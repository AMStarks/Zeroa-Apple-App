#!/usr/bin/env python3
"""
DialoGPT Large AI Companion Server
Enhanced with Christian values and optimized for conversation
"""

import os
import json
import torch
from flask import Flask, request, jsonify
from transformers import AutoModelForCausalLM, AutoTokenizer
import logging
import gc
from datetime import datetime
from christian_prompt_elements import create_christian_prompt, CHRISTIAN_VALUES

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Global variables for model and tokenizer
model = None
tokenizer = None
download_progress = 0
download_status = "Not started"

# Conversation memory system
conversation_memory = {}

def save_conversation_memory():
    """Save conversation memory to file"""
    try:
        with open('nova_conversation_memory.json', 'w') as f:
            json.dump(conversation_memory, f, indent=2)
    except Exception as e:
        logger.error(f"Error saving conversation memory: {e}")

def load_conversation_memory():
    """Load conversation memory from file"""
    try:
        if os.path.exists('nova_conversation_memory.json'):
            with open('nova_conversation_memory.json', 'r') as f:
                data = json.load(f)
                conversation_memory.update(data)
                logger.info(f"✅ Loaded conversation memory for {len(data)} users")
    except Exception as e:
        logger.error(f"Error loading conversation memory: {e}")

def update_progress(progress, status):
    """Update download progress"""
    global download_progress, download_status
    download_progress = progress
    download_status = status
    logger.info(f"📊 Progress: {progress}% - {status}")

def download_and_load_dialogpt_model():
    """Download and load DialoGPT Large model"""
    global model, tokenizer
    
    try:
        model_name = "microsoft/DialoGPT-large"
        local_model_path = "dialogpt_model"
        
        logger.info("🚀 Starting DialoGPT Large download...")
        update_progress(0, "Initializing download...")
        
        # Check available RAM
        import psutil
        available_ram = psutil.virtual_memory().available / (1024**3)
        logger.info(f"💾 Available RAM: {available_ram:.1f}GB")
        
        if available_ram < 8:
            logger.warning("⚠️ Low RAM available. Model may not load properly.")
        
        update_progress(10, "Downloading tokenizer...")
        logger.info("📝 Downloading tokenizer...")
        tokenizer = AutoTokenizer.from_pretrained(model_name)
        update_progress(20, "Tokenizer downloaded successfully")
        
        update_progress(30, "Downloading model (this will take 5-10 minutes)...")
        logger.info("🤖 Downloading DialoGPT Large model...")
        
        # Load model with memory optimization
        model = AutoModelForCausalLM.from_pretrained(
            model_name,
            torch_dtype=torch.float16,
            device_map="auto",
            low_cpu_mem_usage=True,
            max_memory={0: "8GB"}  # Reserve 8GB for the model
        )
        
        update_progress(80, "Model downloaded, saving locally...")
        
        # Save locally
        logger.info("💾 Saving model locally...")
        tokenizer.save_pretrained(local_model_path)
        model.save_pretrained(local_model_path)
        update_progress(90, "Model saved locally")
        
        # Clear memory after loading
        gc.collect()
        torch.cuda.empty_cache() if torch.cuda.is_available() else None
        
        update_progress(100, "Download and loading complete!")
        logger.info("✅ DialoGPT Large downloaded and loaded successfully!")
        return True
        
    except Exception as e:
        logger.error(f"❌ Error downloading/loading model: {e}")
        update_progress(0, f"Error: {str(e)}")
        return False

def create_dialogpt_prompt(user_input: str, user_id: str = "default") -> str:
    """Create a prompt for DialoGPT with Christian values"""
    
    # Get conversation history
    history = conversation_memory.get(user_id, [])
    
    # Start with Christian context
    prompt = "You are Nova, an AI companion with Christian values. You embody love, compassion, and understanding. Respond with warmth, empathy, and gentle wisdom.\n\n"
    
    # Add conversation history
    if history:
        prompt += "Recent conversation:\n"
        for entry in history[-3:]:  # Last 3 exchanges
            prompt += f"User: {entry.get('user_input', '')}\n"
            prompt += f"Nova: {entry.get('response', '')}\n"
        prompt += "\n"
    
    # Add current user input
    prompt += f"User: {user_input}\n"
    prompt += "Nova:"
    
    return prompt

def generate_response(user_input: str, user_id: str = "default") -> str:
    """Generate a response using the DialoGPT model"""
    
    if model is None or tokenizer is None:
        return "I'm sorry, my AI model isn't ready yet. Please try again in a moment."
    
    try:
        # Create prompt
        prompt = create_dialogpt_prompt(user_input, user_id)
        
        # Tokenize input
        inputs = tokenizer(prompt, return_tensors="pt", max_length=1024, truncation=True)
        
        # Move inputs to same device as model
        device = next(model.parameters()).device
        inputs = {k: v.to(device) for k, v in inputs.items()}
        
        # Generate response with optimized parameters for conversation
        with torch.no_grad():
            outputs = model.generate(
                **inputs,
                max_new_tokens=150,
                temperature=0.7,
                do_sample=True,
                top_p=0.9,
                top_k=50,
                pad_token_id=tokenizer.eos_token_id,
                eos_token_id=tokenizer.eos_token_id,
                repetition_penalty=1.1,
                length_penalty=1.0
            )
        
        # Decode response
        generated_text = tokenizer.decode(outputs[0], skip_special_tokens=True)
        
        # Extract only the Nova response part
        response = generated_text.split("Nova:")[-1].strip()
        
        # Clean up response
        if "\n" in response:
            response = response.split("\n")[0].strip()
        
        # Ensure response isn't empty
        if not response or len(response) < 10:
            response = "I understand. How can I help you further?"
        
        # Save to conversation memory
        if user_id not in conversation_memory:
            conversation_memory[user_id] = []
        
        conversation_memory[user_id].append({
            "user_input": user_input,
            "response": response,
            "timestamp": datetime.now().isoformat()
        })
        
        # Keep only last 10 exchanges to manage memory
        if len(conversation_memory[user_id]) > 10:
            conversation_memory[user_id] = conversation_memory[user_id][-10:]
        
        save_conversation_memory()
        
        return response
        
    except Exception as e:
        logger.error(f"❌ Error generating response: {e}")
        return "I'm sorry, I encountered an error. Please try again."

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    model_status = "ready" if model is not None else "loading" if download_progress > 0 else "not_loaded"
    model_name = "DialoGPT-Large" if model is not None else "Not loaded"
    
    return jsonify({
        "status": "healthy",
        "model": model_name,
        "model_status": model_status,
        "download_progress": download_progress,
        "download_status": download_status,
        "timestamp": datetime.now().isoformat()
    })

@app.route('/progress', methods=['GET'])
def get_progress():
    """Get download progress"""
    return jsonify({
        "download_progress": download_progress,
        "download_status": download_status,
        "timestamp": datetime.now().isoformat()
    })

@app.route('/generate', methods=['POST'])
def generate():
    """Generate response endpoint"""
    try:
        data = request.get_json()
        user_input = data.get('input', '')
        user_id = data.get('user_id', 'default')
        
        if not user_input:
            return jsonify({"error": "No input provided"}), 400
        
        logger.info(f"📝 Received input: '{user_input}' from user {user_id}")
        
        response = generate_response(user_input, user_id)
        
        logger.info(f"✅ Generated response: '{response}'")
        
        return jsonify({
            "model": "DialoGPT-Large",
            "response": response,
            "timestamp": datetime.now().isoformat()
        })
        
    except Exception as e:
        logger.error(f"❌ Error in generate endpoint: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/model-info', methods=['GET'])
def model_info():
    """Get model information"""
    return jsonify({
        "model_name": "DialoGPT-Large",
        "parameters": "774M",
        "license": "MIT (completely open)",
        "features": ["Christian values", "Conversational AI", "Emotional support"],
        "ram_usage": "~4GB",
        "download_size": "~3GB"
    })

if __name__ == '__main__':
    # Load conversation memory
    load_conversation_memory()
    
    logger.info("🚀 Starting DialoGPT Large Server...")
    logger.info("💾 Available RAM: 24GB - should be sufficient for DialoGPT")
    logger.info("⚠️ This will download ~3GB of model data (5-10 minutes)")
    logger.info("📊 Progress will be available at http://127.0.0.1:5002/progress")
    
    # Download and load model
    success = download_and_load_dialogpt_model()
    
    if success:
        logger.info("✅ DialoGPT Large downloaded and loaded successfully!")
        logger.info("✅ Server ready at http://127.0.0.1:5002")
        app.run(host='127.0.0.1', port=5002, debug=False)
    else:
        logger.error("❌ Failed to load DialoGPT model")
        exit(1) 
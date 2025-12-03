#!/usr/bin/env python3
"""
Voxtral-Mini-3B Local AI Companion Server
Enhanced with Christian values and better conversation quality
Uses locally downloaded model files
"""

import os
import json
import torch
from flask import Flask, request, jsonify
from transformers import AutoModelForCausalLM, AutoTokenizer
import logging
import gc
from datetime import datetime

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

def load_voxtral_local_model():
    """Load Voxtral-Mini-3B model from local files"""
    global model, tokenizer
    
    try:
        local_model_path = "/Users/starkers/voxtral_local"
        
        logger.info("🚀 Loading Voxtral-Mini-3B from local files...")
        update_progress(0, "Initializing local model loading...")
        
        # Check if local files exist (updated for actual file structure)
        required_files = [
            "config.json",
            "tokenizer.json", 
            "tokenizer_config.json",
            "special_tokens_map.json",
            "model.safetensors.index.json",
            "model-00001-of-0002.safetensors",
            "model-00002-of-0002.safetensors"
        ]
        
        missing_files = []
        for file in required_files:
            if not os.path.exists(os.path.join(local_model_path, file)):
                missing_files.append(file)
        
        if missing_files:
            logger.error(f"❌ Missing required files: {missing_files}")
            update_progress(0, f"Error: Missing files {missing_files}")
            return False
        
        update_progress(20, "Loading tokenizer from local files...")
        logger.info("📝 Loading tokenizer...")
        
        # Load tokenizer with all required files now present
        tokenizer = AutoTokenizer.from_pretrained(local_model_path)
        update_progress(40, "Tokenizer loaded successfully")
        
        update_progress(60, "Loading model from local files...")
        logger.info("🤖 Loading Voxtral-Mini-3B model...")
        
        # Load model with better device mapping
        model = AutoModelForCausalLM.from_pretrained(
            local_model_path,
            torch_dtype=torch.float16,
            device_map="auto",
            trust_remote_code=True,
            low_cpu_mem_usage=True,
            max_memory={0: "4GB", "cpu": "8GB"}  # Better memory allocation
        )
        
        update_progress(90, "Model loaded successfully")
        
        # Clear memory after loading
        gc.collect()
        torch.cuda.empty_cache() if torch.cuda.is_available() else None
        
        update_progress(100, "Local model loading complete!")
        logger.info("✅ Voxtral-Mini-3B loaded successfully from local files!")
        return True
        
    except Exception as e:
        logger.error(f"❌ Error loading local model: {e}")
        update_progress(0, f"Error: {str(e)}")
        return False

def create_companion_prompt(user_input: str, user_id: str = "default") -> str:
    """Create a prompt for the AI companion with Christian values and memory"""
    
    # Get conversation history
    history = conversation_memory.get(user_id, [])
    
    # Christian context
    christian_context = """
    You are Nova, an AI companion with Christian values. You embody:
    - Love, compassion, and understanding
    - Wisdom and guidance based on biblical principles
    - Encouragement and hope in difficult times
    - Respect for all people as created in God's image
    - Humility and service to others
    
    Respond with warmth, empathy, and gentle wisdom. When appropriate, 
    offer comfort and guidance that reflects Christian values without being preachy.
    Keep responses concise but meaningful.
    """
    
    # Build conversation context
    context = christian_context + "\n\n"
    
    # Add recent conversation history
    if history:
        context += "Recent conversation:\n"
        for entry in history[-3:]:  # Last 3 exchanges
            context += f"User: {entry.get('user_input', '')}\n"
            context += f"Assistant: {entry.get('response', '')}\n"
        context += "\n"
    
    # Add current user input
    context += f"User: {user_input}\n"
    context += "Assistant:"
    
    return context

def get_model_device():
    """Get the primary device for the model, handling device mapping properly"""
    try:
        # Check if model has device_map attribute
        if hasattr(model, 'hf_device_map'):
            # Get the first device from the device map
            first_device = list(model.hf_device_map.values())[0]
            if first_device == 'cpu':
                return torch.device('cpu')
            elif first_device == 'mps:0':
                return torch.device('mps')
            else:
                return torch.device('cpu')  # Fallback to CPU
        else:
            # Fallback to checking parameters
            return next(model.parameters()).device
    except Exception as e:
        logger.warning(f"Could not determine model device, using CPU: {e}")
        return torch.device('cpu')

def generate_response(user_input: str, user_id: str = "default") -> str:
    """Generate a response using the Voxtral model with fixed device mapping"""
    
    if model is None or tokenizer is None:
        return "I'm sorry, my AI model isn't ready yet. Please try again in a moment."
    
    try:
        # Create prompt
        prompt = create_companion_prompt(user_input, user_id)
        
        # Tokenize input
        inputs = tokenizer(prompt, return_tensors="pt", max_length=2048, truncation=True)
        
        # Get the correct device for the model
        device = get_model_device()
        logger.info(f"🔧 Using device: {device}")
        
        # Move inputs to the correct device
        inputs = {k: v.to(device) for k, v in inputs.items()}
        
        # Generate response
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
                repetition_penalty=1.1
            )
        
        # Decode response
        generated_text = tokenizer.decode(outputs[0], skip_special_tokens=True)
        
        # Extract only the Assistant response part
        response = generated_text.split("Assistant:")[-1].strip()
        
        # Clean up response
        if "\n" in response:
            response = response.split("\n")[0].strip()
        
        # Ensure response isn't empty
        if not response or len(response) < 5:
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
    model_name = "Voxtral-Mini-3B-Local" if model is not None else "Not loaded"
    
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
            "model": "Voxtral-Mini-3B-Local",
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
        "model_name": "Voxtral-Mini-3B-Local",
        "parameters": "3B",
        "license": "Apache 2.0",
        "features": ["Christian values", "Conversational AI", "Emotional support", "Local files"],
        "ram_usage": "~4GB",
        "source": "Local files"
    })

if __name__ == '__main__':
    # Load conversation memory
    load_conversation_memory()
    
    logger.info("🚀 Starting Voxtral-Mini-3B Local Server...")
    logger.info("📁 Loading from: /Users/starkers/voxtral_local")
    logger.info("📊 Progress will be available at http://127.0.0.1:5010/progress")
    
    # Load model from local files
    success = load_voxtral_local_model()
    
    if success:
        logger.info("✅ Voxtral-Mini-3B loaded successfully from local files!")
        logger.info("✅ Server ready at http://127.0.0.1:5010")
        app.run(host='127.0.0.1', port=5010, debug=False)
    else:
        logger.error("❌ Failed to load Voxtral from local files")
        exit(1) 
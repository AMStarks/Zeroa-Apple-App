#!/usr/bin/env python3
"""
Phi-3-mini-4k-instruct AI Companion Server (Robust Version)
Properly handles model loading with sufficient RAM
"""

import os
import json
import torch
from flask import Flask, request, jsonify
from transformers import AutoModelForCausalLM, AutoTokenizer
import logging
import gc
import time

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Global variables for model and tokenizer
model = None
tokenizer = None

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
    global conversation_memory
    try:
        if os.path.exists('nova_conversation_memory.json'):
            with open('nova_conversation_memory.json', 'r') as f:
                conversation_memory = json.load(f)
            logger.info(f"✅ Loaded conversation memory for {len(conversation_memory)} users")
    except Exception as e:
        logger.error(f"Error loading conversation memory: {e}")
        conversation_memory = {}

def load_phi3_model():
    """Load Phi-3-mini-4k-instruct model with proper memory management"""
    global model, tokenizer
    
    logger.info("🚀 Loading Microsoft/Phi-3-mini-4k-instruct (Robust)...")
    
    # Model configuration
    model_name = "microsoft/Phi-3-mini-4k-instruct"
    local_model_path = "phi3_model"
    
    try:
        # Check if model exists locally
        if os.path.exists(local_model_path):
            logger.info("📝 Loading tokenizer from local storage...")
            tokenizer = AutoTokenizer.from_pretrained(local_model_path)
            tokenizer.pad_token = tokenizer.eos_token
            
            logger.info("🤖 Loading model from local storage (robust loading)...")
            
            # Clear memory before loading
            gc.collect()
            torch.cuda.empty_cache() if torch.cuda.is_available() else None
            
            # Load model with proper memory management
            model = AutoModelForCausalLM.from_pretrained(
                local_model_path,
                torch_dtype=torch.float16,
                device_map="auto",  # Let it automatically handle device placement
                attn_implementation="eager",
                low_cpu_mem_usage=True,
                max_memory={0: "20GB"}  # Reserve 20GB for the model
            )
            
            logger.info("✅ Model loaded successfully!")
            
            # Test a simple generation to ensure it works
            logger.info("🧪 Testing model with simple generation...")
            test_input = tokenizer("Hello", return_tensors="pt", max_length=10, truncation=True)
            with torch.no_grad():
                test_output = model.generate(**test_input, max_new_tokens=5, do_sample=False)
            logger.info("✅ Model test successful!")
            
        else:
            logger.info("📥 Model not found locally, downloading...")
            logger.info(f"🚀 Downloading {model_name}...")
            
            # Download tokenizer
            logger.info("📝 Downloading tokenizer...")
            tokenizer = AutoTokenizer.from_pretrained(model_name)
            tokenizer.pad_token = tokenizer.eos_token
            
            # Download model with memory optimization
            logger.info("🤖 Downloading model (this may take a while)...")
            model = AutoModelForCausalLM.from_pretrained(
                model_name,
                torch_dtype=torch.float16,
                device_map="auto",
                attn_implementation="eager",
                low_cpu_mem_usage=True,
                max_memory={0: "20GB"}
            )
            
            # Save locally
            logger.info("💾 Saving model locally...")
            tokenizer.save_pretrained(local_model_path)
            model.save_pretrained(local_model_path)
            logger.info("✅ Model saved locally")
        
        # Clear memory after loading
        gc.collect()
        torch.cuda.empty_cache() if torch.cuda.is_available() else None
        
        logger.info("✅ Microsoft/Phi-3-mini-4k-instruct loaded successfully!")
        return True
        
    except Exception as e:
        logger.error(f"❌ Error loading model: {e}")
        return False

def create_companion_prompt(user_input: str, user_id: str = "default") -> str:
    """Create a prompt for the AI companion with Christian values and memory"""
    
    # Get conversation history
    history = conversation_memory.get(user_id, [])
    
    # Christian values and personality
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
    
    # Add recent conversation history (last 3 exchanges to save tokens)
    if history:
        context += "Recent conversation:\n"
        for entry in history[-3:]:
            context += f"User: {entry.get('user_input', '')}\n"
            context += f"Nova: {entry.get('response', '')}\n"
        context += "\n"
    
    # Add current user input
    context += f"User: {user_input}\n"
    context += "Nova:"
    
    return context

def generate_response(user_input: str, user_id: str = "default") -> str:
    """Generate a response using the Phi-3 model"""
    
    if model is None or tokenizer is None:
        return "I'm sorry, my AI model isn't ready yet. Please try again in a moment."
    
    try:
        # Create prompt
        prompt = create_companion_prompt(user_input, user_id)
        
        # Tokenize input
        inputs = tokenizer(prompt, return_tensors="pt", max_length=2048, truncation=True)
        
        # Move inputs to same device as model
        device = next(model.parameters()).device
        inputs = {k: v.to(device) for k, v in inputs.items()}
        
        # Generate response
        with torch.no_grad():
            outputs = model.generate(
                **inputs,
                max_new_tokens=150,
                temperature=0.7,
                do_sample=True,
                pad_token_id=tokenizer.eos_token_id,
                eos_token_id=tokenizer.eos_token_id,
                repetition_penalty=1.1
            )
        
        # Decode response
        generated_text = tokenizer.decode(outputs[0], skip_special_tokens=True)
        
        # Extract only the Nova response part
        response = generated_text.split("Nova:")[-1].strip()
        
        # Clean up response
        if response.startswith("User:"):
            response = response.split("User:")[0].strip()
        
        # Update conversation memory
        if user_id not in conversation_memory:
            conversation_memory[user_id] = []
        
        conversation_memory[user_id].append({
            "timestamp": datetime.now().isoformat(),
            "user_input": user_input,
            "response": response
        })
        
        # Keep only last 10 exchanges
        if len(conversation_memory[user_id]) > 10:
            conversation_memory[user_id] = conversation_memory[user_id][-10:]
        
        # Save memory
        save_conversation_memory()
        
        return response
        
    except Exception as e:
        logger.error(f"❌ Error generating response: {e}")
        return "I'm sorry, I'm having trouble processing your request right now. Please try again."

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    model_status = "ready" if model is not None else "loading"
    return jsonify({
        "status": "healthy",
        "model": "Phi-3-mini-4k-instruct",
        "model_status": model_status,
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
        
        # Generate response
        response = generate_response(user_input, user_id)
        
        logger.info(f"✅ Generated response: '{response}'")
        
        return jsonify({
            "response": response,
            "model": "Phi-3-mini-4k-instruct",
            "timestamp": datetime.now().isoformat()
        })
        
    except Exception as e:
        logger.error(f"❌ Error generating response: {e}")
        return jsonify({"error": "Internal server error"}), 500

@app.route('/model-info', methods=['GET'])
def model_info():
    """Model information endpoint"""
    return jsonify({
        "model": "Phi-3-mini-4k-instruct",
        "version": "1.0.0",
        "description": "Microsoft Phi-3-mini-4k-instruct with Christian values",
        "status": "ready" if model is not None else "loading"
    })

if __name__ == '__main__':
    from datetime import datetime
    
    # Load conversation memory
    load_conversation_memory()
    
    logger.info("🚀 Starting Phi-3 Robust Server...")
    logger.info("💾 Available RAM: 24GB - should be sufficient for Phi-3")
    
    # Load model directly (no background loading)
    success = load_phi3_model()
    
    if success:
        logger.info("✅ Phi-3 model loaded successfully!")
        logger.info("✅ Server ready at http://127.0.0.1:5002")
    else:
        logger.error("❌ Failed to load Phi-3 model")
        logger.info("⚠️ Server will start but model won't be available")
    
    # Run the server
    app.run(host='127.0.0.1', port=5002, debug=False) 
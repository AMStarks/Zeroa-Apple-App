#!/usr/bin/env python3
"""
Working AI Server with DialoGPT
Provides real conversational AI responses
"""

import os
import json
import time
from flask import Flask, request, jsonify
from flask_cors import CORS
from transformers import AutoTokenizer, AutoModelForCausalLM
import torch

app = Flask(__name__)
CORS(app)

# Global model and tokenizer
model = None
tokenizer = None
device = "cpu"

def load_dialogpt_model():
    """Load the DialoGPT model"""
    global model, tokenizer
    
    print("📦 Loading DialoGPT model...")
    
    try:
        model_name = "microsoft/DialoGPT-small"
        
        print(f"🔄 Loading {model_name}...")
        
        tokenizer = AutoTokenizer.from_pretrained(model_name)
        model = AutoModelForCausalLM.from_pretrained(model_name)
        
        model = model.to(device)
        model.eval()
        
        print(f"✅ Model loaded successfully")
        print(f"📊 Model parameters: {sum(p.numel() for p in model.parameters()):,}")
        
        return True
        
    except Exception as e:
        print(f"❌ Failed to load model: {e}")
        import traceback
        traceback.print_exc()
        return False

def generate_response(message, user_name="User", context=None):
    """Generate real AI response using DialoGPT"""
    global model, tokenizer
    
    if model is None or tokenizer is None:
        return "Error: Model not loaded"
    
    try:
        print(f"🤖 Generating response for: {message}")
        
        # Encode the input
        input_ids = tokenizer.encode(message + tokenizer.eos_token, return_tensors='pt')
        
        # Generate response
        with torch.no_grad():
            output_ids = model.generate(
                input_ids,
                max_length=input_ids.shape[-1] + 50,
                pad_token_id=tokenizer.eos_token_id,
                temperature=0.7,
                do_sample=True,
                top_p=0.9,
                repetition_penalty=1.2
            )
        
        # Decode the response
        response = tokenizer.decode(output_ids[:, input_ids.shape[-1]:][0], skip_special_tokens=True)
        
        # Clean up response
        response = response.strip()
        
        # Limit response length
        if len(response) > 200:
            response = response[:200] + "..."
        
        print(f"✅ Generated response: {response}")
        return response
        
    except Exception as e:
        print(f"❌ Generation failed: {e}")
        import traceback
        traceback.print_exc()
        return f"Error: Failed to generate response - {str(e)}"

@app.route('/chat', methods=['POST'])
def chat():
    """Handle chat requests"""
    try:
        data = request.get_json()
        message = data.get('message', '')
        user_name = data.get('user_name', 'User')
        context = data.get('context', {})
        
        if not message:
            return jsonify({"error": "No message provided"}), 400
        
        print(f"📨 Received message from {user_name}: {message}")
        
        # Generate real AI response
        response = generate_response(message, user_name, context)
        
        return jsonify({
            "response": response,
            "user_name": user_name,
            "timestamp": time.time()
        })
        
    except Exception as e:
        print(f"❌ Chat endpoint error: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy",
        "model_loaded": model is not None,
        "tokenizer_loaded": tokenizer is not None
    })

@app.route('/', methods=['GET'])
def root():
    """Root endpoint"""
    return jsonify({
        "message": "DialoGPT AI Server is running",
        "endpoints": ["/chat", "/health"]
    })

if __name__ == '__main__':
    print("🚀 Starting DialoGPT AI Server...")
    
    # Load the model
    if load_dialogpt_model():
        print("✅ Server ready! Starting on http://localhost:5001")
        app.run(host='0.0.0.0', port=5001, debug=True)
    else:
        print("❌ Failed to load model. Server cannot start.") 
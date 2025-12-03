#!/usr/bin/env python3
"""
Simple test server to debug TinyLlama
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

def load_model():
    """Load the TinyLlama model"""
    global model, tokenizer
    
    print("📦 Loading TinyLlama model...")
    
    try:
        model_name = "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
        print(f"🔄 Loading {model_name}...")
        
        tokenizer = AutoTokenizer.from_pretrained(model_name)
        model = AutoModelForCausalLM.from_pretrained(
            model_name,
            torch_dtype=torch.float16,
            low_cpu_mem_usage=True
        )
        
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

def generate_response(message):
    """Generate response"""
    global model, tokenizer
    
    if model is None or tokenizer is None:
        return "Error: Model not loaded"
    
    try:
        # Use the proper TinyLlama chat format
        prompt = f"<|im_start|>user\n{message}<|im_end|>\n<|im_start|>assistant\n"
        
        print(f"🤖 Generating response for: {message}")
        print(f"📝 Prompt: {prompt}")
        
        inputs = tokenizer(prompt, return_tensors="pt", max_length=256, truncation=True)
        input_ids = inputs["input_ids"].to(device)
        
        with torch.no_grad():
            outputs = model.generate(
                input_ids,
                max_length=input_ids.shape[1] + 50,
                temperature=0.7,
                do_sample=True,
                pad_token_id=tokenizer.eos_token_id,
                eos_token_id=tokenizer.eos_token_id
            )
        
        generated_ids = outputs[0][input_ids.shape[1]:]
        response = tokenizer.decode(generated_ids, skip_special_tokens=True)
        
        response = response.strip()
        print(f"✅ Generated response: {response}")
        return response
        
    except Exception as e:
        print(f"❌ Generation failed: {e}")
        import traceback
        traceback.print_exc()
        return f"Error: {str(e)}"

@app.route('/chat', methods=['POST'])
def chat():
    """Handle chat requests"""
    try:
        data = request.get_json()
        message = data.get('message', '')
        
        if not message:
            return jsonify({"error": "No message provided"}), 400
        
        print(f"📨 Received message: {message}")
        response = generate_response(message)
        
        return jsonify({
            "response": response,
            "timestamp": time.time()
        })
        
    except Exception as e:
        print(f"❌ Chat endpoint error: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/health', methods=['GET'])
def health():
    """Health check"""
    return jsonify({
        "status": "healthy",
        "model_loaded": model is not None
    })

if __name__ == '__main__':
    print("🚀 Starting Simple TinyLlama Server...")
    
    if load_model():
        print("✅ Server ready! Starting on http://localhost:5001")
        app.run(host='0.0.0.0', port=5001, debug=True)
    else:
        print("❌ Failed to load model. Server cannot start.") 
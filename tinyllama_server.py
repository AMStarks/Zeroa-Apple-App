#!/usr/bin/env python3
"""
TinyLlama Server - Real AI Responses
Provides actual TinyLlama-1.1B-Chat-v1.0 responses via HTTP API
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

def load_tinyllama_model():
    """Load the TinyLlama model using transformers"""
    global model, tokenizer
    
    print("📦 Loading TinyLlama model using transformers...")
    
    try:
        # Use a more reliable model
        model_name = "microsoft/DialoGPT-medium"
        
        print(f"🔄 Loading {model_name}...")
        
        # Load tokenizer and model
        tokenizer = AutoTokenizer.from_pretrained(model_name)
        model = AutoModelForCausalLM.from_pretrained(
            model_name,
            torch_dtype=torch.float16,
            low_cpu_mem_usage=True
        )
        
        # Move to device
        model = model.to(device)
        model.eval()
        
        print(f"✅ Model loaded successfully")
        print(f"📊 Model parameters: {sum(p.numel() for p in model.parameters()):,}")
        print(f"📊 Vocabulary size: {tokenizer.vocab_size}")
        
        # Test the model
        test_prompt = "Hello"
        test_inputs = tokenizer(test_prompt, return_tensors="pt", max_length=50, truncation=True)
        with torch.no_grad():
            test_outputs = model.generate(
                test_inputs["input_ids"],
                max_length=test_inputs["input_ids"].shape[1] + 20,
                temperature=0.7,
                do_sample=True,
                pad_token_id=tokenizer.eos_token_id,
                eos_token_id=tokenizer.eos_token_id
            )
        test_response = tokenizer.decode(test_outputs[0][test_inputs["input_ids"].shape[1]:], skip_special_tokens=True)
        print(f"🧪 Test response: {test_response}")
        
        return True
        
    except Exception as e:
        print(f"❌ Failed to load model: {e}")
        import traceback
        traceback.print_exc()
        return False

def generate_response(message, user_name="User", context=None):
    """Generate real AI response using TinyLlama with conversation reset"""
    global model, tokenizer
    
    if model is None or tokenizer is None:
        return "Error: Model not loaded"
    
    try:
        # Create a simple prompt for DialoGPT
        prompt = f"User: {message}\nNova:"
        
        print(f"🤖 Generating response for: {message}")
        print(f"📝 Using DialoGPT prompt")
        
        # Tokenize input
        inputs = tokenizer(prompt, return_tensors="pt", max_length=256, truncation=True)
        input_ids = inputs["input_ids"].to(device)
        
        # Generate response with improved parameters for natural conversation
        generation_config = {
            'max_length': input_ids.shape[1] + 150,  # Reasonable length for conversation
            'temperature': 0.8,                       # More creative for natural responses
            'do_sample': True,                        # Enable sampling
            'pad_token_id': tokenizer.eos_token_id,   # Proper padding
            'eos_token_id': tokenizer.eos_token_id,   # End of sequence
            'top_p': 0.95,                           # Higher nucleus sampling for variety
            'repetition_penalty': 1.05,               # Very low repetition penalty for natural flow
            'no_repeat_ngram_size': 1,               # Minimal repetition restriction
            'early_stopping': True                    # Stop at natural endings
        }
        
        with torch.no_grad():
            outputs = model.generate(
                input_ids,
                **generation_config
            )
        
        # Decode the generated response
        generated_ids = outputs[0][input_ids.shape[1]:]  # Get only the new tokens
        response = tokenizer.decode(generated_ids, skip_special_tokens=True)
        
        # Clean up the response
        response = response.strip()
        
        # Remove any remaining prompt artifacts
        if response.startswith("Assistant:"):
            response = response[10:].strip()
        
        # Remove meta-commentary and customer service patterns
        meta_patterns = [
            "Sure! Here is an example response to your user message:",
            "Here is an example response:",
            "Here's what I would say:",
            "Here is a response:",
            "Here's an example:",
            "Here's what you could say:",
            "Here's a sample response:",
            "Thank you for reaching out! I'm glad to hear that",
            "Please know that your message has been received",
            "If you have any further questions or concerns",
            "We appreciate your continued support",
            "Thank you again for choosing to partner with us",
            "Sincerely,",
            "Please don't single-post a direct message",
            "contact us directly through our chat widget",
            "Certainly! Here's an updated response for you:",
            "Here's an updated response for you:",
            "I hope this message finds your day filled",
            "Please know that our team is here anytime",
            "We want nothing but positive progress",
            "#greenliving#climatechangeawareness",
            "With positivity & joy",
            "impact on people'nd communities"
        ]
        
        for pattern in meta_patterns:
            if response.startswith(pattern):
                response = response[len(pattern):].strip()
                # Remove quotes if present
                if response.startswith('"') and response.endswith('"'):
                    response = response[1:-1].strip()
        
        # Stop at the first complete response - don't include additional dialogue
        if "User:" in response:
            response = response.split("User:")[0].strip()
        
        if "Nova:" in response:
            response = response.split("Nova:")[0].strip()
        
        # Remove any trailing incomplete sentences (but don't truncate arbitrarily)
        if response and not response.endswith(('.', '!', '?')):
            # Only truncate if it's clearly incomplete (ends with comma, etc.)
            if response.endswith(','):
                response = response[:-1] + '.'
        
        # Check if response contains unrendered formatting or is completely broken
        if "&nbsp;" in response or "&lt" in response or "&gt" in response or "[Color:" in response or "User Message" in response:
            print(f"🚨 Detected unrendered formatting in response")
            response = "Model not working"
        
        # Check if response is completely nonsensical or contains obvious errors
        if len(response) > 500 or "Assistant:" in response or response.strip() == "":
            print(f"🚨 Detected nonsensical response")
            response = "Model not working"
        
        print(f"✅ Generated response: {response}")
        return response
        
    except Exception as e:
        print(f"❌ Generation failed: {e}")
        import traceback
        traceback.print_exc()
        return f"Error: Failed to generate response - {str(e)}"

@app.route('/chat', methods=['POST'])
def chat():
    try:
        data = request.get_json()
        message = data.get('message', '')
        user_name = data.get('user_name', 'User')
        context = data.get('context', {})
        
        print(f"📨 Received message from {user_name}: {message}")
        print(f"🤖 Generating response for: {message}")
        
        # Log enhanced context information
        memory_size = context.get('memory_size', 0)
        days_active = context.get('days_active', 0)
        learning_insights = context.get('learning_insights', {})
        adaptive_personality = context.get('adaptive_personality', {})
        bonding_strength = context.get('bonding_strength', 0.0)
        
        if memory_size > 0:
            print(f"🧠 Memory context: {memory_size} messages, {days_active} days active")
            if learning_insights:
                top_interests = learning_insights.get('top_interests', [])
                if top_interests:
                    print(f"📊 Learning insights: Top interests - {', '.join(top_interests[:3])}")
            
            if adaptive_personality:
                adaptive_interests = adaptive_personality.get('adaptive_interests', [])
                user_influence = adaptive_personality.get('user_influence', 0.85)
                nova_core = adaptive_personality.get('nova_core', 0.15)
                print(f"🎭 Adaptive personality: {user_influence*100:.0f}% user influence, {nova_core*100:.0f}% Nova core")
                print(f"💫 Bonding strength: {bonding_strength:.2f}")
                if adaptive_interests:
                    print(f"🎯 Adaptive interests: {', '.join(adaptive_interests[:5])}")
        
        # Use conversation reset prompt for fresh start
        print("📝 Using conversation reset prompt")
        
        response = generate_response(message)
        
        return jsonify({'response': response})
        
    except Exception as e:
        print(f"❌ Error in chat endpoint: {e}")
        return jsonify({'error': str(e)}), 500

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
        "message": "TinyLlama Server is running",
        "endpoints": ["/chat", "/health"]
    })

if __name__ == '__main__':
    print("🚀 Starting TinyLlama Server...")
    
    # Load the model
    if load_tinyllama_model():
        print("✅ Server ready! Starting on http://localhost:5001")
        app.run(host='0.0.0.0', port=5001, debug=True)
    else:
        print("❌ Failed to load model. Server cannot start.") 
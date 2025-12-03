#!/usr/bin/env python3
"""
Test simple model to verify AI responses
"""

import torch
from transformers import AutoTokenizer, AutoModelForCausalLM

def test_simple_model():
    """Test with a simpler model"""
    print("🧪 Testing simple model...")
    
    try:
        # Try a different, simpler model
        model_name = "microsoft/DialoGPT-small"
        
        print(f"🔄 Loading {model_name}...")
        
        tokenizer = AutoTokenizer.from_pretrained(model_name)
        model = AutoModelForCausalLM.from_pretrained(model_name)
        
        # Test simple conversation
        user_input = "Hello"
        
        # Encode the input
        input_ids = tokenizer.encode(user_input + tokenizer.eos_token, return_tensors='pt')
        
        # Generate response
        with torch.no_grad():
            output_ids = model.generate(
                input_ids,
                max_length=50,
                pad_token_id=tokenizer.eos_token_id,
                temperature=0.7,
                do_sample=True
            )
        
        response = tokenizer.decode(output_ids[:, input_ids.shape[-1]:][0], skip_special_tokens=True)
        
        print(f"✅ Test response: {response}")
        return response
        
    except Exception as e:
        print(f"❌ Test failed: {e}")
        return None

if __name__ == "__main__":
    test_simple_model() 
#!/usr/bin/env python3
"""
Test different models to find one that works properly for chat
"""

import torch
from transformers import AutoTokenizer, AutoModelForCausalLM

def test_different_models():
    """Test different models to find one that works for chat"""
    
    print("🔍 Testing different models for chat...")
    
    # Test different models
    models_to_test = [
        {
            "name": "TinyLlama-1.1B-Chat-v1.0",
            "model_id": "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
        },
        {
            "name": "TinyLlama-1.1B-Chat-v1.0 (different prompt)",
            "model_id": "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
        },
        {
            "name": "DialoGPT-small",
            "model_id": "microsoft/DialoGPT-small"
        }
    ]
    
    test_message = "Hello"
    
    for model_test in models_to_test:
        print(f"\n🧪 Testing: {model_test['name']}")
        
        try:
            # Load model
            tokenizer = AutoTokenizer.from_pretrained(model_test['model_id'])
            model = AutoModelForCausalLM.from_pretrained(
                model_test['model_id'],
                torch_dtype=torch.float16,
                low_cpu_mem_usage=True
            )
            model.eval()
            
            # Test different prompts based on model
            if "DialoGPT" in model_test['name']:
                prompt = f"User: {test_message}\nAssistant:"
            elif "different prompt" in model_test['name']:
                # Try a different prompt format for TinyLlama
                prompt = f"<|im_start|>user\n{test_message}<|im_end|>\n<|im_start|>assistant\n"
            else:
                prompt = f"User: {test_message}\nAssistant:"
            
            print(f"📝 Prompt: {prompt}")
            
            # Tokenize
            inputs = tokenizer(prompt, return_tensors="pt", max_length=256, truncation=True)
            
            # Generate
            with torch.no_grad():
                outputs = model.generate(
                    inputs["input_ids"],
                    max_length=inputs["input_ids"].shape[1] + 20,
                    temperature=0.7,
                    do_sample=True,
                    pad_token_id=tokenizer.eos_token_id,
                    eos_token_id=tokenizer.eos_token_id,
                    top_p=0.9,
                    repetition_penalty=1.1
                )
            
            # Decode
            generated_ids = outputs[0][inputs["input_ids"].shape[1]:]
            response = tokenizer.decode(generated_ids, skip_special_tokens=True)
            
            print(f"✅ Response: {response}")
            
        except Exception as e:
            print(f"❌ Error: {e}")

if __name__ == "__main__":
    test_different_models() 
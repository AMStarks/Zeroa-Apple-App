#!/usr/bin/env python3
"""
Test different TinyLlama chat formats to find the correct one
"""

import torch
from transformers import AutoTokenizer, AutoModelForCausalLM

def test_tinyllama_formats():
    """Test different TinyLlama chat formats"""
    
    print("🔍 Testing TinyLlama chat formats...")
    
    # Load model
    model_name = "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
    tokenizer = AutoTokenizer.from_pretrained(model_name)
    model = AutoModelForCausalLM.from_pretrained(
        model_name,
        torch_dtype=torch.float16,
        low_cpu_mem_usage=True
    )
    model.eval()
    
    test_message = "Hello, how are you?"
    
    # Test different formats
    formats = [
        {
            "name": "Current Format (im_start/im_end)",
            "prompt": f"<|im_start|>user\n{test_message}<|im_end|>\n<|im_start|>assistant\n"
        },
        {
            "name": "Simple User/Assistant",
            "prompt": f"User: {test_message}\nAssistant:"
        },
        {
            "name": "System/User/Assistant",
            "prompt": f"<|system|>\nYou are a helpful assistant.\n<|end|>\n<|user|>\n{test_message}\n<|end|>\n<|assistant|>\n"
        },
        {
            "name": "Llama2 Chat Format",
            "prompt": f"[INST] {test_message} [/INST]"
        },
        {
            "name": "Simple Assistant",
            "prompt": f"Assistant: {test_message}\nUser:"
        },
        {
            "name": "Direct Question",
            "prompt": test_message
        }
    ]
    
    for format_test in formats:
        print(f"\n🧪 Testing: {format_test['name']}")
        print(f"📝 Prompt: {format_test['prompt']}")
        
        try:
            # Tokenize
            inputs = tokenizer(format_test['prompt'], return_tensors="pt", max_length=256, truncation=True)
            
            # Generate
            with torch.no_grad():
                outputs = model.generate(
                    inputs["input_ids"],
                    max_length=inputs["input_ids"].shape[1] + 30,
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
    test_tinyllama_formats() 
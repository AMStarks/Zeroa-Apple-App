#!/usr/bin/env python3
"""
Test TinyLlama conversation reset to see if state persistence is the issue
"""

import torch
from transformers import AutoTokenizer, AutoModelForCausalLM

def test_tinyllama_reset():
    """Test if TinyLlama has persistent conversation state"""
    
    print("🔍 Testing TinyLlama conversation reset...")
    
    # Load model
    model_name = "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
    tokenizer = AutoTokenizer.from_pretrained(model_name)
    model = AutoModelForCausalLM.from_pretrained(
        model_name,
        torch_dtype=torch.float16,
        low_cpu_mem_usage=True
    )
    model.eval()
    
    test_message = "Hello"
    
    print(f"\n🧪 Test 1: Fresh model instance")
    print(f"📝 Prompt: User: {test_message}\nAssistant:")
    
    # Test 1: Fresh model
    inputs = tokenizer(f"User: {test_message}\nAssistant:", return_tensors="pt", max_length=256, truncation=True)
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
    generated_ids = outputs[0][inputs["input_ids"].shape[1]:]
    response = tokenizer.decode(generated_ids, skip_special_tokens=True)
    print(f"✅ Response: {response}")
    
    print(f"\n🧪 Test 2: Same model instance, different prompt")
    print(f"📝 Prompt: User: Hi there\nAssistant:")
    
    # Test 2: Same model, different prompt
    inputs2 = tokenizer("User: Hi there\nAssistant:", return_tensors="pt", max_length=256, truncation=True)
    with torch.no_grad():
        outputs2 = model.generate(
            inputs2["input_ids"],
            max_length=inputs2["input_ids"].shape[1] + 20,
            temperature=0.7,
            do_sample=True,
            pad_token_id=tokenizer.eos_token_id,
            eos_token_id=tokenizer.eos_token_id,
            top_p=0.9,
            repetition_penalty=1.1
        )
    generated_ids2 = outputs2[0][inputs2["input_ids"].shape[1]:]
    response2 = tokenizer.decode(generated_ids2, skip_special_tokens=True)
    print(f"✅ Response: {response2}")
    
    print(f"\n🧪 Test 3: Reset with system prompt")
    system_prompt = "You are a helpful AI assistant. Start fresh with each conversation."
    prompt3 = f"{system_prompt}\n\nUser: {test_message}\nAssistant:"
    print(f"📝 Prompt: {prompt3}")
    
    inputs3 = tokenizer(prompt3, return_tensors="pt", max_length=256, truncation=True)
    with torch.no_grad():
        outputs3 = model.generate(
            inputs3["input_ids"],
            max_length=inputs3["input_ids"].shape[1] + 20,
            temperature=0.7,
            do_sample=True,
            pad_token_id=tokenizer.eos_token_id,
            eos_token_id=tokenizer.eos_token_id,
            top_p=0.9,
            repetition_penalty=1.1
        )
    generated_ids3 = outputs3[0][inputs3["input_ids"].shape[1]:]
    response3 = tokenizer.decode(generated_ids3, skip_special_tokens=True)
    print(f"✅ Response: {response3}")
    
    print(f"\n🧪 Test 4: Different TinyLlama model")
    print("Testing if there's a different TinyLlama model that works better...")
    
    # Test with a different TinyLlama variant
    try:
        model_name2 = "TinyLlama/TinyLlama-1.1B-intermediate-step-1431k-3T"
        tokenizer2 = AutoTokenizer.from_pretrained(model_name2)
        model2 = AutoModelForCausalLM.from_pretrained(
            model_name2,
            torch_dtype=torch.float16,
            low_cpu_mem_usage=True
        )
        model2.eval()
        
        inputs4 = tokenizer2(f"User: {test_message}\nAssistant:", return_tensors="pt", max_length=256, truncation=True)
        with torch.no_grad():
            outputs4 = model2.generate(
                inputs4["input_ids"],
                max_length=inputs4["input_ids"].shape[1] + 20,
                temperature=0.7,
                do_sample=True,
                pad_token_id=tokenizer2.eos_token_id,
                eos_token_id=tokenizer2.eos_token_id,
                top_p=0.9,
                repetition_penalty=1.1
            )
        generated_ids4 = outputs4[0][inputs4["input_ids"].shape[1]:]
        response4 = tokenizer2.decode(generated_ids4, skip_special_tokens=True)
        print(f"✅ Response: {response4}")
        
    except Exception as e:
        print(f"❌ Could not load alternative model: {e}")

if __name__ == "__main__":
    test_tinyllama_reset() 
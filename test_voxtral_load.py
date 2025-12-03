#!/usr/bin/env python3
"""
Test script to load Voxtral model from local files
"""

import os
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def test_voxtral_load():
    """Test loading Voxtral model from local files"""
    
    try:
        local_model_path = "/Users/starkers/voxtral_local"
        
        logger.info("🚀 Testing Voxtral-Mini-3B load from local files...")
        
        # Check if local files exist
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
            return False
        
        logger.info("✅ All required files found")
        
        # Load tokenizer
        logger.info("📝 Loading tokenizer...")
        tokenizer = AutoTokenizer.from_pretrained(local_model_path)
        logger.info("✅ Tokenizer loaded successfully")
        
        # Load model
        logger.info("🤖 Loading Voxtral-Mini-3B model...")
        model = AutoModelForCausalLM.from_pretrained(
            local_model_path,
            torch_dtype=torch.float16,
            device_map="auto",
            trust_remote_code=True,
            low_cpu_mem_usage=True,
            max_memory={0: "4GB", "cpu": "8GB"}
        )
        logger.info("✅ Model loaded successfully")
        
        # Test generation
        logger.info("🧪 Testing generation...")
        test_input = "Hello, how are you today?"
        inputs = tokenizer(test_input, return_tensors="pt", max_length=512, truncation=True)
        
        # Get device
        device = next(model.parameters()).device
        logger.info(f"🔧 Using device: {device}")
        
        inputs = {k: v.to(device) for k, v in inputs.items()}
        
        with torch.no_grad():
            outputs = model.generate(
                **inputs,
                max_new_tokens=50,
                temperature=0.7,
                do_sample=True,
                top_p=0.9,
                top_k=50,
                pad_token_id=tokenizer.eos_token_id,
                eos_token_id=tokenizer.eos_token_id,
                repetition_penalty=1.1
            )
        
        generated_text = tokenizer.decode(outputs[0], skip_special_tokens=True)
        logger.info(f"✅ Generated text: {generated_text}")
        
        return True
        
    except Exception as e:
        logger.error(f"❌ Error testing model: {e}")
        return False

if __name__ == '__main__':
    success = test_voxtral_load()
    if success:
        logger.info("🎉 Voxtral model test successful!")
    else:
        logger.error("❌ Voxtral model test failed!") 
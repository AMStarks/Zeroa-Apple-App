#!/usr/bin/env python3
"""
Convert TinyLlama PyTorch model to CoreML format
"""

import torch
import coremltools as ct
import json
import os
import numpy as np
from transformers import AutoTokenizer, AutoModelForCausalLM

def download_and_load_tinyllama():
    """Download and load TinyLlama model from HuggingFace"""
    print("📦 Downloading TinyLlama model from HuggingFace...")
    
    try:
        # Download the model from HuggingFace
        model_name = "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
        
        print(f"🔄 Downloading {model_name}...")
        
        # Load tokenizer and model
        tokenizer = AutoTokenizer.from_pretrained(model_name)
        model = AutoModelForCausalLM.from_pretrained(
            model_name,
            torch_dtype=torch.float16,
            low_cpu_mem_usage=True
        )
        
        print(f"✅ Model downloaded and loaded successfully")
        print(f"📊 Model parameters: {sum(p.numel() for p in model.parameters()):,}")
        print(f"📊 Vocabulary size: {tokenizer.vocab_size}")
        
        return model, tokenizer
        
    except Exception as e:
        print(f"❌ Failed to download/load model: {e}")
        return None, None

def create_model_wrapper(model):
    """Create a wrapper for the model that's compatible with CoreML"""
    
    class TinyLlamaWrapper(torch.nn.Module):
        def __init__(self, model):
            super().__init__()
            self.model = model
            
        def forward(self, input_ids):
            # Forward pass without attention mask for simplicity
            outputs = self.model(input_ids=input_ids)
            return outputs.logits
    
    return TinyLlamaWrapper(model)

def convert_to_coreml():
    """Convert TinyLlama model to CoreML"""
    print("🚀 Starting TinyLlama to CoreML conversion...")
    
    # Load model and tokenizer
    model, tokenizer = download_and_load_tinyllama()
    if model is None:
        return False
    
    try:
        print("🔄 Creating model wrapper...")
        
        # Create wrapper
        wrapper = create_model_wrapper(model)
        wrapper.eval()
        
        print("🔄 Converting model to TorchScript...")
        
        # Create example input for tracing
        # Use tokenizer to create proper input
        example_text = "Hello, how are you?"
        inputs = tokenizer(example_text, return_tensors="pt", max_length=512, truncation=True)
        example_input = inputs["input_ids"]
        
        print(f"📊 Example input shape: {example_input.shape}")
        
        # Trace the model
        with torch.no_grad():
            traced_model = torch.jit.trace(wrapper, example_input)
        print("✅ Model traced successfully")
        
        print("🔄 Converting to CoreML...")
        
        # Convert to CoreML
        mlmodel = ct.convert(
            traced_model,
            inputs=[ct.TensorType(shape=example_input.shape, dtype=np.int32)],
            minimum_deployment_target=ct.target.iOS15
        )
        
        # Save the CoreML model
        output_path = "Zeroa/Data/TinyLlamaModel.mlmodel"
        mlmodel.save(output_path)
        
        print(f"✅ CoreML model saved to: {output_path}")
        print(f"📊 Model size: {os.path.getsize(output_path) / (1024*1024):.2f} MB")
        
        # Save tokenizer info
        tokenizer_info = {
            "vocab_size": tokenizer.vocab_size,
            "bos_token_id": tokenizer.bos_token_id,
            "eos_token_id": tokenizer.eos_token_id,
            "pad_token_id": tokenizer.pad_token_id,
            "unk_token_id": tokenizer.unk_token_id
        }
        
        with open("Zeroa/Data/tokenizer_info.json", "w") as f:
            json.dump(tokenizer_info, f)
        
        print("✅ Tokenizer info saved!")
        
        return True
        
    except Exception as e:
        print(f"❌ Conversion failed: {e}")
        import traceback
        traceback.print_exc()
        return False

def main():
    """Main conversion function"""
    print("🎯 TinyLlama to CoreML Converter")
    print("=" * 40)
    
    success = convert_to_coreml()
    
    if success:
        print("\n🎉 Conversion completed successfully!")
        print("📱 The CoreML model is ready for iOS integration")
    else:
        print("\n❌ Conversion failed")
        print("🔧 Please check the error messages above")

if __name__ == "__main__":
    main() 
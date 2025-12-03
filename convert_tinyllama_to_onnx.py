#!/usr/bin/env python3
"""
Convert TinyLlama PyTorch model to ONNX format
"""

import torch
import onnx
import onnxruntime as ort
import json
import os
import numpy as np
from transformers import AutoTokenizer, AutoModelForCausalLM

def load_tinyllama_model():
    """Load the TinyLlama model using transformers"""
    print("📦 Loading TinyLlama model using transformers...")
    
    try:
        # Download the model from HuggingFace
        model_name = "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
        
        print(f"🔄 Loading {model_name}...")
        
        # Load tokenizer and model
        tokenizer = AutoTokenizer.from_pretrained(model_name)
        model = AutoModelForCausalLM.from_pretrained(
            model_name,
            torch_dtype=torch.float16,
            low_cpu_mem_usage=True
        )
        
        print(f"✅ Model loaded successfully")
        print(f"📊 Model parameters: {sum(p.numel() for p in model.parameters()):,}")
        print(f"📊 Vocabulary size: {tokenizer.vocab_size}")
        
        return model, tokenizer
        
    except Exception as e:
        print(f"❌ Failed to load model: {e}")
        return None, None

def create_model_wrapper(model):
    """Create a wrapper for the model that's compatible with ONNX"""
    
    class TinyLlamaWrapper(torch.nn.Module):
        def __init__(self, model):
            super().__init__()
            self.model = model
            
        def forward(self, input_ids):
            # Forward pass without attention mask for simplicity
            outputs = self.model(input_ids=input_ids)
            return outputs.logits
    
    return TinyLlamaWrapper(model)

def convert_to_onnx():
    """Convert TinyLlama model to ONNX"""
    print("🚀 Starting TinyLlama to ONNX conversion...")
    
    # Load model and tokenizer
    model, tokenizer = load_tinyllama_model()
    if model is None:
        return False
    
    try:
        print("🔄 Creating model wrapper...")
        
        # Create wrapper
        wrapper = create_model_wrapper(model)
        wrapper.eval()
        
        print("🔄 Converting model to ONNX...")
        
        # Create example input for tracing
        example_text = "Hello, how are you?"
        inputs = tokenizer(example_text, return_tensors="pt", max_length=512, truncation=True)
        example_input = inputs["input_ids"]
        
        print(f"📊 Example input shape: {example_input.shape}")
        
        # Export to ONNX
        onnx_path = "Zeroa/Data/TinyLlamaModel.onnx"
        
        torch.onnx.export(
            wrapper,
            example_input,
            onnx_path,
            export_params=True,
            opset_version=17,
            do_constant_folding=True,
            input_names=['input_ids'],
            output_names=['logits'],
            dynamic_axes={
                'input_ids': {0: 'batch_size', 1: 'sequence_length'},
                'logits': {0: 'batch_size', 1: 'sequence_length'}
            }
        )
        
        print(f"✅ ONNX model saved to: {onnx_path}")
        print(f"📊 Model size: {os.path.getsize(onnx_path) / (1024*1024):.2f} MB")
        
        # Test ONNX model
        print("🔄 Testing ONNX model...")
        
        # Create ONNX Runtime session
        session = ort.InferenceSession(onnx_path)
        
        # Test inference
        input_data = example_input.numpy()
        outputs = session.run(None, {'input_ids': input_data})
        
        print(f"✅ ONNX model test successful!")
        print(f"📊 Output shape: {outputs[0].shape}")
        
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
    print("🎯 TinyLlama to ONNX Converter")
    print("=" * 40)
    
    success = convert_to_onnx()
    
    if success:
        print("\n🎉 Conversion completed successfully!")
        print("📱 The ONNX model is ready for iOS integration")
    else:
        print("\n❌ Conversion failed")
        print("🔧 Please check the error messages above")

if __name__ == "__main__":
    main() 
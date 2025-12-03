#!/usr/bin/env python3
"""
Create a simple Core ML model for iOS integration
This will be a basic text generation model that can work directly in the app
"""

import coremltools as ct
import numpy as np
import torch
import torch.nn as nn
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class SimpleTextGenerator(nn.Module):
    """Simple text generation model for Core ML conversion"""
    
    def __init__(self, vocab_size=50257, hidden_size=768, num_layers=6):
        super().__init__()
        self.vocab_size = vocab_size
        self.hidden_size = hidden_size
        self.num_layers = num_layers
        
        # Simple embedding layer
        self.embedding = nn.Embedding(vocab_size, hidden_size)
        
        # Simple transformer-like layers
        self.layers = nn.ModuleList([
            nn.TransformerEncoderLayer(
                d_model=hidden_size,
                nhead=12,
                dim_feedforward=hidden_size * 4,
                dropout=0.1,
                batch_first=True
            ) for _ in range(num_layers)
        ])
        
        # Output projection
        self.output_projection = nn.Linear(hidden_size, vocab_size)
        
    def forward(self, input_ids):
        # Embed input tokens
        x = self.embedding(input_ids)
        
        # Pass through transformer layers
        for layer in self.layers:
            x = layer(x)
        
        # Project to vocabulary
        logits = self.output_projection(x)
        
        return logits

def create_simple_coreml_model():
    """Create and convert a simple model to Core ML"""
    
    logger.info("🚀 Creating simple Core ML model...")
    
    try:
        # Create model
        model = SimpleTextGenerator()
        model.eval()
        
        # Create example input
        batch_size = 1
        seq_length = 128
        example_input = torch.randint(0, 50257, (batch_size, seq_length), dtype=torch.long)
        
        # Trace the model
        logger.info("🔧 Tracing model...")
        traced_model = torch.jit.trace(model, example_input)
        
        # Convert to Core ML
        logger.info("🔄 Converting to Core ML...")
        coreml_model = ct.convert(
            traced_model,
            inputs=[
                ct.TensorType(
                    name="input_ids",
                    shape=example_input.shape,
                    dtype=np.int32
                )
            ],
            outputs=[
                ct.TensorType(
                    name="logits",
                    dtype=np.float32
                )
            ],
            minimum_deployment_target=ct.target.iOS16
        )
        
        # Save the model
        output_path = "SimpleTextModel.mlpackage"
        logger.info(f"💾 Saving Core ML model to {output_path}...")
        coreml_model.save(output_path)
        
        logger.info("✅ Simple Core ML model created successfully!")
        logger.info(f"📱 Model saved as: {output_path}")
        logger.info(f"📏 Model size: {os.path.getsize(output_path) / (1024*1024):.1f} MB")
        
        return True
        
    except Exception as e:
        logger.error(f"❌ Error creating model: {e}")
        return False

if __name__ == "__main__":
    import os
    success = create_simple_coreml_model()
    if success:
        print("\n🎉 Simple Core ML model created successfully!")
        print("📱 The model can now be integrated directly into the iOS app")
    else:
        print("\n❌ Model creation failed")
        print("Please check the error messages above") 
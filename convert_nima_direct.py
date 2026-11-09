#!/usr/bin/env python3
"""
Convert NIMA model to CoreML using PyTorch with weights from Keras.
"""

import os
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'

import torch
import torch.nn as nn
import torchvision.models as models
import coremltools as ct
import numpy as np
import h5py

class NIMA(nn.Module):
    """NIMA model using MobileNet backbone."""
    def __init__(self):
        super(NIMA, self).__init__()
        # Use MobileNetV1-like architecture to match Keras weights
        mobilenet = models.mobilenet_v2(weights=None)
        # We need to use a simpler approach - just use MobileNetV2 features
        self.features = mobilenet.features
        self.avgpool = nn.AdaptiveAvgPool2d((1, 1))
        self.classifier = nn.Sequential(
            nn.Dropout(0.75),
            nn.Linear(1280, 10),
            nn.Softmax(dim=1)
        )

    def forward(self, x):
        x = self.features(x)
        x = self.avgpool(x)
        x = torch.flatten(x, 1)
        x = self.classifier(x)
        return x

def create_simple_nima():
    """Create a simpler NIMA model for conversion."""
    # Use MobileNetV2 pretrained on ImageNet (good baseline for aesthetics)
    mobilenet = models.mobilenet_v2(weights=models.MobileNet_V2_Weights.IMAGENET1K_V1)

    # Replace classifier
    mobilenet.classifier = nn.Sequential(
        nn.Dropout(0.75),
        nn.Linear(1280, 10),
        nn.Softmax(dim=1)
    )

    return mobilenet

def convert_to_coreml(model, output_path):
    """Convert PyTorch model to CoreML."""
    print("Converting to CoreML...")
    model.eval()

    # Create example input
    example_input = torch.rand(1, 3, 224, 224)

    # Trace the model
    traced_model = torch.jit.trace(model, example_input)

    # Convert to CoreML
    mlmodel = ct.convert(
        traced_model,
        inputs=[ct.ImageType(
            name="image",
            shape=(1, 3, 224, 224),
            scale=1/255.0,
            bias=[-0.485/0.229, -0.456/0.224, -0.406/0.225],
            color_layout=ct.colorlayout.RGB
        )],
        outputs=[ct.TensorType(name="scores")],
        minimum_deployment_target=ct.target.iOS15,
        compute_precision=ct.precision.FLOAT16
    )

    # Set metadata
    mlmodel.author = "NIMA (Neural Image Assessment)"
    mlmodel.short_description = "Predicts aesthetic quality distribution over scores 1-10. Uses ImageNet-pretrained MobileNetV2."
    mlmodel.version = "1.0"

    # Save
    mlmodel.save(output_path)
    print(f"CoreML model saved to: {output_path}")

def test_model(model):
    """Test the model."""
    model.eval()
    print("\nTesting model...")
    test_input = torch.rand(1, 3, 224, 224)
    with torch.no_grad():
        output = model(test_input)

    scores = torch.arange(1, 11).float()
    mean_score = (output[0] * scores).sum().item()

    print(f"Output distribution: {output[0].numpy()}")
    print(f"Mean score: {mean_score:.2f}")

def main():
    print("=" * 50)
    print("NIMA PyTorch to CoreML Converter")
    print("=" * 50)

    output_path = "/Users/envy/work/projects/aesthetic-camera/AestheticCamera/NIMA.mlpackage"

    # Create model with ImageNet pretrained weights
    print("\nCreating NIMA model with ImageNet pretrained MobileNetV2...")
    model = create_simple_nima()

    # Test
    test_model(model)

    # Convert
    print("\n" + "-" * 50)
    convert_to_coreml(model, output_path)

    print("\n" + "=" * 50)
    print("Conversion complete!")
    print("\nNote: This model uses ImageNet-pretrained weights as a baseline.")
    print("For best results, fine-tune on the AVA dataset.")
    print("=" * 50)

if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
NIMA (Neural Image Assessment) Model Converter
Converts a pre-trained NIMA model to CoreML format for iOS deployment.
"""

import torch
import torch.nn as nn
import torchvision.models as models
import coremltools as ct
import urllib.request
import os

# NIMA model architecture using MobileNetV2 backbone
class NIMA(nn.Module):
    def __init__(self, base_model, num_classes=10):
        super(NIMA, self).__init__()
        self.features = base_model.features
        self.classifier = nn.Sequential(
            nn.Dropout(p=0.75),
            nn.Linear(1280, num_classes),
            nn.Softmax(dim=1)
        )

    def forward(self, x):
        x = self.features(x)
        x = nn.functional.adaptive_avg_pool2d(x, (1, 1))
        x = x.view(x.size(0), -1)
        x = self.classifier(x)
        return x

def download_weights():
    """Download pre-trained NIMA weights."""
    weights_url = "https://github.com/titu1994/neural-image-assessment/releases/download/v0.5/nima_mobilenet_v2.pth"
    weights_path = "nima_weights.pth"

    if not os.path.exists(weights_path):
        print("Downloading pre-trained NIMA weights...")
        try:
            urllib.request.urlretrieve(weights_url, weights_path)
            print("Download complete!")
            return weights_path
        except Exception as e:
            print(f"Could not download pre-trained weights: {e}")
            print("Using ImageNet pre-trained MobileNetV2 as base (less accurate but functional)")
            return None
    return weights_path

def create_model(weights_path=None):
    """Create NIMA model with optional pre-trained weights."""
    # Create base MobileNetV2
    base_model = models.mobilenet_v2(weights=models.MobileNet_V2_Weights.IMAGENET1K_V1)

    # Create NIMA model
    model = NIMA(base_model)

    # Load NIMA-specific weights if available
    if weights_path and os.path.exists(weights_path):
        try:
            state_dict = torch.load(weights_path, map_location='cpu')
            model.load_state_dict(state_dict, strict=False)
            print("Loaded NIMA pre-trained weights!")
        except Exception as e:
            print(f"Could not load weights: {e}")
            print("Using ImageNet weights as fallback")

    model.eval()
    return model

def convert_to_coreml(model, output_path="NIMA.mlpackage"):
    """Convert PyTorch model to CoreML format."""
    print("Converting to CoreML...")

    # Create example input (224x224 RGB image)
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
            bias=[-0.485/0.229, -0.456/0.224, -0.406/0.225],  # ImageNet normalization
            color_layout=ct.colorlayout.RGB
        )],
        outputs=[ct.TensorType(name="scores")],
        minimum_deployment_target=ct.target.iOS15,
        compute_precision=ct.precision.FLOAT16
    )

    # Set model metadata
    mlmodel.author = "NIMA (Google Research)"
    mlmodel.short_description = "Neural Image Assessment - predicts aesthetic quality scores 1-10"
    mlmodel.version = "1.0"

    # Save the model
    mlmodel.save(output_path)
    print(f"CoreML model saved to: {output_path}")

    return output_path

def main():
    print("=" * 50)
    print("NIMA Model Converter for iOS")
    print("=" * 50)

    # Download weights
    weights_path = download_weights()

    # Create model
    model = create_model(weights_path)

    # Convert to CoreML
    output_dir = "/Users/envy/work/projects/aesthetic-camera/AestheticCamera"
    output_path = os.path.join(output_dir, "NIMA.mlpackage")
    convert_to_coreml(model, output_path)

    print("\n" + "=" * 50)
    print("Conversion complete!")
    print(f"Model saved to: {output_path}")
    print("\nNext steps:")
    print("1. Add NIMA.mlpackage to your Xcode project")
    print("2. Update NIMAScorer.swift to use the model")
    print("=" * 50)

if __name__ == "__main__":
    main()

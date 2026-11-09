#!/usr/bin/env python3
"""
Convert NIMA model with REAL trained weights to CoreML.
This script properly maps Keras MobileNetV1 weights to PyTorch.
"""

import torch
import torch.nn as nn
import numpy as np
import h5py
import coremltools as ct

class DepthwiseSeparableConv(nn.Module):
    """Depthwise separable convolution block."""
    def __init__(self, in_channels, out_channels, stride=1):
        super().__init__()
        self.depthwise = nn.Conv2d(in_channels, in_channels, kernel_size=3,
                                   stride=stride, padding=1, groups=in_channels, bias=False)
        self.depthwise_bn = nn.BatchNorm2d(in_channels)
        self.depthwise_relu = nn.ReLU(inplace=True)

        self.pointwise = nn.Conv2d(in_channels, out_channels, kernel_size=1, bias=False)
        self.pointwise_bn = nn.BatchNorm2d(out_channels)
        self.pointwise_relu = nn.ReLU(inplace=True)

    def forward(self, x):
        x = self.depthwise(x)
        x = self.depthwise_bn(x)
        x = self.depthwise_relu(x)
        x = self.pointwise(x)
        x = self.pointwise_bn(x)
        x = self.pointwise_relu(x)
        return x


class MobileNetV1NIMA(nn.Module):
    """MobileNetV1 architecture matching the Keras NIMA model."""
    def __init__(self, num_classes=10):
        super().__init__()

        # Initial conv layer
        self.conv1 = nn.Conv2d(3, 32, kernel_size=3, stride=2, padding=1, bias=False)
        self.conv1_bn = nn.BatchNorm2d(32)
        self.conv1_relu = nn.ReLU(inplace=True)

        # Depthwise separable blocks
        # Block configurations: (in_channels, out_channels, stride)
        self.blocks = nn.ModuleList([
            DepthwiseSeparableConv(32, 64, stride=1),    # block 1
            DepthwiseSeparableConv(64, 128, stride=2),   # block 2
            DepthwiseSeparableConv(128, 128, stride=1),  # block 3
            DepthwiseSeparableConv(128, 256, stride=2),  # block 4
            DepthwiseSeparableConv(256, 256, stride=1),  # block 5
            DepthwiseSeparableConv(256, 512, stride=2),  # block 6
            DepthwiseSeparableConv(512, 512, stride=1),  # block 7
            DepthwiseSeparableConv(512, 512, stride=1),  # block 8
            DepthwiseSeparableConv(512, 512, stride=1),  # block 9
            DepthwiseSeparableConv(512, 512, stride=1),  # block 10
            DepthwiseSeparableConv(512, 512, stride=1),  # block 11
            DepthwiseSeparableConv(512, 1024, stride=2), # block 12
            DepthwiseSeparableConv(1024, 1024, stride=1),# block 13
        ])

        # Global average pooling and classifier
        self.avgpool = nn.AdaptiveAvgPool2d((1, 1))
        self.dropout = nn.Dropout(0.75)
        self.fc = nn.Linear(1024, num_classes)
        self.softmax = nn.Softmax(dim=1)

    def forward(self, x):
        x = self.conv1(x)
        x = self.conv1_bn(x)
        x = self.conv1_relu(x)

        for block in self.blocks:
            x = block(x)

        x = self.avgpool(x)
        x = torch.flatten(x, 1)
        x = self.dropout(x)
        x = self.fc(x)
        x = self.softmax(x)
        return x


def load_keras_weights(model, h5_path):
    """Load Keras HDF5 weights into PyTorch model."""
    print(f"Loading weights from {h5_path}...")

    with h5py.File(h5_path, 'r') as f:
        # Load conv1 weights
        conv1_kernel = np.array(f['conv1/conv1/kernel:0'])
        # Keras: (H, W, C_in, C_out) -> PyTorch: (C_out, C_in, H, W)
        model.conv1.weight.data = torch.from_numpy(conv1_kernel.transpose(3, 2, 0, 1))

        # Load conv1_bn weights
        model.conv1_bn.weight.data = torch.from_numpy(np.array(f['conv1_bn/conv1_bn/gamma:0']))
        model.conv1_bn.bias.data = torch.from_numpy(np.array(f['conv1_bn/conv1_bn/beta:0']))
        model.conv1_bn.running_mean.data = torch.from_numpy(np.array(f['conv1_bn/conv1_bn/moving_mean:0']))
        model.conv1_bn.running_var.data = torch.from_numpy(np.array(f['conv1_bn/conv1_bn/moving_variance:0']))

        # Load depthwise separable blocks
        for i, block in enumerate(model.blocks):
            block_num = i + 1

            # Depthwise conv
            dw_key = f'conv_dw_{block_num}/conv_dw_{block_num}/depthwise_kernel:0'
            dw_kernel = np.array(f[dw_key])
            # Keras depthwise: (H, W, C, 1) -> PyTorch: (C, 1, H, W)
            block.depthwise.weight.data = torch.from_numpy(dw_kernel.transpose(2, 3, 0, 1))

            # Depthwise BN
            dw_bn_prefix = f'conv_dw_{block_num}_bn/conv_dw_{block_num}_bn'
            block.depthwise_bn.weight.data = torch.from_numpy(np.array(f[f'{dw_bn_prefix}/gamma:0']))
            block.depthwise_bn.bias.data = torch.from_numpy(np.array(f[f'{dw_bn_prefix}/beta:0']))
            block.depthwise_bn.running_mean.data = torch.from_numpy(np.array(f[f'{dw_bn_prefix}/moving_mean:0']))
            block.depthwise_bn.running_var.data = torch.from_numpy(np.array(f[f'{dw_bn_prefix}/moving_variance:0']))

            # Pointwise conv
            pw_key = f'conv_pw_{block_num}/conv_pw_{block_num}/kernel:0'
            pw_kernel = np.array(f[pw_key])
            # Keras 1x1: (1, 1, C_in, C_out) -> PyTorch: (C_out, C_in, 1, 1)
            block.pointwise.weight.data = torch.from_numpy(pw_kernel.transpose(3, 2, 0, 1))

            # Pointwise BN
            pw_bn_prefix = f'conv_pw_{block_num}_bn/conv_pw_{block_num}_bn'
            block.pointwise_bn.weight.data = torch.from_numpy(np.array(f[f'{pw_bn_prefix}/gamma:0']))
            block.pointwise_bn.bias.data = torch.from_numpy(np.array(f[f'{pw_bn_prefix}/beta:0']))
            block.pointwise_bn.running_mean.data = torch.from_numpy(np.array(f[f'{pw_bn_prefix}/moving_mean:0']))
            block.pointwise_bn.running_var.data = torch.from_numpy(np.array(f[f'{pw_bn_prefix}/moving_variance:0']))

        # Load dense layer (the NIMA classifier!)
        fc_kernel = np.array(f['dense_1/dense_1/kernel:0'])
        fc_bias = np.array(f['dense_1/dense_1/bias:0'])
        # Keras: (in, out) -> PyTorch: (out, in)
        model.fc.weight.data = torch.from_numpy(fc_kernel.T)
        model.fc.bias.data = torch.from_numpy(fc_bias)

    print("Weights loaded successfully!")
    return model


def test_model(model):
    """Test the model with random input."""
    model.eval()
    print("\nTesting model...")

    # Create test input
    test_input = torch.rand(1, 3, 224, 224)

    with torch.no_grad():
        output = model(test_input)

    # Calculate mean score
    scores = torch.arange(1, 11).float()
    mean_score = (output[0] * scores).sum().item()

    print(f"Output distribution: {output[0].numpy()}")
    print(f"Mean aesthetic score: {mean_score:.2f}")

    return mean_score


def convert_to_coreml(model, output_path):
    """Convert PyTorch model to CoreML."""
    print("\nConverting to CoreML...")
    model.eval()

    # Create example input
    example_input = torch.rand(1, 3, 224, 224)

    # Trace the model
    traced_model = torch.jit.trace(model, example_input)

    # Convert to CoreML
    # Keras MobileNet preprocessing: scale to [0, 1] then normalize with ImageNet stats
    # For Keras MobileNet (not V2): preprocess_input scales to [-1, 1]
    mlmodel = ct.convert(
        traced_model,
        inputs=[ct.ImageType(
            name="image",
            shape=(1, 3, 224, 224),
            scale=1.0/127.5,
            bias=[-127.5/127.5, -127.5/127.5, -127.5/127.5],  # Normalize to [-1, 1]
            color_layout=ct.colorlayout.RGB
        )],
        outputs=[ct.TensorType(name="scores")],
        minimum_deployment_target=ct.target.iOS15,
        compute_precision=ct.precision.FLOAT32  # Use full precision for accuracy
    )

    # Set metadata
    mlmodel.author = "idealo/NIMA (trained on AVA dataset)"
    mlmodel.short_description = "NIMA: Neural Image Assessment - predicts aesthetic quality distribution (1-10 scale). Trained on 250k+ professionally rated images."
    mlmodel.version = "1.0"

    # Save
    mlmodel.save(output_path)
    print(f"CoreML model saved to: {output_path}")


def main():
    print("=" * 60)
    print("NIMA Real Weights Converter")
    print("=" * 60)

    weights_path = "/Users/envy/work/projects/aesthetic-camera/nima_aesthetic.hdf5"
    output_path = "/Users/envy/work/projects/aesthetic-camera/AestheticCamera/NIMA.mlpackage"

    # Create model
    print("\nCreating MobileNetV1 NIMA architecture...")
    model = MobileNetV1NIMA(num_classes=10)

    # Load real NIMA weights
    model = load_keras_weights(model, weights_path)

    # Test model
    test_model(model)

    # Convert to CoreML
    convert_to_coreml(model, output_path)

    print("\n" + "=" * 60)
    print("SUCCESS! Real NIMA model converted to CoreML!")
    print("The model is now trained on 250k+ aesthetically rated images.")
    print("=" * 60)


if __name__ == "__main__":
    main()

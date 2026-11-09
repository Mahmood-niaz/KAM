#!/usr/bin/env python3
"""
Convert idealo NIMA Keras model to CoreML format.
"""

import os
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'  # Suppress TF warnings

import tensorflow as tf
from tensorflow import keras
import coremltools as ct
import numpy as np

def create_nima_model():
    """Recreate the NIMA model architecture used by idealo."""
    # Create MobileNet base
    base_model = keras.applications.MobileNet(
        input_shape=(224, 224, 3),
        include_top=False,
        pooling='avg',
        weights=None  # We'll load weights separately
    )

    # Add NIMA classification head
    x = keras.layers.Dropout(0.75)(base_model.output)
    x = keras.layers.Dense(10, activation='softmax')(x)

    model = keras.Model(inputs=base_model.input, outputs=x)
    return model

def load_weights_from_hdf5(model, weights_path):
    """Load weights from HDF5 file."""
    print(f"Loading weights from: {weights_path}")
    try:
        model.load_weights(weights_path)
        print("Weights loaded successfully!")
        return True
    except Exception as e:
        print(f"Error loading weights: {e}")
        # Try loading with by_name
        try:
            model.load_weights(weights_path, by_name=True, skip_mismatch=True)
            print("Weights loaded with by_name=True")
            return True
        except Exception as e2:
            print(f"Failed to load weights: {e2}")
            return False

def convert_to_coreml(model, output_path):
    """Convert Keras model to CoreML."""
    print("Converting to CoreML...")

    # First save as SavedModel format for better compatibility
    saved_model_path = "/tmp/nima_saved_model"
    model.export(saved_model_path)
    print(f"Exported to SavedModel: {saved_model_path}")

    # Convert using coremltools from SavedModel
    mlmodel = ct.convert(
        saved_model_path,
        source="tensorflow",
        inputs=[ct.ImageType(
            name="image",
            shape=(1, 224, 224, 3),
            scale=1/127.5,
            bias=[-1, -1, -1],  # MobileNet preprocessing: (x/127.5) - 1
            color_layout=ct.colorlayout.RGB
        )],
        outputs=[ct.TensorType(name="scores")],
        minimum_deployment_target=ct.target.iOS15,
        compute_precision=ct.precision.FLOAT16
    )

    # Set metadata
    mlmodel.author = "idealo (NIMA implementation)"
    mlmodel.short_description = "Neural Image Assessment - predicts aesthetic quality distribution over scores 1-10"
    mlmodel.version = "1.0"

    # Save
    mlmodel.save(output_path)
    print(f"CoreML model saved to: {output_path}")

def test_model(model):
    """Test the model with a random image."""
    print("\nTesting model with random input...")
    test_input = np.random.rand(1, 224, 224, 3).astype(np.float32)
    output = model.predict(test_input, verbose=0)

    # Calculate mean score (weighted average of 1-10)
    scores = np.arange(1, 11)
    mean_score = np.sum(output[0] * scores)

    print(f"Output distribution: {output[0]}")
    print(f"Mean aesthetic score: {mean_score:.2f}")

def main():
    print("=" * 50)
    print("NIMA Keras to CoreML Converter")
    print("=" * 50)

    weights_path = "/Users/envy/work/projects/aesthetic-camera/nima_aesthetic.hdf5"
    output_path = "/Users/envy/work/projects/aesthetic-camera/AestheticCamera/NIMA.mlpackage"

    # Create model
    print("\nCreating NIMA model architecture...")
    model = create_nima_model()
    model.summary()

    # Load weights
    print("\n" + "-" * 50)
    if not load_weights_from_hdf5(model, weights_path):
        print("WARNING: Could not load pre-trained weights. Model will use random weights.")

    # Test model
    test_model(model)

    # Convert to CoreML
    print("\n" + "-" * 50)
    convert_to_coreml(model, output_path)

    print("\n" + "=" * 50)
    print("Conversion complete!")
    print("=" * 50)

if __name__ == "__main__":
    main()

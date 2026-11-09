#!/usr/bin/env python3
"""Inspect the structure of the NIMA Keras weights file."""

import h5py
import numpy as np

def print_h5_structure(name, obj):
    """Print structure of HDF5 file."""
    if isinstance(obj, h5py.Dataset):
        print(f"  Dataset: {name} - shape: {obj.shape}, dtype: {obj.dtype}")
    else:
        print(f"Group: {name}")

def main():
    weights_path = "/Users/envy/work/projects/aesthetic-camera/nima_aesthetic.hdf5"

    print("=" * 60)
    print("NIMA Weights File Structure")
    print("=" * 60)

    with h5py.File(weights_path, 'r') as f:
        print("\nTop-level keys:", list(f.keys()))

        # Recursively print structure
        print("\nFull structure:")
        f.visititems(print_h5_structure)

        # Count total parameters
        total_params = 0
        def count_params(name, obj):
            nonlocal total_params
            if isinstance(obj, h5py.Dataset):
                total_params += np.prod(obj.shape)

        f.visititems(count_params)
        print(f"\nTotal parameters: {total_params:,}")

        # Check for model config
        if 'model_config' in f.attrs:
            print("\nModel config found!")

        # Look at first few layer weights
        print("\n" + "=" * 60)
        print("Sample layer shapes:")
        print("=" * 60)

        layer_count = 0
        for key in f.keys():
            if layer_count > 10:
                print("...")
                break
            if isinstance(f[key], h5py.Group):
                for subkey in f[key].keys():
                    if isinstance(f[key][subkey], h5py.Group):
                        for name in f[key][subkey].keys():
                            dataset = f[key][subkey][name]
                            if isinstance(dataset, h5py.Dataset):
                                print(f"{key}/{subkey}/{name}: {dataset.shape}")
                                layer_count += 1

if __name__ == "__main__":
    main()

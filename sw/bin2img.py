"""
python bin2img.py <input_bin> <output_image> [--mode rgb|gray] [--width W] [--height H]

"""
import sys
import argparse
import numpy as np
from PIL import Image


def bin2img(input_path, output_path, mode='rgb', width=512, height=512):
    with open(input_path, 'rb') as f:
        raw = f.read()

    if mode == 'rgb':
        expected = width * height * 3
        if len(raw) != expected:
            print(f"Warning: expected {expected} bytes, got {len(raw)} bytes.")
        arr = np.frombuffer(raw, dtype=np.uint8).reshape(height, width, 3)
        img = Image.fromarray(arr, 'RGB')

    elif mode == 'gray':
        expected = width * height
        if len(raw) != expected:
            print(f"Warning: expected {expected} bytes, got {len(raw)} bytes.")
        arr = np.frombuffer(raw, dtype=np.uint8).reshape(height, width)
        img = Image.fromarray(arr, 'L')

    else:
        print(f"Unknown mode '{mode}'. Use 'rgb' or 'gray'.")
        sys.exit(1)

    img.save(output_path)
    print(f"Saved {output_path} ({width}x{height}, mode={mode}).")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert flat raw binary (FPGA DDR export) to image.")
    parser.add_argument("input",  help="Input binary file path")
    parser.add_argument("output", help="Output image path")
    parser.add_argument("--mode",   choices=['rgb', 'gray'], default='rgb')
    parser.add_argument("--width",  type=int, default=512)
    parser.add_argument("--height", type=int, default=512)
    args = parser.parse_args()
    bin2img(args.input, args.output, args.mode, args.width, args.height)
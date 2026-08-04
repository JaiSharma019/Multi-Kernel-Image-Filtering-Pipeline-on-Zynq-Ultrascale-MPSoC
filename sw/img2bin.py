"""
python img2bin.py <input_image> <output_bin> [--mode rgb|gray]

"""
import sys
import argparse
import numpy as np
from PIL import Image


def img2bin(input_path, output_path, mode='rgb'):
    if mode == 'rgb':
        img = Image.open(input_path).convert('RGB')
        arr = np.array(img, dtype=np.uint8)   # shape (H, W, 3)
        expected = arr.shape[0] * arr.shape[1] * 3
    elif mode == 'gray':
        img = Image.open(input_path).convert('L')
        arr = np.array(img, dtype=np.uint8)   # shape (H, W)
        expected = arr.shape[0] * arr.shape[1]
    else:
        print(f"Unknown mode '{mode}'. Use 'rgb' or 'gray'.")
        sys.exit(1)

    raw = arr.tobytes()
    assert len(raw) == expected, f"Byte count mismatch: got {len(raw)}, expected {expected}"

    with open(output_path, 'wb') as f:
        f.write(raw)
    print(f"Written {len(raw)} bytes to {output_path} (mode={mode}).")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert image to flat raw binary for FPGA DDR loading.")
    parser.add_argument("input",  help="Input image path")
    parser.add_argument("output", help="Output binary file path")
    parser.add_argument("--mode", choices=['rgb', 'gray'], default='rgb')
    args = parser.parse_args()
    img2bin(args.input, args.output, args.mode)
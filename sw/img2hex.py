"""
Convert an image to a hex file for Verilog simulation.

Usage:
    python img2hex.py <input_image> <output_hex> [--mode rgb|gray]

Examples:
    python img2hex.py lena_rgb.png input_image_rgb.hex --mode rgb
    python img2hex.py lena_gray.png input_image.hex --mode gray

Default mode is rgb if --mode is not specified.
"""
import sys
import argparse
from PIL import Image


def img2hex(input_path, output_path, mode='rgb'):
    if mode == 'rgb':
        import numpy as np
        arr = np.array(Image.open(input_path).convert('RGB'), dtype=np.uint8)
        h, w, _ = arr.shape
        with open(output_path, 'w') as f:
            for row in arr:
                for r, g, b in row:
                    f.write(f"{r:02x}{g:02x}{b:02x}\n")
        print(f"Generated {output_path} with {h*w} 24-bit RGB pixels.")

    elif mode == 'gray':
        import numpy as np
        arr = np.array(Image.open(input_path).convert('L'), dtype=np.uint8)
        h, w = arr.shape
        with open(output_path, 'w') as f:
            for row in arr:
                for p in row:
                    f.write(f"{p:02x}\n")
        print(f"Generated {output_path} with {h*w} 8-bit grayscale pixels.")

    else:
        print(f"Unknown mode '{mode}'. Use 'rgb' or 'gray'.")
        sys.exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert image to hex file for Verilog simulation.")
    parser.add_argument("input",  help="Input image path (e.g. lena_rgb.png)")
    parser.add_argument("output", help="Output hex file path (e.g. input_image_rgb.hex)")
    parser.add_argument("--mode", choices=['rgb', 'gray'], default='rgb',
                        help="Color mode: 'rgb' (default) or 'gray'")
    args = parser.parse_args()
    img2hex(args.input, args.output, args.mode)
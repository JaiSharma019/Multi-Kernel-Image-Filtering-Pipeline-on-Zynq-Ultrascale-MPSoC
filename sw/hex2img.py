"""
Convert a Verilog simulation hex output file back to an image.

Usage:
    python hex2img.py <input_hex> <output_image> [--mode rgb|gray] [--width W] [--height H]

Examples:
    python hex2img.py output_image_rgb.hex lena_rgb_gauss_sim.png --mode rgb
    python hex2img.py output_image.hex lena_gray_sobel_sim.png --mode gray

Default mode is rgb, default size is 512x512.
The 'x' (uninitialized) state from Verilog simulation is treated as 0 (black).
"""
import sys
import argparse
from PIL import Image


def hex2img(input_path, output_path, mode='rgb', width=512, height=512):
    with open(input_path, 'r') as f:
        hex_data = f.read().splitlines()

    if mode == 'rgb':
        pixel_data = []
        for hex_str in hex_data:
            hex_str = hex_str.strip()
            # Verilog 'x' (uninitialized) state -> black pixel
            if 'x' in hex_str.lower():
                hex_str = '000000'
            r = int(hex_str[0:2], 16)
            g = int(hex_str[2:4], 16)
            b = int(hex_str[4:6], 16)
            pixel_data.append((r, g, b))
        img_out = Image.new('RGB', (width, height))
        img_out.putdata(pixel_data)

    elif mode == 'gray':
        pixel_data = []
        for hex_str in hex_data:
            hex_str = hex_str.strip()
            if 'x' in hex_str.lower():
                hex_str = '00'
            pixel_data.append(int(hex_str, 16))
        img_out = Image.new('L', (width, height))
        img_out.putdata(pixel_data)

    else:
        print(f"Unknown mode '{mode}'. Use 'rgb' or 'gray'.")
        sys.exit(1)

    img_out.save(output_path)
    print(f"Saved {output_path} ({width}x{height}, mode={mode}).")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert Verilog simulation hex output to image.")
    parser.add_argument("input",  help="Input hex file (e.g. output_image_rgb.hex)")
    parser.add_argument("output", help="Output image path (e.g. result.png)")
    parser.add_argument("--mode",   choices=['rgb', 'gray'], default='rgb')
    parser.add_argument("--width",  type=int, default=512)
    parser.add_argument("--height", type=int, default=512)
    args = parser.parse_args()
    hex2img(args.input, args.output, args.mode, args.width, args.height)
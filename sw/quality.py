"""
python quality.py <original_image> <hardware_image> --filter <filter> [--mode rgb|gray]

Supported filters: blur, sobel_x, sobel_xy, sharpen, scharr
"""
import sys
import argparse
import numpy as np
from PIL import Image
from skimage.metrics import structural_similarity as ssim
from skimage.metrics import peak_signal_noise_ratio as psnr



def convolve3x3(channel, kernel_int):
    h, w = channel.shape
    padded = np.pad(channel, 1, mode='edge').astype(np.int64)
    out = np.zeros((h, w), dtype=np.int64)
    for dy in range(3):
        for dx in range(3):
            out += kernel_int[dy, dx] * padded[dy:dy + h, dx:dx + w]
    return out


# Golden reference generator
KERNELS = {
    'blur': np.array([[1, 2, 1], [2, 4, 2], [1, 2, 1]], dtype=np.int64),
    'sobel_x': np.array([[1, 0, -1], [2, 0, -2], [1, 0, -1]], dtype=np.int64),
    'sobel_y': np.array([[1, 2, 1], [0, 0, 0], [-1, -2, -1]], dtype=np.int64),
    'sharpen': np.array([[0, -1, 0], [-1, 5, -1], [0, -1, 0]], dtype=np.int64),
    'scharr_x': np.array([[-3, 0, 3], [-10, 0, 10], [-3, 0, 3]], dtype=np.int64),
    'scharr_y': np.array([[-3, -10, -3], [0, 0, 0], [3, 10, 3]], dtype=np.int64),
}


def generate_golden(channel, filter_name):
    
    if filter_name == 'blur':
        # Sum of coefficients = 16, so divide by 16 (truncating right-shift by 4)
        result = convolve3x3(channel, KERNELS['blur']) >> 4

    elif filter_name == 'sobel_x':
        result = np.abs(convolve3x3(channel, KERNELS['sobel_x']))

    elif filter_name == 'sobel_xy':
        gx = np.abs(convolve3x3(channel, KERNELS['sobel_x']))
        gy = np.abs(convolve3x3(channel, KERNELS['sobel_y']))
        result = gx + gy

    elif filter_name == 'sharpen':
        # Coefficient sum = 1, no normalization shift needed
        result = convolve3x3(channel, KERNELS['sharpen'])

    elif filter_name == 'scharr':
        gx = np.abs(convolve3x3(channel, KERNELS['scharr_x']))
        gy = np.abs(convolve3x3(channel, KERNELS['scharr_y']))
        result = (gx + gy) >> 2   # matches RTL's sobel_sum >>> 2 for KERNEL=5

    else:
        raise ValueError(f"Unknown filter '{filter_name}'. "
                         f"Supported: blur, sobel_x, sobel_xy, sharpen, scharr")

    return np.clip(result, 0, 255).astype(np.uint8)


# main verification
def run_verification(original_path, hardware_path, filter_name, mode):
    pil_mode = 'RGB' if mode == 'rgb' else 'L'

    original = np.array(Image.open(original_path).convert(pil_mode), dtype=np.uint8)
    hardware = np.array(Image.open(hardware_path).convert(pil_mode), dtype=np.uint8)

    if original.shape != hardware.shape:
        print(f"ERROR: Shape mismatch — original {original.shape} vs hardware {hardware.shape}")
        sys.exit(1)

    # Build golden reference channel by channel
    if mode == 'rgb':
        golden = np.zeros_like(original)
        for c in range(3):
            golden[:, :, c] = generate_golden(original[:, :, c], filter_name)
        channel_axis = 2
    else:
        golden = generate_golden(original, filter_name)
        channel_axis = None

    # Metrics
    mse_val = np.mean((golden.astype(np.float64) - hardware.astype(np.float64)) ** 2)
    psnr_val = psnr(golden, hardware, data_range=255)
    ssim_val = ssim(golden, hardware, data_range=255,
                    channel_axis=channel_axis if mode == 'rgb' else None)

    # pixel exact analysis
    diff = np.abs(golden.astype(np.int64) - hardware.astype(np.int64))
    if mode == 'rgb':
        differing = np.argwhere(diff.sum(axis=2) > 0)
    else:
        differing = np.argwhere(diff > 0)

    print(f"\n--- Verification: {filter_name.upper()} | mode={mode} ---")
    print(f"  Original : {original_path}")
    print(f"  Hardware : {hardware_path}")
    print(f"  MSE      : {mse_val:.4f}  (lower is better, 0 = perfect)")
    print(f"  PSNR     : {psnr_val:.2f} dB  (higher is better, >40 dB = excellent)")
    print(f"  SSIM     : {ssim_val:.5f}  (higher is better, 1.0 = perfect)")
    print(f"  Differing pixels: {len(differing)} / {original.shape[0] * original.shape[1]}")
    if 0 < len(differing) <= 10:
        print(f"  Locations: {differing.tolist()}")
    print()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Verify FPGA/simulation output against an independent golden reference."
    )
    parser.add_argument("original", help="Original input image (e.g. lena_rgb.png)")
    parser.add_argument("hardware", help="FPGA or simulation output image to verify")
    parser.add_argument("--filter", required=True,
                        choices=['blur', 'sobel_x', 'sobel_xy', 'sharpen', 'scharr'],
                        help="Filter type applied by the hardware")
    parser.add_argument("--mode", choices=['rgb', 'gray'], default='rgb',
                        help="Image mode: 'rgb' (default) or 'gray'")
    args = parser.parse_args()
    run_verification(args.original, args.hardware, args.filter, args.mode)
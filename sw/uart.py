import serial
import numpy as np
from PIL import Image

PORT = 'COM6'
BAUD = 115200
SIZE = 512*512*3

ser = serial.Serial(PORT, BAUD, timeout=180)

img = Image.open("lena_rgb.png").convert("RGB")
arr = np.array(img)
print("Sending input image...")
ser.write(arr.tobytes())

print("Waiting for filtered output...")
raw = ser.read(SIZE)
out = np.frombuffer(raw, dtype=np.uint8).reshape(512, 512, 3)
Image.fromarray(out, "RGB").save("lena_rgb_fpga_scharr_uart.png")
print("Done.")
ser.close()
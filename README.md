# Multi-Kernel Image Filtering Pipeline on Zynq UltraScale+ MPSoC

A hardware image filtering accelerator, implemented from RTL, integrated into a full Zynq SoC, and verified on FPGA (ZCU104 board). It takes raw RGB/grayscale image as input, applies a 2D convolution-based filter, and outputs the filtered image and performs the math on hardware, and AXI4 Stream compliant.

## Data Flow

The PS core recieves the raw image over UART1, writing it into DDR, then starting the AXI VDMA streaming the pixels through filter IP and writing the result back to separate DDR region, then the PS polls the VDMA's frame counter interrupt to detect the completion and then sends the filtered image back over UART1, which is then converted from raw bin file to image.

![Figure 1](<images/block_design.png>)

## IP Architecture

The image filter IP is made of three modules, `convolution.v`, `window.v` and `lineBuffer.v`, wrapped under a top module (`image_filter_top.v`). Their working is explained below: 

### Line Buffer Module

* It delays an incoming pixel stream by exactly one complete row which is required to have three simulataneous rows available for the 3x3 convolution window. Each line buffer infers to a BRAM in hardware.

* For handshaking, to know if it is ready to accept new input, we check either the downstream stage is ready to accept its output or the buffer hasn't produced a valid output yet, thus preventing backpressure data loss.

* To mark the end of line pulse (TLAST) DATA_WIDTH+1 is passed to LB1, so the TLAST arrives at window generation module delayed by exxactly one row correctly aligned with the pixel data.

### Window Generation Module

* This builds the 3x3 pixel neighbourhood around each center pixel, with edge replication at the borders, and outputting 72 bit wider bus one every valid clock.

* The bottom row would be the live incoming stream, that is, the current row. The LB1 is the middle row which was the current row one row back, and LB2 is the top row, which is the output of LB1 row one row back.

* Valid flag signals is aligned with the center pixel and including two rows of pipeline fill time. Enable signal is activated only when either downstream stage is ready to accept or there's no pending valid output, thus preventing from any backpressure losses.

* Edge replication is implemented in two stages, horizontal and vertical, when the center pixel is column 0 it is filled with center pixels on the left side similarly for the right border we do horizontal replication, when the center pixel is at the top/bottom row the center pixels are replicated on the corresponding missing side where this is already horizontally replicated thus filling the corners too. 

* The TLAST packed with LB1 when outputs from it, is delayed by a row and two clock cycles to get aligned with the center pixel.

### 2D Convolution Module

* It takes a 9 pixel window, of one channel, multiply each pixel with corresponding selected filter coefficients, sums the results, clamps them to [0,255], and outputs one filtered pixel per cycle.

* We use two coefficients path for the full Sobel and Scharr filter as they require two separate convolutions on the same window, one for horizontal gradient Gx and another for vertical gradient Gy then combining them both via `|Gx| + |Gy|`.

* Having two parallel paths allow to maintain the same throughput all over the system, and for single kernel filters second path is set zero, which becomes hardwired due to generate/case block in Verilog reducing resource consumption. To avoid overflows, the bit widths are added accordignly so that full precision value is preserved in the pipeline.

* There are four stages in here, first we do the 18 multiplications (9 multiplications for single kernel), next stage the row addition occurs, in the third stage we do the column summation and in the last stage we do the normalization of pixels and clamp them if required.

## System Integration

The IP created is used in another Vivado block design project where its integrated with the Zynq PS and the AXI VDMA IP using the processor system reset IP and AXI interconnect with ILA to verify before hardware implementation, with appropiate parameters are set. And then from Vitis using C code we implement UART transfer of input and output raw bin file of image from and to the PC, and also manually manage cache coherence via explicit flush/invalidate as the VDMA goes directly to DDR via AXI to bypass the CPU cache.

### UART Configuration

* UART1 is used for image data transfer as UART0 is already owned by `init_platform()` for console output, so reinitializing UART0 causes console corruption.

* In the C porgram we utilize the function `XUartPs_Send`/`XUartPs_Recv` to transfer as many bytes as UART FIFO can handle per call. Thus the loop will accumulate the the partial transfers until the full image is transfered.

### Cache Management

* The ARM core writes image bytes into a CPU cache line. So without flushing, those bytes may not exist in physical DDR, but still the VDMA which goes to DDR directly via AXI, bypassing the CPU cache would read stale/garbage values. Hence used `Xil_DCacheFlushRange` before DmaStart.

* Again as the VDMA writes filtered pixels directly into DDR. The CPU's cache may still hold old data for those addresses. So invalidating forces the CPU to fetch from DDR on the next read, ensuring it sees what the VDMA actually wrote, done using `Xil_DCacheInvalidateRange` after DmaStop.

## Verification

### Vivado Behavioral Simulation

* Image data is loaded in a hex file (RGB/grayscale) generated by `img2hex.py`(`--mode rgb` or `--mode gray`). Output image is captured and converted back to image using again python program `hex2img.py`. This is done using the testbench `image_filter_top_tb.v`.

* Then again the quality of the filtered image is checked with another python program `quality.py`, which computed the MSE/PSNR/SSIM using scikit image using an independently derived golden reference, thus verifying the math is working correctly and output matching the expected one numerically.

### Hardware Verification

* The PS recieves input image over UART1 via `uart.py`, then runs the full design system and sends the filtered output back. Then `quality.py` checks on the result against an independent reference with same integer arithmetic and edge replication convention as in RTL files.

* There had been a single corner pixel discrepancy consistent across all filters and is due to the write completion timing margin at end of the frame, the frame counter IRQ fires as the last DMA burst is issued potentially slightly before write response confirms it has landed in DDR.

| Filter | MSE | PSNR | SSIM |
|---|---|---|---|
| Gaussian Blur | 0.038 | 62.34 dB | 1.00000 | 
| Full Sobel | 0.230 | 54.51 dB | 1.00000 | 
| Sharpen | 0.046 | 61.52 dB | 1.00000 | 
| Scharr | 0.230 | 54.51 dB | 1.00000 |

## Repository Structure

* Within `\ip` are the RTL files (`\rtl`) of the filter IP having within them `image_filter_top.v`, `window.v`, `lineBuffer.v`, `convolution.v` and testbench files (`\tb`) for simulation which was `image_filter_top_tb.v`.

* In `\system` there are script files (`\scripts`) which contains the block design TCL file `imageFilterSoC.tcl` which can be used to run in Vivado and recreate the SoC integration.

* In `\sw`, under the `\vitis` are the bare metal application codes in C which are `main.c`,`platform.c`, `platform.h` & `platform_config.h`, while under the `\python_tools` are the image conversion and quality verification files, that is, `img2bin.py`, `bin2img.py`, `img2hex.py`, `hex2img.py`, `quality.py` and UART based image transfer file `uart.py`.

* Under the `\images` are the input and output filtered images, along with reference images for README used in here.

## Requirements

* **Board**: Xilinx ZCU104 Ultrascale+ MPSoC

* **EDA Tools**: Vitis 2022.2, Vivado 2022.2

* **UART**: 2 COM ports required for console (UART0) and image transfer (UART1)

* The filter selection requires here a full Vivado rebuilding as kernel is a compile time parameter in the filter IP, thus the runtime reconfigurability would require AXI4 Lite slave based port loading kernels at runtime.

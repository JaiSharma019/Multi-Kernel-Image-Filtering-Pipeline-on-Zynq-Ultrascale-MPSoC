#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xaxivdma.h"
#include "xil_cache.h"

// image dimensions
#define IMAGE_WIDTH  512
#define IMAGE_HEIGHT 512
#define BYTES_PER_PIXEL 3

// DDR memory addresses for the frames
#define MEM_BASE_ADDR       0x10000000
#define SRC_BUFFER_ADDR     MEM_BASE_ADDR
#define DEST_BUFFER_ADDR    (MEM_BASE_ADDR + 0x01000000) // offset by 16MB for safety

XAxiVdma VdmaInstance; // creating a driver instance for the VDMA

// for UART based image transfer into FPGA
#include "xuartps.h"

XUartPs UartInstance;

// blocks until exactly NumBytes have been transferred either send or recieve, as single XUartPs_Send/Recv call only moves whatever FIFO can hold in that call, looping needed for large buffers
static void UartTransferAll(XUartPs *Uart, u8 *BufferPtr, u32 NumBytes, int isSend)
{
    u32 totalDone = 0;
    while (totalDone < NumBytes) {
        u32 done;
        if (isSend) {
            done = XUartPs_Send(Uart, BufferPtr + totalDone, NumBytes - totalDone);
        } else {
            done = XUartPs_Recv(Uart, BufferPtr + totalDone, NumBytes - totalDone);
        }
        totalDone += done;
    }
}

int main()
{
    init_platform(); // for initializing the UART and caches

    xil_printf("\r\n--- Starting ---\r\n");
    int Status;

    // UART based transfer
    XUartPs_Config *UartCfg;
    UartCfg = XUartPs_LookupConfig(XPAR_XUARTPS_1_DEVICE_ID);
    if (!UartCfg) {
        xil_printf("UART lookup failed!\r\n");
        return XST_FAILURE;
    }
    Status = XUartPs_CfgInitialize(&UartInstance, UartCfg, UartCfg->BaseAddress);
    if (Status != XST_SUCCESS) {
        xil_printf("UART init failed!\r\n");
        return XST_FAILURE;
    }

    xil_printf("UART ready (115200 baud).\r\n");   // just a check



    XAxiVdma_Config *Config;

    // look up the VDMA hardware configuration
    Config = XAxiVdma_LookupConfig(XPAR_AXIVDMA_0_DEVICE_ID);
    if (!Config) {
        xil_printf("No VDMA found in hardware layout!\r\n");
        return XST_FAILURE;
    }

    // initializing the VDMA driver
    Status = XAxiVdma_CfgInitialize(&VdmaInstance, Config, Config->BaseAddress);
    if (Status != XST_SUCCESS) {
        xil_printf("VDMA Initialization Failed!\r\n");
        return XST_FAILURE;
    }

    xil_printf("VDMA Initialized Successfully.\r\n");

    XAxiVdma_FrameCounter FrameCfg;
    FrameCfg.ReadFrameCount  = 1;   // fire after exactly 1 frame on MM2S
    FrameCfg.WriteFrameCount = 1;   // fire after exactly 1 frame on S2MM

    Status = XAxiVdma_SetFrameCounter(&VdmaInstance, &FrameCfg);
    if (Status != XST_SUCCESS) {
        xil_printf("SetFrameCounter failed\r\n");
        return XST_FAILURE;
    }
    //


    // setting up read channel
    XAxiVdma_DmaSetup ReadCfg;
    ReadCfg.VertSizeInput = IMAGE_HEIGHT + 1; // adding extra 1 to flush last row

    ReadCfg.HoriSizeInput       = IMAGE_WIDTH * BYTES_PER_PIXEL;
    ReadCfg.Stride              = IMAGE_WIDTH * BYTES_PER_PIXEL;
    ReadCfg.FrameDelay          = 0;
    ReadCfg.EnableCircularBuf   = 0;
    ReadCfg.EnableSync          = 0;
    ReadCfg.PointNum            = 0;
    ReadCfg.EnableFrameCounter  = 0;
    ReadCfg.FixedFrameStoreAddr = 0;

    Status = XAxiVdma_DmaConfig(&VdmaInstance, XAXIVDMA_READ, &ReadCfg);
    if (Status != XST_SUCCESS) { xil_printf("Read config failed\r\n"); return XST_FAILURE; }

    // telling the read channel where to find the original image
    UINTPTR SrcAddr = SRC_BUFFER_ADDR;
    Status = XAxiVdma_DmaSetBufferAddr(&VdmaInstance, XAXIVDMA_READ, &SrcAddr);

    // setting up the write channel
    XAxiVdma_DmaSetup WriteCfg;
    WriteCfg.VertSizeInput = IMAGE_HEIGHT;
    WriteCfg.HoriSizeInput = IMAGE_WIDTH * BYTES_PER_PIXEL;
    WriteCfg.Stride        = IMAGE_WIDTH * BYTES_PER_PIXEL;
    WriteCfg.FrameDelay    = 0;
    WriteCfg.EnableCircularBuf = 0;
    WriteCfg.EnableSync    = 0;
    WriteCfg.PointNum      = 0;
    WriteCfg.EnableFrameCounter = 1; 
    WriteCfg.FixedFrameStoreAddr = 0;


    Status = XAxiVdma_DmaConfig(&VdmaInstance, XAXIVDMA_WRITE, &WriteCfg);
    if (Status != XST_SUCCESS) { xil_printf("Write config failed\r\n"); return XST_FAILURE; }

    // for write channel where to save the filtered image
    UINTPTR DestAddr = DEST_BUFFER_ADDR;
    Status = XAxiVdma_DmaSetBufferAddr(&VdmaInstance, XAXIVDMA_WRITE, &DestAddr);
    XAxiVdma_StartFrmCntEnable(&VdmaInstance, XAXIVDMA_WRITE);


    xil_printf("VDMA Configured. Preparing to launch hardware...\r\n");

    // UART based image transfer
    xil_printf("Waiting for input image over UART (%d bytes)...\r\n", IMAGE_WIDTH*IMAGE_HEIGHT*BYTES_PER_PIXEL);
    UartTransferAll(&UartInstance, (u8 *)SRC_BUFFER_ADDR, IMAGE_WIDTH*IMAGE_HEIGHT*BYTES_PER_PIXEL, 0);
    xil_printf("Input image received.\r\n");


    // manual cache management, flushing the processor's cache to physical RAM so the VDMA can see the input image
    Xil_DCacheFlushRange(SRC_BUFFER_ADDR, IMAGE_WIDTH * (IMAGE_HEIGHT+1) * BYTES_PER_PIXEL);

    memset((void *)DEST_BUFFER_ADDR, 0x00, IMAGE_WIDTH * IMAGE_HEIGHT * BYTES_PER_PIXEL);
    Xil_DCacheFlushRange(DEST_BUFFER_ADDR, IMAGE_WIDTH * IMAGE_HEIGHT * BYTES_PER_PIXEL);

    // starting the hardware
    // first start the write channel, so it is ready to catch the pixels
    Status = XAxiVdma_DmaStart(&VdmaInstance, XAXIVDMA_WRITE);
    // then start the read channel to push the pixels in
    Status = XAxiVdma_DmaStart(&VdmaInstance, XAXIVDMA_READ);

    xil_printf("Hardware accelerator is running...\r\n"); // a check

    u32 pending;
    do {
        pending = XAxiVdma_IntrGetPending(&VdmaInstance, XAXIVDMA_WRITE);
    } while (!(pending & XAXIVDMA_IXR_FRMCNT_MASK));
    xil_printf("Frame count IRQ observed, proceeding to stop...\r\n");  
    // clearing the interrupt after getting observed
    XAxiVdma_IntrClear(&VdmaInstance, XAXIVDMA_IXR_FRMCNT_MASK, XAXIVDMA_WRITE);

    // stopping as complete frame would be in DDR by now
    XAxiVdma_DmaStop(&VdmaInstance, XAXIVDMA_READ);
    XAxiVdma_DmaStop(&VdmaInstance, XAXIVDMA_WRITE);

    while (XAxiVdma_IsBusy(&VdmaInstance, XAXIVDMA_WRITE)) {
        // waiting for clean halt confirmation
    }

    Xil_DCacheInvalidateRange(DEST_BUFFER_ADDR, IMAGE_WIDTH * IMAGE_HEIGHT * BYTES_PER_PIXEL);
    xil_printf("SUCCESS! Filtered image at 0x%08X\r\n", DEST_BUFFER_ADDR);

    // UART based image tranasfer
    xil_printf("Sending output image over UART...\r\n");
    UartTransferAll(&UartInstance, (u8 *)DEST_BUFFER_ADDR, IMAGE_WIDTH*IMAGE_HEIGHT*BYTES_PER_PIXEL, 1);
    xil_printf("Output image sent.\r\n");
    
    cleanup_platform();
    return 0;
}

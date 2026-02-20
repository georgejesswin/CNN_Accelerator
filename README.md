# CNN Accelerator
## FPGA-Based Depthwise Separable Convolution Engine for MobileNetSSD

### 📌 Overview

This project implements a hardware accelerator for Convolutional Neural Networks (CNNs) in Verilog, specifically optimized for MobileNet-style depthwise separable convolutions.

The design targets FPGA deployment and accelerates the fundamental building block of MobileNetSSD:

```
Depthwise Convolution (3×3)
        +
Pointwise Convolution (1×1)
```

The architecture is fully streaming, AXI-Stream compliant, and optimized for FPGA resource efficiency using:

- Parallel MAC arrays
- Tiled computation
- BRAM-based weight blocking
- Pipelined arithmetic
- Backpressure-safe streaming

### 🏗 Architecture Overview

#### 🔹 Depthwise Separable Convolution Block

Each block implements:

```
Input Feature Map
        ↓
Depthwise 3×3 Convolution (per channel)
        ↓
Pointwise 1×1 Convolution (channel mixing)
        ↓
Output Feature Map
```

This matches the MobileNet architecture used in MobileNetSSD.

#### 🔬 High-Level Hardware Architecture

```
            AXI-Stream Input
                    │
                    ▼
           depthwise_layer_stream
                    │
                    ▼
           pointwise_layer_stream
                    │
                    ▼
            AXI-Stream Output
```

The top-level module:

`conv_dw_pw_top.v`

connects depthwise and pointwise layers directly via AXI backpressure.

### 📦 Project Structure

#### 🟢 1. Depthwise Convolution Subsystem

**depthwise_conv.v**

Implements streaming 3×3 depthwise convolution:

- One convolution per input channel
- Fully streaming architecture
- AXI-Stream slave + master
- Backpressure-aware

##### Key Internal Modules

| Module | Purpose |
|--------|---------|
| depthwise_image_control.v | 3×3 sliding window generator using line buffers |
| depthwise_kernel.v | Per-channel kernel storage |
| depthwise_mac.v | MAC datapath |

##### Depthwise Characteristics

- Produces 1 spatial pixel per cycle (after warm-up)
- Parallel across channels
- Fully pipelined
- Zero internal spatial blocking

#### 🔵 2. Pointwise Convolution Subsystem (1×1 Conv)

**pointwise_layer_stream.v**

Implements channel mixing via tiled 1×1 convolution.

Unlike depthwise, this layer is tiled across channels.

##### 🔹 Parallelism Configuration

```
PAR_CIN  = 16
PAR_COUT = 16
```

This means:

- 16 input channels processed per cycle
- 16 output channels computed in parallel

##### 🔹 Tiling Strategy

Given:

```
CIN  = 32
COUT = 64
```

The engine performs:

```
NUM_CIN_ITER  = CIN / PAR_CIN  = 2
NUM_COUT_ITER = COUT / PAR_COUT = 4
```

Per spatial pixel:

4 output blocks × 2 input blocks

Accumulation happens over multiple cycles.

##### Key Internal Modules

| Module | Purpose |
|--------|---------|
| pointwise_conv1x1_fsm_axis.v | Tiling controller FSM |
| pointwise_weight_regs.v | BRAM-based block weight storage |
| pointwise_mac_datapath.v | Fully pipelined MAC tree |

##### 🔹 Pointwise MAC Architecture

Each cycle performs:

```
16 output channels × 16 input channels
= 256 multiplications
```

The datapath contains:

- DSP-mapped multipliers
- Pipelined adder tree
- Accumulator registers
- Latency-aligned control

Latency:

```
MAC_LATENCY = 2 + log2(PAR_CIN)
```

### 🧠 Dataflow Model

#### Depthwise Layer

- Streaming spatial pipeline
- No spatial blocking
- Output: full CIN channel vector per pixel

#### Pointwise Layer

- Spatially blocking per pixel
- Channel-tiled accumulation
- Output generated after full CIN accumulation

### ⚙️ Top-Level Integration

**conv_dw_pw_top.v**

Implements:

- AXI slave input
- Depthwise layer
- Direct AXI chaining to pointwise
- AXI master output
- Independent weight loading interfaces

No FIFOs are used in the final version — backpressure is fully AXI-driven.

### 📊 Performance Characteristics

#### Depthwise

- Throughput: 1 pixel / cycle
- Highly efficient
- Fully pipelined

#### Pointwise (8×8 Tiled)

For:

```
CIN  = 32
COUT = 64
```

Per pixel cycles:

```
NUM_COUT_ITER × (NUM_CIN_ITER + MAC_LATENCY)
≈ 4 × (2 + 6)
≈ 32 cycles per pixel
```

Thus overall throughput is limited by pointwise tiling.

### 💾 Memory Architecture

#### Depthwise

- Distributed RAM for small kernels
- Line buffers using BRAM
- Per-channel kernel storage

#### Pointwise

- BRAM-based tiled weight storage
- Block-organized memory layout
- No full-memory reset
- Linear-to-tile address remapping

### 🔁 AXI Streaming Behavior

All layers use:

- s_axis_tvalid
- s_axis_tready
- m_axis_tvalid
- m_axis_tready

Backpressure propagates naturally:

```
Output stall
    ↓
Pointwise stall
    ↓
Depthwise stall
    ↓
Input stall
```

No data loss.
Fully AXI-compliant.

### 🎯 Design Goals

- Efficient FPGA implementation
- Modular separable convolution block
- Parameterizable CIN / COUT
- Reusable MAC datapath
- Clean tiling logic
- Backpressure-safe streaming

### 📐 Design Philosophy

This accelerator emphasizes:

- Hardware realism
- Explicit tiling control
- Deterministic latency
- Clean modular boundaries
- FPGA-friendly arithmetic

The architecture reflects real-world constraints:

- Limited DSP count
- Limited BRAM
- Controlled parallelism
- Balanced resource usage

### ⚠ Known Architectural Limitation

The current pointwise layer uses spatial blocking per pixel.

This limits throughput to:

~1 pixel per 32 cycles (for 32×64 case)

Future optimization would require:

- Spatial streaming accumulation
- Systolic pointwise engine
- Cross-pixel overlap

### 📚 Model Support

The hardware is designed for:

- MobileNetSSD
- Caffe-based .prototxt and .caffemodel
- Depthwise separable convolution networks

### 🏁 Summary

This project implements:

- A full separable convolution accelerator
- FPGA-optimized tiled pointwise engine
- Streaming depthwise convolution
- AXI-compliant modular design
- Hardware-aware CNN execution



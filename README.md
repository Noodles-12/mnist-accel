# mnist-accel

A from-scratch MNIST digit classifier built as a fully pipelined SystemVerilog inference accelerator, targeting a Xilinx Zynq-7020 (Arty Z7-20 Rev.B). A PyTorch training/INT8-quantization pipeline produces the weights, and a UART link lets a PC (including a live webcam feed) push images to the board and read back the predicted digit.

## Status

Working on getting hands on an actual Arty Z7-20 to demonstrate this on real hardware and confirm it works.

## Architecture

```
image (28x28, quint8)
  -> conv1      16 filters, 5x5, 25-wide parallel MAC array + 5-stage adder tree, ReLU + requantize
  -> max_pool   2x2, stride 2
  -> fc1        64 neurons, 16-lane parallel MAC, ReLU + requantize
  -> fc2        10 classes, 10-lane parallel MAC, raw logits
  -> argmax     4-stage pipelined pairwise reduction tree
  -> digit      4-bit output
```

Quantization matches PyTorch's static INT8 calibration exactly: symmetric quint8 activations (zero_point = 128), symmetric qint8 weights (zero_point = 0), and a fixed-point requantize between every layer —

```
q_out = clamp(((acc * M0 + round_bias) >>> SHIFT) + ZERO_POINT, 0, 255)
```

with `M0`/`SHIFT` derived per layer from the calibrated weight/activation/output scales, so there's no floating point anywhere in the datapath.

## Repo layout

| Path | Contents |
|---|---|
| `mnist_cnn_training.py` | PyTorch training + eager-mode static INT8 quantization + weight/bias export to `.mem` files |
| `gen_test_image.py` | pulls a real MNIST test image, quantizes it, and computes a bit-exact Python golden reference for every pipeline stage — used by the RTL testbenches |
| `webcam_capture.py` | captures a digit from a webcam and streams it to the FPGA over UART |
| `mnist_cnn_export/` | weight/bias `.mem` files exported from the trained model (symlinked into the RTL tree so they're never stale) |
| `mnist_fpga/mnist_fpga.srcs/sources_1/new/` | RTL sources |
| `mnist_fpga/mnist_fpga.srcs/sim_1/new/` | testbenches |
| `mnist_fpga/mnist_fpga.srcs/constrs_1/new/` | XDC constraints (Arty Z7-20) |

### RTL modules

| Module | Role |
|---|---|
| `fpga_top` | board-level top: UART → `accel_top`, drives status LEDs |
| `accel_top` | pure compute top: image in, digit out — no UART awareness |
| `conv_layer` / `conv_dp` / `conv_mem` | conv1 |
| `max_pool` / `pool_dp` / `pool_mem` | max pooling |
| `fc1_layer` / `fc1_dp` / `fc1_mem` | fc1 |
| `fc2_layer` / `fc2_dp` / `fc2_mem` | fc2 |
| `argmax_layer` | pipelined argmax |
| `uart_rx` / `uart_cmd` | UART receiver + command/opcode decoder |

## UART protocol

Host → FPGA only, 115200 baud. The top 2 bits of each header byte are a 2-bit opcode:

| Opcode | Meaning | Packet |
|---|---|---|
| `01` | image pixel write | `[01 0000 addr[9:8]]` `[addr[7:0]]` `[pixel]` — 3 bytes |
| `10` | start inference | `[10 000000]` — 1 byte |
| `00` / `11` | no-op | ignored |

784 pixel packets (one 28×28 image) followed by a single START byte triggers a full inference — about 19,000 cycles, ~150 µs at 125 MHz. `webcam_capture.py` builds and sends this stream for you: **SPACE** captures a frame and sends it (repeatable — press it as many times as you like), **q** quits.

## Getting started

```bash
# generate a golden reference for one MNIST test image (for RTL sim)
python3 gen_test_image.py --index 0
```

To simulate the full pipeline against that golden reference in Vivado:

1. Open `mnist_fpga/mnist_fpga.xpr` in Vivado.
2. In the **Sources** window, switch to the **Simulation Sources** view, expand `sim_1`, right-click `top_tb`, and choose **Set as Top**.
3. In the **Flow Navigator**, under **SIMULATION**, click **Run Simulation → Run Behavioral Simulation**.
4. Watch the Tcl console — it prints a per-stage pass/fail summary and finishes with `PASS: full pipeline matches golden, digit = N`.

`fpga_top_tb`, `fc1_layer_tb`, and `conv_layer_tb` under the same `sim_1` fileset work the same way — just set whichever one you want as top before running.

For the live webcam path: `python3 webcam_capture.py --port /dev/ttyUSB0` (omit `--port` to just preview captures without sending).

## Synthesis / timing

Implemented (synth → place → route) against the Arty Z7-20's real 125 MHz clock:

- 0 errors, 0 critical warnings
- Timing: WNS +0.060 ns, TNS 0.000 ns, 0 failing endpoints

## Known limitation

`fc1_mem`'s activation buffer is indexed by two runtime signals at once, which Vivado can't map to block RAM — it falls back to roughly 18,400 flip-flops instead. That's the biggest contributor to this design's FF count.

It's a known tradeoff, not a bug. Splitting the buffer into 16 per-channel banks would let it infer as BRAM, but hasn't been worth doing yet since the design already fits comfortably and timing still closes.

#!/usr/bin/env python3
"""
Pulls one real image out of the MNIST test set, quantizes it the same way the
trained model's QuantStub does (symmetric quint8, zero_point=128), and writes
it out as a conv_mem-compatible .mem file for RTL simulation.

Also computes a bit-exact golden reference for conv1's post-bias-ReLU output
(16 filters x 24x24), using the same int8 weights / int32 bias / integer
arithmetic the RTL uses, so a testbench can compare against it directly with
no floating point involved anywhere in the comparison.

No numpy/torch required -- MNIST's IDX format and .npy's header are both
trivial to parse by hand, and the golden conv is small enough for pure
Python (16 * 24 * 24 * 25 ~= 230k MACs).

Usage:
    python3 gen_test_image.py --index 0
    python3 gen_test_image.py --index 17 --out-dir mnist_fpga/mnist_fpga.srcs/sim_1/new
"""
import argparse
import ast
import os
import struct
import zlib


def read_npy_scalar(path):
    with open(path, "rb") as f:
        assert f.read(6) == b"\x93NUMPY", f"{path} is not a .npy file"
        major, _minor = f.read(2)
        hlen = struct.unpack("<H" if major == 1 else "<I", f.read(2 if major == 1 else 4))[0]
        header = ast.literal_eval(f.read(hlen).decode().strip())
        data = f.read()
    fmt = {"<f4": "f", "<f8": "d"}[header["descr"]]
    return struct.unpack("<" + fmt, data)[0]


def read_mnist_image(idx_path, index):
    with open(idx_path, "rb") as f:
        magic, n, rows, cols = struct.unpack(">IIII", f.read(16))
        assert magic == 2051, f"bad magic {magic} in {idx_path}"
        assert 0 <= index < n, f"index {index} out of range (0..{n-1})"
        f.seek(16 + index * rows * cols)
        raw = f.read(rows * cols)
    return rows, cols, list(raw)


def read_mnist_label(idx_path, index):
    with open(idx_path, "rb") as f:
        magic, n = struct.unpack(">II", f.read(8))
        assert magic == 2049, f"bad magic {magic} in {idx_path}"
        f.seek(8 + index)
        return f.read(1)[0]


def read_hex_mem(path, signed_width=None):
    vals = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            v = int(line, 16)
            if signed_width is not None and v >= (1 << (signed_width - 1)):
                v -= 1 << signed_width
            vals.append(v)
    return vals


def fit_input_scale(export_dir):
    """
    bias_int32[i] == round(bias_fp32[i] / (input_scale * weight_scale)), the
    convention export_bias() in mnist_cnn_training.py uses. Recover
    bias_scale by least-squares (robust to per-entry rounding noise), then
    divide out weight_scale.
    """
    weight_scale = read_npy_scalar(os.path.join(export_dir, "conv1_weight_scale.npy"))
    bias_fp32 = [float(l) for l in open(os.path.join(export_dir, "conv1_bias.txt"))]
    bias_int32 = read_hex_mem(os.path.join(export_dir, "conv1_bias.mem"), signed_width=32)

    num = sum(t * m for t, m in zip(bias_fp32, bias_int32))
    den = sum(m * m for m in bias_int32)
    bias_scale = num / den
    return bias_scale / weight_scale, weight_scale, bias_int32


def quantize_pixel(raw_byte, input_scale):
    """Mirrors the model's QuantStub: quint8, symmetric, zero_point=128.
    Input to the stub is ToTensor()'s raw_byte/255 (no Normalize in the
    training pipeline), so: q = round((raw_byte/255) / input_scale) + 128."""
    q = round((raw_byte / 255.0) / input_scale) + 128
    return max(0, min(255, q))


def compute_golden_conv1(q_pixels, rows, cols, weights, bias_int32):
    """weights: flat list of 16*25 int8, filter-major, kernel taps in
    row-major (ky*5+kx) order -- exactly conv1_weights.mem / conv_addr_calc's
    layout. Returns golden[f][y][x], post-bias, post-ReLU, always >= 0."""
    num_filters, ksize = 16, 5
    out_h, out_w = rows - ksize + 1, cols - ksize + 1
    golden = [[[0] * out_w for _ in range(out_h)] for _ in range(num_filters)]

    for f in range(num_filters):
        w = weights[f * 25:(f + 1) * 25]
        for oy in range(out_h):
            for ox in range(out_w):
                acc = 0
                for ky in range(ksize):
                    row = oy + ky
                    base = row * cols + ox
                    wrow = w[ky * 5:ky * 5 + 5]
                    for kx in range(ksize):
                        acc += wrow[kx] * (q_pixels[base + kx] - 128)
                acc += bias_int32[f]
                relu_val = acc if acc > 0 else 0
                golden[f][oy][ox] = requantize(relu_val)
    return golden


REQUANT_M0 = 77
REQUANT_SHIFT = 16
REQUANT_ZERO_POINT = 128


def requantize(relu_val, m0=REQUANT_M0, shift=REQUANT_SHIFT, zero_point=REQUANT_ZERO_POINT):
    round_bias = 1 << (shift - 1) if shift > 0 else 0
    shifted = (relu_val * m0 + round_bias) >> shift
    return max(0, min(255, shifted + zero_point))


FC1_REQUANT_M0 = 45
FC1_REQUANT_SHIFT = 16
FC1_REQUANT_ZERO_POINT = 128


def requantize_fc1(relu_val):
    round_bias = 1 << (FC1_REQUANT_SHIFT - 1) if FC1_REQUANT_SHIFT > 0 else 0
    shifted = (relu_val * FC1_REQUANT_M0 + round_bias) >> FC1_REQUANT_SHIFT
    return max(0, min(255, shifted + FC1_REQUANT_ZERO_POINT))


def compute_golden_fc1(pooled, fc1_weights, fc1_bias_int32,
                        num_neurons=64, num_channels=16, spatial=144):
    per_neuron = num_channels * spatial
    out = []
    for n in range(num_neurons):
        acc = 0
        for c in range(num_channels):
            wbase = n * per_neuron + c * spatial
            for s in range(spatial):
                acc += fc1_weights[wbase + s] * (pooled[c][s // 12][s % 12] - 128)
        acc += fc1_bias_int32[n]
        relu_val = acc if acc > 0 else 0
        out.append(requantize_fc1(relu_val))
    return out


def compute_golden_fc2(fc1_out, fc2_weights, fc2_bias_int32,
                        num_classes=10, num_inputs=64):
    acc = []
    for n in range(num_classes):
        a = sum(fc2_weights[n * num_inputs + i] * (fc1_out[i] - 128)
                for i in range(num_inputs))
        acc.append(a + fc2_bias_int32[n])
    return acc


def compute_golden_pool(golden_conv1):
    """2x2 non-overlapping max pool, stride 2, over each filter's 24x24
    golden conv1 output -> 12x12. Matches pool_addr_calc's addressing
    (window taps at 2*idx_x+DX, 2*idx_y+DY) once that's implemented
    correctly."""
    num_filters = len(golden_conv1)
    out_h, out_w = len(golden_conv1[0]) // 2, len(golden_conv1[0][0]) // 2
    pooled = [[[0] * out_w for _ in range(out_h)] for _ in range(num_filters)]
    for f in range(num_filters):
        for oy in range(out_h):
            for ox in range(out_w):
                window = [
                    golden_conv1[f][2 * oy][2 * ox],
                    golden_conv1[f][2 * oy][2 * ox + 1],
                    golden_conv1[f][2 * oy + 1][2 * ox],
                    golden_conv1[f][2 * oy + 1][2 * ox + 1],
                ]
                pooled[f][oy][ox] = max(window)
    return pooled


ASCII_RAMP = " .:-=+*#%@"


def ascii_art(raw_bytes, rows, cols):
    lines = []
    for y in range(rows):
        row = raw_bytes[y * cols:(y + 1) * cols]
        lines.append("".join(ASCII_RAMP[min(9, p * 10 // 256)] for p in row))
    return "\n".join(lines)


def write_png(path, raw_bytes, rows, cols, scale=10):
    """Minimal 8-bit grayscale PNG, nearest-neighbor upscaled, so the picked
    digit can actually be looked at instead of just read as bytes. Built by
    hand with zlib (stdlib) -- no imaging library available/needed."""
    w, h = cols * scale, rows * scale

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0)  # bit_depth=8, color_type=0 (gray)

    raw = bytearray()
    for y in range(h):
        src_y = y // scale
        raw.append(0)  # filter type 0 (none) for this scanline
        for x in range(w):
            src_x = x // scale
            raw.append(raw_bytes[src_y * cols + src_x])
    idat = zlib.compress(bytes(raw), 9)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", idat))
        f.write(chunk(b"IEND", b""))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--index", type=int, default=0, help="MNIST test-set index to export")
    ap.add_argument("--data-dir", default="data/MNIST/raw")
    ap.add_argument("--export-dir", default="mnist_cnn_export")
    ap.add_argument("--out-dir", default="mnist_cnn_export",
                     help="where the .mem files (read by RTL sim, via a symlink into "
                          "sim_1/new/) are written")
    ap.add_argument("--img-dir", default="images",
                     help="where the viewable .png/.txt (not read by RTL) are written")
    args = ap.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    os.makedirs(args.img_dir, exist_ok=True)

    rows, cols, raw = read_mnist_image(os.path.join(args.data_dir, "t10k-images-idx3-ubyte"), args.index)
    label = read_mnist_label(os.path.join(args.data_dir, "t10k-labels-idx1-ubyte"), args.index)
    print(f"MNIST test[{args.index}]: {rows}x{cols}, label={label}")

    input_scale, weight_scale, bias_int32 = fit_input_scale(args.export_dir)
    print(f"  fitted input_scale={input_scale:.8g} (weight_scale={weight_scale:.8g})")

    q_pixels = [quantize_pixel(p, input_scale) for p in raw]
    print(f"  quantized pixel range: [{min(q_pixels)}, {max(q_pixels)}] "
          f"(raw byte range was [{min(raw)}, {max(raw)}])")

    img_path = os.path.join(args.out_dir, "test_image.mem")
    with open(img_path, "w") as f:
        for q in q_pixels:
            f.write(f"{q:02x}\n")
    print(f"  wrote {img_path} ({len(q_pixels)} bytes, row-major addr = row*{cols}+col)")

    weights = read_hex_mem(os.path.join(args.export_dir, "conv1_weights.mem"), signed_width=8)
    golden = compute_golden_conv1(q_pixels, rows, cols, weights, bias_int32)

    out_h, out_w = len(golden[0]), len(golden[0][0])
    golden_path = os.path.join(args.out_dir, "test_image_golden_conv1.mem")
    with open(golden_path, "w") as f:
        for f_idx in range(16):
            for y in range(out_h):
                for x in range(out_w):
                    f.write(f"{golden[f_idx][y][x]:08x}\n")
    n_vals = 16 * out_h * out_w
    all_vals = [golden[f_idx][y][x] for f_idx in range(16) for y in range(out_h) for x in range(out_w)]
    above_floor = sum(1 for v in all_vals if v > REQUANT_ZERO_POINT)
    print(f"  wrote {golden_path} ({n_vals} values, filter-major then row-major "
          f"addr = filter*{out_h*out_w} + y*{out_w}+x)")
    print(f"  golden conv1 output: {above_floor}/{n_vals} above the relu floor "
          f"({REQUANT_ZERO_POINT}), max={max(all_vals)}")

    pooled = compute_golden_pool(golden)
    pool_h, pool_w = len(pooled[0]), len(pooled[0][0])
    pool_path = os.path.join(args.out_dir, "test_image_golden_pool.mem")
    with open(pool_path, "w") as f:
        for f_idx in range(16):
            for y in range(pool_h):
                for x in range(pool_w):
                    f.write(f"{pooled[f_idx][y][x]:08x}\n")
    n_pool_vals = 16 * pool_h * pool_w
    print(f"  wrote {pool_path} ({n_pool_vals} values, filter-major then row-major "
          f"addr = filter*{pool_h*pool_w} + y*{pool_w}+x)")

    fc1_weights = read_hex_mem(os.path.join(args.export_dir, "fc1_weights.mem"), signed_width=8)
    fc1_bias = read_hex_mem(os.path.join(args.export_dir, "fc1_bias.mem"), signed_width=32)
    fc1_out = compute_golden_fc1(pooled, fc1_weights, fc1_bias)
    fc1_path = os.path.join(args.out_dir, "test_image_golden_fc1.mem")
    with open(fc1_path, "w") as f:
        for v in fc1_out:
            f.write(f"{v:02x}\n")
    print(f"  wrote {fc1_path} ({len(fc1_out)} values, one per neuron)")
    print(f"  golden fc1 output: {sum(1 for v in fc1_out if v > FC1_REQUANT_ZERO_POINT)}/{len(fc1_out)} "
          f"above the relu floor ({FC1_REQUANT_ZERO_POINT}), max={max(fc1_out)}")

    fc2_weights = read_hex_mem(os.path.join(args.export_dir, "fc2_weights.mem"), signed_width=8)
    fc2_bias = read_hex_mem(os.path.join(args.export_dir, "fc2_bias.mem"), signed_width=32)
    fc2_acc = compute_golden_fc2(fc1_out, fc2_weights, fc2_bias)
    digit = max(range(len(fc2_acc)), key=lambda n: fc2_acc[n])

    fc2_path = os.path.join(args.out_dir, "test_image_golden_fc2.mem")
    with open(fc2_path, "w") as f:
        for v in fc2_acc:
            f.write(f"{v & 0xFFFFFFFF:08x}\n")
    print(f"  wrote {fc2_path} ({len(fc2_acc)} int32 accumulators, one per class)")

    digit_path = os.path.join(args.out_dir, "test_image_golden_digit.mem")
    with open(digit_path, "w") as f:
        f.write(f"{digit:01x}\n")
    print(f"  wrote {digit_path} (predicted digit = {digit}, image label = {label})")

    readable_path = os.path.join(args.img_dir, f"test_image_{args.index}_readable.txt")
    with open(readable_path, "w") as f:
        f.write(f"MNIST test-set index {args.index}, label={label}\n")
        f.write(f"input_scale={input_scale:.8g}, zero_point=128 (quint8, matches conv1's calibration)\n\n")
        f.write(ascii_art(raw, rows, cols))
        f.write("\n")
    print(f"  wrote {readable_path}")

    png_path = os.path.join(args.img_dir, f"test_image_{args.index}.png")
    write_png(png_path, raw, rows, cols)
    print(f"  wrote {png_path} (raw grayscale, upscaled 10x for viewing)")

    print()
    print(ascii_art(raw, rows, cols))


if __name__ == "__main__":
    main()

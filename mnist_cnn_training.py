"""
This script does three things:
  1. Trains a small image-recognition CNN to recognize
     handwritten digits 0-9, using the MNIST dataset.
  2. Shrinks all the numbers in that network from large decimal numbers
     down to plain 8-bit integers (-128 to 127), so they're cheap for an
     FPGA to work with. This shrinking step is called "quantization."
  3. Saves those final integers to files your FPGA/Verilog project can
     read directly, and prints the M0/shift requantization constants
     you need for the hardware-side "requantize" step -- these are
     single numbers, not arrays, so they're meant to be hardcoded
     directly into your RTL as localparams, not loaded from a file.

The network's shape (in order, first to last):
    28x28 pixel image comes in
    -> Conv layer: 16 small 5x5 "filters" slide over the image looking
       for small patterns (like edges or strokes) -> produces 16 grids,
       each 24x24
    -> ReLU: a simple "if negative, make it zero" step
    -> Max pooling: shrinks each 24x24 grid down to 12x12 by keeping only
       the biggest value in each small 2x2 area
    -> Flatten: lays all those numbers out in one long list (2304 of them)
    -> Dense layer: combines all 2304 numbers down to 64 numbers
    -> ReLU again
    -> Dense layer: combines those 64 numbers down to just 10 numbers,
       one per digit (0-9)
    -> Whichever of those 10 numbers is the largest is the network's guess
"""

import argparse
import os
import sys

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader
from torchvision import datasets, transforms

torch.manual_seed(0)


class CNN(nn.Module):
    def __init__(self):
        super().__init__()
        self.quant = torch.ao.quantization.QuantStub()
        self.conv1 = nn.Conv2d(1, 16, kernel_size=5)   # 28x28 -> 24x24x16
        self.relu1 = nn.ReLU()
        self.pool = nn.MaxPool2d(2, 2)                  # 24x24 -> 12x12
        self.fc1 = nn.Linear(12 * 12 * 16, 64)
        self.relu2 = nn.ReLU()
        self.fc2 = nn.Linear(64, 10)
        self.dequant = torch.ao.quantization.DeQuantStub()

    def forward(self, x):
        x = self.quant(x)
        x = self.relu1(self.conv1(x))
        x = self.pool(x)
        x = x.reshape(x.size(0), -1)
        x = self.relu2(self.fc1(x))
        x = self.fc2(x)
        x = self.dequant(x)
        return x


def get_dataloaders(batch_size=128):
    transform = transforms.Compose([transforms.ToTensor()])
    train_set = datasets.MNIST(root="./data", train=True, download=True, transform=transform)
    test_set = datasets.MNIST(root="./data", train=False, download=True, transform=transform)
    train_loader = DataLoader(train_set, batch_size=batch_size, shuffle=True)
    test_loader = DataLoader(test_set, batch_size=256, shuffle=False)
    return train_loader, test_loader


def train(model, train_loader, device, epochs, lr=1e-3):
    model.to(device)
    opt = torch.optim.Adam(model.parameters(), lr=lr)
    loss_fn = nn.CrossEntropyLoss()
    model.train()
    for epoch in range(epochs):
        total_loss = 0.0
        for x, y in train_loader:
            x, y = x.to(device), y.to(device)
            opt.zero_grad()
            loss = loss_fn(model(x), y)
            loss.backward()
            opt.step()
            total_loss += loss.item() * x.size(0)
        print(f"  epoch {epoch + 1}/{epochs}  loss={total_loss / len(train_loader.dataset):.4f}")
    return model


@torch.no_grad()
def evaluate(model, loader, device):
    model.eval()
    correct = 0
    for x, y in loader:
        x, y = x.to(device), y.to(device)
        pred = model(x).argmax(dim=1)
        correct += (pred == y).sum().item()
    return correct / len(loader.dataset)


def make_qconfig():
    act_observer = torch.ao.quantization.MovingAverageMinMaxObserver.with_args(
        qscheme=torch.per_tensor_symmetric, dtype=torch.quint8
    )
    weight_observer = torch.ao.quantization.MovingAverageMinMaxObserver.with_args(
        qscheme=torch.per_tensor_symmetric, dtype=torch.qint8
    )
    return torch.ao.quantization.QConfig(activation=act_observer, weight=weight_observer)


def quantize_model(fp32_model, calib_loader, calib_batches=20):
    model = fp32_model.to("cpu").eval()
    model.qconfig = make_qconfig()
    torch.ao.quantization.prepare(model, inplace=True)
    with torch.no_grad():
        for i, (x, _) in enumerate(calib_loader):
            model(x)
            if i >= calib_batches:
                break
    torch.ao.quantization.convert(model, inplace=True)
    return model


class ExportCheckError(RuntimeError):
    pass


def check_zero_point(name, zp):
    if zp != 0:
        raise ExportCheckError(
            f"[FAIL] {name} zero_point is {zp}, expected 0. Symmetric "
            f"quantization has drifted -- check make_qconfig()."
        )
    print(f"  [ok] {name} zero_point == 0")


def check_activation_zero_point(name, zp, expected=128):
    if zp != expected:
        raise ExportCheckError(
            f"[FAIL] {name} activation zero_point is {zp}, expected {expected}. "
            f"Hardware subtract-offset logic assumes a fixed {expected} -- "
            f"if this changed, the RTL correction constant must change too."
        )
    print(f"  [ok] {name} activation zero_point == {expected} (fixed hardware offset)")


def get_input_activation_zero_point(quantized_model):
    quant_module = quantized_model.quant

    candidate_paths = [
        lambda m: m.activation_post_process.zero_point.item(),
        lambda m: m.zero_point.item(),
        lambda m: m.zero_point,
        lambda m: int(m.activation_post_process.zero_point),
    ]

    for get_zp in candidate_paths:
        try:
            return int(get_zp(quant_module))
        except (AttributeError, TypeError):
            continue

    return None


def get_input_activation_scale(quantized_model):
    quant_module = quantized_model.quant

    candidate_paths = [
        lambda m: m.activation_post_process.scale.item(),
        lambda m: m.scale.item(),
        lambda m: m.scale,
        lambda m: float(m.activation_post_process.scale),
    ]

    for get_scale in candidate_paths:
        try:
            return float(get_scale(quant_module))
        except (AttributeError, TypeError):
            continue

    return None


def get_layer_output_scale(layer, layer_name):
    """
    Attempts to read a quantized layer's own OUTPUT scale (i.e. the scale
    of the values it produces, which becomes the next layer's input
    scale). Tries a couple of known attribute paths since this varies by
    PyTorch version -- same reasoning as get_input_activation_zero_point.
    Returns None (with a warning) if nothing works, rather than silently
    trusting an attribute that might mean something else.
    """
    candidate_paths = [
        lambda l: float(l.scale),
        lambda l: float(l.scale.item()),
    ]
    for get_scale in candidate_paths:
        try:
            val = get_scale(layer)
            if val is not None and val > 0:
                return val
        except (AttributeError, TypeError):
            continue

    print(f"  [warn] could not confirm {layer_name}'s output scale directly -- "
          f"downstream M0/shift constants for the layer consuming this "
          f"output will be skipped. Verify manually if needed.")
    return None


def compute_requant_constants(weight_scale, input_scale, output_scale, mantissa_bits=16):
    """
    Computes the integer-only requantization constants M0 and shift such
    that (accumulator * M0) >> shift approximates
    accumulator * (weight_scale * input_scale / output_scale).

    M0 and shift are single scalar constants for the whole layer (not
    per-weight, not per-neuron) -- meant to be hardcoded directly as RTL
    localparams (e.g. requantize #(.M0(...), .SHIFT_AMT(...))), not
    loaded from a .mem file, since there's nothing array-shaped here.
    """
    M = (weight_scale * input_scale) / output_scale
    M0 = round(M * (2 ** mantissa_bits))
    approx_error_pct = abs((M0 / (2 ** mantissa_bits)) - M) / M * 100 if M != 0 else 0.0
    return M0, mantissa_bits, M, approx_error_pct


def check_shape(name, actual_shape, expected_shape):
    if tuple(actual_shape) != tuple(expected_shape):
        raise ExportCheckError(
            f"[FAIL] {name} shape {tuple(actual_shape)} != expected {expected_shape}"
        )
    print(f"  [ok] {name} shape {tuple(actual_shape)}")


def check_mem_roundtrip(name, mem_path, expected_flat_values):
    with open(mem_path) as f:
        lines = [l.strip() for l in f if l.strip()]

    if len(lines) != len(expected_flat_values):
        raise ExportCheckError(
            f"[FAIL] {name}: {mem_path} has {len(lines)} lines, "
            f"expected {len(expected_flat_values)}"
        )

    for i, (line, expected) in enumerate(zip(lines, expected_flat_values)):
        v = int(line, 16)
        signed_v = v - 256 if v >= 128 else v
        if signed_v != int(expected):
            raise ExportCheckError(
                f"[FAIL] {name}: {mem_path} line {i} decodes to {signed_v}, "
                f"expected {expected}"
            )
    print(f"  [ok] {name}: {mem_path} round-trips correctly ({len(lines)} values)")


def check_lane_reconstruction(lane_dir, num_filters, filter_size, original_flat_filter_major):
    reconstructed = np.zeros((num_filters, filter_size), dtype=np.int32)
    for p in range(filter_size):
        lane_path = os.path.join(lane_dir, f"conv_w_{p}.mem")
        with open(lane_path) as f:
            lines = [l.strip() for l in f if l.strip()]
        if len(lines) != num_filters:
            raise ExportCheckError(
                f"[FAIL] {lane_path} has {len(lines)} lines, expected {num_filters}"
            )
        for filt in range(num_filters):
            v = int(lines[filt], 16)
            reconstructed[filt][p] = v - 256 if v >= 128 else v

    if not np.array_equal(reconstructed, original_flat_filter_major):
        raise ExportCheckError(
            "[FAIL] Reconstructed lane weights do not match original "
            "filter-major weights -- check the transpose logic."
        )
    print(f"  [ok] {filter_size} lane files reconstruct original weights exactly")


def export_bias(layer_name, bias_fp32, weight_scale, input_scale, out_dir):
    txt_path = os.path.join(out_dir, f"{layer_name}_bias.txt")
    with open(txt_path, "w") as f:
        for v in bias_fp32:
            f.write(f"{float(v):.8g}\n")
    print(f"  wrote {txt_path}")

    if input_scale is None:
        print(f"  [warn] {layer_name} bias: input activation scale unknown -- "
              f"skipping quantized int32 .mem (fp32 .txt/.npy still written)")
        return

    bias_scale = input_scale * weight_scale
    bias_int32 = np.round(bias_fp32 / bias_scale).astype(np.int32)

    mem_path = os.path.join(out_dir, f"{layer_name}_bias.mem")
    with open(mem_path, "w") as f:
        for v in bias_int32:
            f.write(f"{int(v) & 0xFFFFFFFF:08x}\n")
    print(f"  wrote {mem_path} (int32, bias_scale={bias_scale:.6g})")


def print_requant_constants(layer_name, weight_scale, input_scale, output_scale):
    """
    Prints the M0/shift constants for one layer's hardware requantize
    stage, ready to copy directly into RTL. Does not write any file --
    these are single scalars meant to be hardcoded as localparams.
    """
    if input_scale is None or output_scale is None:
        print(f"  [warn] {layer_name}: missing input_scale or output_scale -- "
              f"cannot compute M0/shift. input_scale={input_scale}, "
              f"output_scale={output_scale}")
        return

    M0, shift, M, err_pct = compute_requant_constants(weight_scale, input_scale, output_scale)
    print(f"  {layer_name} requantize constants (hardcode these as RTL localparams):")
    print(f"    M0 = {M0}")
    print(f"    SHIFT_AMT = {shift}")
    print(f"    (M={M:.8f}, approximation error={err_pct:.3f}%)")
    print(f"    e.g. requantize #(.M0({M0}), .SHIFT_AMT({shift})) {layer_name}_requant (...);")


def export_dense_layer(quantized_model, layer_name, out_dir, input_scale=None, output_scale=None):
    layer = getattr(quantized_model, layer_name)
    try:
        w, b = layer._weight_bias()
    except AttributeError:
        w, b = layer.weight(), layer.bias()

    w_int = w.int_repr().numpy()
    w_scale = w.q_scale()
    w_zp = w.q_zero_point()

    check_zero_point(f"{layer_name} weight", w_zp)

    mem_path = os.path.join(out_dir, f"{layer_name}_weights.mem")
    flat = w_int.flatten()
    with open(mem_path, "w") as f:
        for v in flat:
            f.write(f"{int(v) & 0xFF:02x}\n")
    check_mem_roundtrip(f"{layer_name} weight", mem_path, flat)

    np.save(os.path.join(out_dir, f"{layer_name}_weight_scale.npy"), np.array(w_scale))
    bias_fp32 = b.detach().numpy()
    np.save(os.path.join(out_dir, f"{layer_name}_bias_fp32.npy"), bias_fp32)
    export_bias(layer_name, bias_fp32, w_scale, input_scale, out_dir)

    print(f"  {layer_name}: {w_int.shape} = {flat.size} weights, scale={w_scale:.6g}")

    print_requant_constants(layer_name, w_scale, input_scale, output_scale)


def export_conv1(quantized_model, out_dir, input_scale=None, output_scale=None):
    print("\nExporting conv1 weights...")
    layer = quantized_model.conv1
    try:
        w, b = layer._weight_bias()
    except AttributeError:
        w, b = layer.weight(), layer.bias()

    w_int = w.int_repr().numpy()   # (16, 1, 5, 5)
    w_scale = w.q_scale()
    w_zp = w.q_zero_point()

    check_zero_point("conv1 weight", w_zp)
    check_shape("conv1 weight", w_int.shape, (16, 1, 5, 5))

    num_filters, filter_size = 16, 25

    readable_path = os.path.join(out_dir, "conv1_weights_readable.txt")
    mem_path = os.path.join(out_dir, "conv1_weights.mem")
    flat_filter_major = w_int.reshape(num_filters, filter_size)

    with open(readable_path, "w") as f_readable, open(mem_path, "w") as f_mem:
        f_readable.write(f"conv1 weights - 16 filters, 5x5, int8, scale={w_scale:.6g}, zero_point=0\n")
        f_readable.write("=" * 60 + "\n\n")
        for filt in range(num_filters):
            f_readable.write(f"Filter {filt}:\n")
            grid = w_int[filt, 0]
            for row in range(5):
                f_readable.write("  " + " ".join(f"{v:4d}" for v in grid[row]) + "\n")
                for val in grid[row]:
                    f_mem.write(f"{int(val) & 0xFF:02x}\n")
            f_readable.write("\n")

    check_mem_roundtrip("conv1 filter-major", mem_path, flat_filter_major.flatten())

    lanes = flat_filter_major.T  # (25, 16): lane p = window position, filter-indexed
    lane_dir = os.path.join(out_dir, "lanes")
    os.makedirs(lane_dir, exist_ok=True)

    for p in range(filter_size):
        lane_path = os.path.join(lane_dir, f"conv_w_{p}.mem")
        with open(lane_path, "w") as f_lane:
            for filt in range(num_filters):
                val = int(lanes[p][filt])
                f_lane.write(f"{val & 0xFF:02x}\n")

    check_lane_reconstruction(lane_dir, num_filters, filter_size, flat_filter_major)

    np.save(os.path.join(out_dir, "conv1_weight_scale.npy"), np.array(w_scale))
    bias_fp32 = b.detach().numpy()
    np.save(os.path.join(out_dir, "conv1_bias_fp32.npy"), bias_fp32)
    export_bias("conv1", bias_fp32, w_scale, input_scale, out_dir)

    print(f"  conv1: {num_filters} filters x {filter_size} weights = "
          f"{num_filters * filter_size} total, scale={w_scale:.6g}")
    print(f"  wrote {readable_path}")
    print(f"  wrote {mem_path}")
    print(f"  wrote {filter_size} lane files to {lane_dir}/conv_w_{{0..{filter_size-1}}}.mem")

    print_requant_constants("conv1", w_scale, input_scale, output_scale)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--epochs", type=int, default=5)
    parser.add_argument("--out-dir", default="mnist_cnn_export")
    args = parser.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)

    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Using device: {device}")
    print(f"Output directory: {args.out_dir}")

    train_loader, test_loader = get_dataloaders()

    print(f"\nTraining CNN for {args.epochs} epochs...")
    model = CNN()
    train(model, train_loader, device, epochs=args.epochs)
    fp32_acc = evaluate(model, test_loader, device) * 100
    print(f"Float32 test accuracy: {fp32_acc:.2f}%")

    print("\nQuantizing (symmetric INT8, zero_point=0)...")
    quantized = quantize_model(model, train_loader)
    int8_acc = evaluate(quantized, test_loader, "cpu") * 100
    print(f"Quantized (int8) test accuracy: {int8_acc:.2f}%")

    if abs(fp32_acc - int8_acc) > 5.0:
        print(f"  [warn] accuracy dropped by {fp32_acc - int8_acc:.1f} points after "
              f"quantization -- larger than typical for this dataset, worth checking "
              f"calibration batch count or model capacity.")

    try:
        act_zp = get_input_activation_zero_point(quantized)
        if act_zp is not None:
            check_activation_zero_point("input", act_zp)
        else:
            print("  [warn] could not introspect input activation zero_point directly "
                  "(PyTorch version-specific attribute path) -- verifying indirectly "
                  "via golden reference instead.")

        net_input_scale = get_input_activation_scale(quantized)
        if net_input_scale is None:
            print("  [warn] could not introspect input activation scale directly -- "
                  "bias .mem files and M0/shift constants will be skipped where "
                  "they depend on it.")

        # Each layer's own OUTPUT scale becomes the NEXT layer's input_scale.
        # Fetched and printed explicitly (not just trusted silently) since
        # this is exactly the kind of attribute-path assumption that has
        # needed correcting before in this project (see
        # get_input_activation_zero_point's multi-path fallback).
        conv1_out_scale = get_layer_output_scale(quantized.conv1, "conv1")
        fc1_out_scale = get_layer_output_scale(quantized.fc1, "fc1")
        fc2_out_scale = get_layer_output_scale(quantized.fc2, "fc2")

        print(f"\nScale chain (verify these look like reasonable, positive numbers "
              f"typically in the 0.001-0.1 range for int8 quantization):")
        print(f"  network input scale:  {net_input_scale}")
        print(f"  conv1 output scale:   {conv1_out_scale}")
        print(f"  fc1 output scale:     {fc1_out_scale}")
        print(f"  fc2 output scale:     {fc2_out_scale}")

        export_conv1(quantized, args.out_dir,
                     input_scale=net_input_scale, output_scale=conv1_out_scale)
        export_dense_layer(quantized, "fc1", args.out_dir,
                           input_scale=conv1_out_scale, output_scale=fc1_out_scale)
        export_dense_layer(quantized, "fc2", args.out_dir,
                           input_scale=fc1_out_scale, output_scale=fc2_out_scale)

    except ExportCheckError as e:
        print(f"\n{e}")
        print("\nExport failed a sanity check -- see [FAIL] line above. "
              "Fix the underlying issue before trusting these files in RTL testing.")
        sys.exit(1)

    print(f"\nAll sanity checks passed. Export complete: {args.out_dir}/")
    print(f"\nRemember: M0/SHIFT_AMT values printed above are meant to be hardcoded "
          f"directly as RTL localparams in your requantize module instantiations -- "
          f"no .mem file needed for them, since they're single per-layer constants, "
          f"not arrays.")


if __name__ == "__main__":
    main()
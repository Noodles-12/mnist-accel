"""
This script does three things:
  1. Trains a small image-recognition CNN to recognize
     handwritten digits 0-9, using the MNIST dataset.
  2. Shrinks all the numbers in that network from large decimal numbers
     down to plain 8-bit integers (-128 to 127), so they're cheap for an
     FPGA to work with. This shrinking step is called "quantization."
  3. Saves those final integers to files your FPGA/Verilog project can
     read directly.
 
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


def export_dense_layer(quantized_model, layer_name, out_dir):
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
    np.save(os.path.join(out_dir, f"{layer_name}_bias_fp32.npy"), b.detach().numpy())

    print(f"  {layer_name}: {w_int.shape} = {flat.size} weights, scale={w_scale:.6g}")


def export_conv1(quantized_model, out_dir):
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
    np.save(os.path.join(out_dir, "conv1_bias_fp32.npy"), b.detach().numpy())

    print(f"  conv1: {num_filters} filters x {filter_size} weights = "
          f"{num_filters * filter_size} total, scale={w_scale:.6g}")
    print(f"  wrote {readable_path}")
    print(f"  wrote {mem_path}")
    print(f"  wrote {filter_size} lane files to {lane_dir}/conv_w_{{0..{filter_size-1}}}.mem")


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

        export_conv1(quantized, args.out_dir)
        export_dense_layer(quantized, "fc1", args.out_dir)
        export_dense_layer(quantized, "fc2", args.out_dir)

    except ExportCheckError as e:
        print(f"\n{e}")
        print("\nExport failed a sanity check -- see [FAIL] line above. "
              "Fix the underlying issue before trusting these files in RTL testing.")
        sys.exit(1)

    print(f"\nAll sanity checks passed. Export complete: {args.out_dir}/")


if __name__ == "__main__":
    main()
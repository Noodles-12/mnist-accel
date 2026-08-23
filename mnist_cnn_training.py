import os
import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader
from torchvision import datasets, transforms

torch.manual_seed(0)

OUT_DIR = "mnist_cnn_export"
os.makedirs(OUT_DIR, exist_ok=True)


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


def train(model, train_loader, device, epochs=5, lr=1e-3):
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
        print(f"epoch {epoch + 1}/{epochs}  loss={total_loss / len(train_loader.dataset):.4f}")
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
        qscheme=torch.per_tensor_affine, dtype=torch.quint8
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


def export_conv1_weights_as_text(quantized_model):
    """
    Export conv1's weights in the exact layout your RTL memory needs to
    match: 16 filters, each 5x5 = 25 weights, int8, two's-complement.

    Two files are written:
      conv1_weights_readable.txt  - human-readable, one filter per block,
                                     5x5 grid layout, for visually checking
                                     the numbers and planning your memory map
      conv1_weights.mem           - flat hex, one weight per line, ready
                                     for $readmemh, ordered
                                     filter -> row -> col (filter-major)
    """
    layer = quantized_model.conv1
    try:
        w, b = layer._weight_bias()
    except AttributeError:
        w, b = layer.weight(), layer.bias()

    w_int = w.int_repr().numpy()   # shape: (16, 1, 5, 5) -> (num_filters, in_channels, kH, kW)
    w_scale = w.q_scale()
    w_zp = w.q_zero_point()

    assert w_zp == 0, f"conv1 weight zero_point should be 0 (symmetric) - got {w_zp}"
    assert w_int.shape == (16, 1, 5, 5), f"unexpected conv1 weight shape: {w_int.shape}"

    readable_path = os.path.join(OUT_DIR, "conv1_weights_readable.txt")
    mem_path = os.path.join(OUT_DIR, "conv1_weights.mem")

    with open(readable_path, "w") as f_readable, open(mem_path, "w") as f_mem:
        f_readable.write(f"conv1 weights - 16 filters, 5x5, int8, scale={w_scale:.6g}, zero_point=0\n")
        f_readable.write("=" * 60 + "\n\n")

        for filt in range(16):
            f_readable.write(f"Filter {filt}:\n")
            grid = w_int[filt, 0]  # 5x5
            for row in range(5):
                row_vals = grid[row]
                f_readable.write("  " + " ".join(f"{v:4d}" for v in row_vals) + "\n")
                for val in row_vals:
                    mask = 0xFF
                    f_mem.write(f"{int(val) & mask:02x}\n")
            f_readable.write("\n")

    np.save(os.path.join(OUT_DIR, "conv1_weight_scale.npy"), np.array(w_scale))
    np.save(os.path.join(OUT_DIR, "conv1_bias_fp32.npy"), b.detach().numpy())

    print(f"conv1: 16 filters x 25 weights = 400 total weights")
    print(f"  scale={w_scale:.6g}  zero_point={w_zp}")
    print(f"  wrote {readable_path}")
    print(f"  wrote {mem_path}  (400 lines, filter-major order: filter0 row0-4, filter1 row0-4, ...)")


def main():
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Using device: {device}")

    train_loader, test_loader = get_dataloaders()

    model = CNN()
    train(model, train_loader, device, epochs=5)
    print(f"Float32 test accuracy: {evaluate(model, test_loader, device) * 100:.2f}%")

    quantized = quantize_model(model, train_loader)
    print(f"Quantized (int8) test accuracy: {evaluate(quantized, test_loader, 'cpu') * 100:.2f}%")

    export_conv1_weights_as_text(quantized)


if __name__ == "__main__":
    main()
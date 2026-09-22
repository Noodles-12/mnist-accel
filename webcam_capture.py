import argparse
import sys
import time

import cv2
import numpy as np

from gen_test_image import fit_input_scale, quantize_pixel

OP_IMG = 0b01
OP_START = 0b10

BOX_SIZE = 200          # pixels, in the raw camera frame
BOX_CENTER_OFFSET_Y = 0 # positive = move box down from vertical center

OUTPUT_SIZE = (28, 28)
OUTPUT_PATH = "captured_digit_28x28.png"
RAW_SAVE_PATH = "captured_digit_raw.png"


def build_uart_stream(gray28, input_scale, invert):
    """28x28 uint8 -> UART byte stream.

    Quantized exactly like gen_test_image.py so the FPGA sees the same
    quint8/zero_point=128 format the weights were calibrated against.
    MNIST is a white digit on a black background; a photo of ink on paper
    is the opposite, hence --invert.
    """
    flat = gray28.reshape(-1)
    out = bytearray()
    for addr, px in enumerate(flat):
        raw = 255 - int(px) if invert else int(px)
        out.append((OP_IMG << 6) | ((addr >> 8) & 0x03))
        out.append(addr & 0xFF)
        out.append(quantize_pixel(raw, input_scale) & 0xFF)
    out.append(OP_START << 6)
    return bytes(out)


def send_to_fpga(gray28, port, baud, input_scale, invert):
    stream = build_uart_stream(gray28, input_scale, invert)
    try:
        import serial
    except ImportError:
        print("pyserial not installed:  pip install pyserial")
        return
    try:
        with serial.Serial(port, baud, timeout=2) as ser:
            ser.write(stream)
            ser.flush()
    except Exception as e:
        print(f"ERROR: could not send on {port}: {e}")
        return
    print(f"Sent {len(stream)} bytes to {port} "
          f"({len(stream)*10/baud*1000:.0f} ms at {baud} baud) -- START issued")


def get_capture_box(frame_width, frame_height):
    """Return (x1, y1, x2, y2) for a centered square box."""
    cx, cy = frame_width // 2, frame_height // 2 + BOX_CENTER_OFFSET_Y
    half = BOX_SIZE // 2
    x1, y1 = max(0, cx - half), max(0, cy - half)
    x2, y2 = min(frame_width, cx + half), min(frame_height, cy + half)
    return x1, y1, x2, y2


def process_frame(frame, box):
    """crop -> resize -> grayscale. Returns a 28x28 uint8 array."""
    x1, y1, x2, y2 = box
    cropped = frame[y1:y2, x1:x2]

    if cropped.size == 0:
        raise ValueError("Capture box produced an empty crop -- check BOX_SIZE "
                          "against your camera resolution.")

    resized = cv2.resize(cropped, OUTPUT_SIZE, interpolation=cv2.INTER_AREA)
    gray = cv2.cvtColor(resized, cv2.COLOR_BGR2GRAY)
    return gray


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default=None, help="serial port, e.g. /dev/ttyUSB1 (omit to skip sending)")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--export-dir", default="mnist_cnn_export")
    ap.add_argument("--no-invert", action="store_true",
                    help="skip the black/white flip (use if your digit is already white-on-black)")
    args = ap.parse_args()

    input_scale, _, _ = fit_input_scale(args.export_dir)
    print(f"input_scale = {input_scale:.8g} (matches the trained model's QuantStub)")

    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("ERROR: could not open webcam (index 0). Try index 1 if you "
              "have multiple cameras, or check OS camera permissions.")
        sys.exit(1)

    if args.port:
        print(f"Webcam opened. SPACE=capture+send to {args.port}, q=quit.")
    else:
        print("Webcam opened. SPACE=capture, q=quit. (no --port given, will not send)")

    last_saved = None
    while True:
        ok, frame = cap.read()
        if not ok:
            print("ERROR: failed to read frame from webcam.")
            break

        h, w = frame.shape[:2]
        box = get_capture_box(w, h)
        x1, y1, x2, y2 = box

        display = frame.copy()
        cv2.rectangle(display, (x1, y1), (x2, y2), (0, 255, 0), 2)
        cv2.putText(display, "SPACE=capture+send  q=quit", (10, 25),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2)

        if last_saved is not None:
            preview = cv2.resize(last_saved, (140, 140), interpolation=cv2.INTER_NEAREST)
            preview_bgr = cv2.cvtColor(preview, cv2.COLOR_GRAY2BGR)
            ph, pw = preview_bgr.shape[:2]
            display[10:10 + ph, w - 10 - pw:w - 10] = preview_bgr

        cv2.imshow("MNIST capture (put digit in green box)", display)

        key = cv2.waitKey(1) & 0xFF
        if key == ord('q'):
            break
        elif key == ord(' '):
            gray28 = process_frame(frame, box)
            cv2.imwrite(OUTPUT_PATH, gray28)
            cv2.imwrite(RAW_SAVE_PATH, frame[y1:y2, x1:x2])
            last_saved = gray28
            print(f"Captured -> {OUTPUT_PATH}  "
                  f"(shape={gray28.shape}, dtype={gray28.dtype}, "
                  f"min={gray28.min()}, max={gray28.max()})")
            if args.port:
                send_to_fpga(last_saved, args.port, args.baud,
                             input_scale, not args.no_invert)

    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
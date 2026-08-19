import sys
import time

import cv2
import numpy as np

BOX_SIZE = 200          # pixels, in the raw camera frame
BOX_CENTER_OFFSET_Y = 0 # positive = move box down from vertical center

OUTPUT_SIZE = (28, 28)
OUTPUT_PATH = "captured_digit_28x28.png"
RAW_SAVE_PATH = "captured_digit_raw.png"


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
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("ERROR: could not open webcam (index 0). Try index 1 if you "
              "have multiple cameras, or check OS camera permissions.")
        sys.exit(1)

    print("Webcam opened. Press SPACE to capture, 'q' to quit.")

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
        cv2.putText(display, "SPACE=capture  q=quit", (10, 25),
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

    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
import sys
import cv2

print(f"OpenCV version: {cv2.__version__}")
print(f"Platform: {sys.platform}")

for index in range(3):
    print(f"\n--- Trying camera index {index} ---")
    cap = cv2.VideoCapture(index)

    if not cap.isOpened():
        print(f"  Could not open index {index}")
        cap.release()
        continue

    print(f"  Opened index {index} successfully")
    print(f"  Backend: {cap.getBackendName()}")

    ok, frame = cap.read()
    if ok:
        print(f"  SUCCESS: got frame, shape={frame.shape}")
        cap.release()
        print(f"\n==> Use camera index {index} in your main script")
        sys.exit(0)
    else:
        print(f"  Opened but read() failed -- device may be in use, "
              f"permissions blocked, or needs a warm-up delay")
    cap.release()

print("\nNo working camera index found in range 0-2.")
print("Next steps depend on your OS -- see troubleshooting notes.")
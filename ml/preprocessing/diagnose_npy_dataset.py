"""
Checks .npy sign datasets before full processing:
- confirms array shape/dtype are sane
- tests hand-detection rate on a sample of frames per word
"""
import numpy as np
import cv2
import mediapipe as mp
from pathlib import Path

NPY_DIR = Path("dataset/npy_signs")
SAMPLE_SIZE = 30  # frames to test per word (for speed)

mp_hands = mp.solutions.hands


def detect_hand(image_rgb, confidence=0.3):
    with mp_hands.Hands(
        static_image_mode=True,
        max_num_hands=2,
        min_detection_confidence=confidence,
    ) as hands:
        results = hands.process(image_rgb)
        return results.multi_hand_landmarks is not None


def main():
    npy_files = sorted(NPY_DIR.glob("*.npy"))
    print(f"Found {len(npy_files)} .npy files\n")

    for npy_path in npy_files:
        word = npy_path.stem
        arr = np.load(npy_path)

        print(f"=== {word} ===")
        print(f"  Shape: {arr.shape}, dtype: {arr.dtype}")

        if arr.ndim != 4:
            print(f"  WARNING: expected 4D array (num_frames, H, W, 3), got {arr.ndim}D. Skipping detection test.")
            continue

        num_frames = arr.shape[0]
        sample_indices = np.linspace(0, num_frames - 1, min(SAMPLE_SIZE, num_frames), dtype=int)

        detected = 0
        for idx in sample_indices:
            frame = arr[idx]
            # Ensure uint8 (some npy dumps save as float 0-1, which breaks cv2/mediapipe)
            if frame.dtype != np.uint8:
                frame = (frame * 255).astype(np.uint8) if frame.max() <= 1.0 else frame.astype(np.uint8)

            # Assume RGB already (most npy captures are); if colors look wrong later, we may need BGR2RGB
            if detect_hand(frame):
                detected += 1

        rate = detected / len(sample_indices) * 100
        print(f"  Hand detection rate (sample of {len(sample_indices)}): {rate:.0f}%")
        print()


if __name__ == "__main__":
    main()
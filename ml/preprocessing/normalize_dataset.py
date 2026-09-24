"""
Re-normalizes the existing sequence_dataset.npz so each hand's landmarks
are relative to its own wrist position and scaled by hand size —
removing dependence on camera distance/framing.
"""
import numpy as np
from pathlib import Path

INPUT_PATH = Path("ml/models/sequence_dataset.npz")
OUTPUT_PATH = Path("ml/models/sequence_dataset_normalized.npz")


def normalize_frame(frame_features: np.ndarray) -> np.ndarray:
    """frame_features shape: (126,) = left hand (63) + right hand (63)"""
    left = frame_features[:63].reshape(21, 3)
    right = frame_features[63:].reshape(21, 3)

    def normalize_hand(hand: np.ndarray) -> np.ndarray:
        if np.all(hand == 0):
            return hand.flatten()
        wrist = hand[0].copy()
        centered = hand - wrist  # position relative to wrist
        ref_dist = np.linalg.norm(centered[9])  # distance to middle-finger base = hand "size"
        if ref_dist < 1e-6:
            ref_dist = 1.0
        return (centered / ref_dist).flatten()

    return np.concatenate([normalize_hand(left), normalize_hand(right)])


def main():
    data = np.load(INPUT_PATH)
    X, y = data["X"], data["y"]  # X shape: (num_samples, 30, 126)

    X_norm = np.zeros_like(X)
    for i in range(X.shape[0]):
        for t in range(X.shape[1]):
            X_norm[i, t] = normalize_frame(X[i, t])

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(OUTPUT_PATH, X=X_norm, y=y)
    print(f"Normalized {X.shape[0]} samples, saved to {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
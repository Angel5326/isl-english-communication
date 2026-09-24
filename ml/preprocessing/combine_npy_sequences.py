"""
Combines dataset/npy_signs/<word>/*.npy into one training-ready dataset.
Any sequence length is accepted and RESAMPLED to SEQ_LEN frames —
so files from different capture tools (30-frame, 50-frame, etc.)
can all be combined safely.

Saves to ml/models/sequence_dataset.npz
"""
import numpy as np
from pathlib import Path

NPY_DIR = Path("dataset/npy_signs")
OUTPUT_PATH = Path("ml/models/sequence_dataset.npz")

SEQ_LEN = 30       # target length — MUST match your model's expected input
FEATURE_DIM = 126


def resample_sequence(seq: np.ndarray, target_len: int = SEQ_LEN) -> np.ndarray:
    n = seq.shape[0]
    if n == 0:
        return np.zeros((target_len, FEATURE_DIM), dtype=np.float32)
    if n == target_len:
        return seq
    indices = np.linspace(0, n - 1, target_len).astype(int)
    return seq[indices]


def main():
    words = sorted([d.name for d in NPY_DIR.iterdir() if d.is_dir()])
    print(f"Found {len(words)} words: {words}")

    all_sequences = []
    all_labels = []
    skipped = []
    resampled_count = 0

    for word in words:
        folder = NPY_DIR / word
        npy_files = sorted(folder.glob("*.npy"))
        kept_for_word = 0

        for npy_path in npy_files:
            arr = np.load(npy_path)

            if arr.ndim != 2 or arr.shape[1] != FEATURE_DIM:
                # Genuinely wrong shape (not just a different frame count) — skip
                skipped.append((word, npy_path.name, arr.shape))
                continue

            if arr.shape[0] != SEQ_LEN:
                arr = resample_sequence(arr, SEQ_LEN)
                resampled_count += 1

            all_sequences.append(arr)
            all_labels.append(word)
            kept_for_word += 1

        print(f"  {word}: {kept_for_word}/{len(npy_files)} kept")

    X = np.array(all_sequences, dtype=np.float32)
    y = np.array(all_labels)

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(OUTPUT_PATH, X=X, y=y)

    print(f"\nTotal samples: {X.shape[0]}")
    print(f"X shape: {X.shape}")
    print(f"Resampled {resampled_count} sequences to {SEQ_LEN} frames")
    print(f"Words: {sorted(set(y.tolist()))}")
    if skipped:
        print(f"\nSkipped {len(skipped)} files with genuinely invalid shape (not just frame-count mismatch):")
        for word, fname, shape in skipped[:10]:
            print(f"  {word}/{fname}: {shape}")
    print(f"\nSaved to {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
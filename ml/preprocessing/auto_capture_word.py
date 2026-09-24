"""
Automatically captures 200 repetitions of a sign word, saving each as a
raw (unnormalized) 30-frame landmark sequence — same format as your
existing dataset/npy_signs/<word>/*.npy files.

A repetition is saved ONLY if every single frame had a hand detected.
If even one frame is missing a hand, the whole repetition is rejected
and retried automatically.

Usage:
    python ml/preprocessing/auto_capture_word.py hello

Controls during capture:
    p  - pause/resume (freezes the countdown, use it to take a break)
    q  - quit early (already-saved repetitions are kept)
"""
import sys
import time
import cv2
import mediapipe as mp
import numpy as np
from pathlib import Path

# ---- Settings ----
TARGET_REPS = 200
RECORD_SECONDS = 3.5
REST_SECONDS = 5
SEQ_LEN = 30
OUTPUT_ROOT = Path("dataset/npy_signs")

mp_hands = mp.solutions.hands
mp_drawing = mp.solutions.drawing_utils


def process_frame(hands_detector, frame):
    """Runs MediaPipe once and returns (feature_vector, mediapipe_results)."""
    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    results = hands_detector.process(rgb)
    left, right = [0.0] * 63, [0.0] * 63
    if results.multi_hand_landmarks and results.multi_handedness:
        for hand_landmarks, handedness in zip(
            results.multi_hand_landmarks, results.multi_handedness
        ):
            coords = []
            for lm in hand_landmarks.landmark:
                coords.extend([lm.x, lm.y, lm.z])
            label = handedness.classification[0].label
            if label == "Left":
                left = coords
            else:
                right = coords
    features = np.array(left + right, dtype=np.float32)
    return features, results


def draw_landmarks_on(frame, results):
    """Draws the hand skeleton onto frame IN PLACE. Only for the display copy."""
    if results.multi_hand_landmarks:
        for hand_landmarks in results.multi_hand_landmarks:
            mp_drawing.draw_landmarks(frame, hand_landmarks, mp_hands.HAND_CONNECTIONS)


def resample_sequence(seq: np.ndarray, target_len: int = SEQ_LEN) -> np.ndarray:
    n = seq.shape[0]
    if n == 0:
        return np.zeros((target_len, 126), dtype=np.float32)
    if n == target_len:
        return seq
    indices = np.linspace(0, n - 1, target_len).astype(int)
    return seq[indices]


def draw_overlay(frame, lines, color=(0, 255, 0)):
    y = 30
    for line in lines:
        cv2.putText(frame, line, (10, y), cv2.FONT_HERSHEY_SIMPLEX, 0.7, color, 2)
        y += 32


def wait_with_countdown(cap, hands_detector, seconds, message_prefix):
    """Shows a live camera countdown WITH hand tracking feedback."""
    start = time.time()
    paused = False
    pause_started = None
    while True:
        ret, frame = cap.read()
        if not ret:
            continue

        _, results = process_frame(hands_detector, frame)
        display = frame.copy()
        draw_landmarks_on(display, results)
        hand_status = "HAND DETECTED ✅" if results.multi_hand_landmarks else "NO HAND VISIBLE ⚠️"
        status_color = (0, 255, 0) if results.multi_hand_landmarks else (0, 0, 255)

        remaining = seconds - (time.time() - start)
        if paused:
            remaining = seconds

        draw_overlay(display, [
            f"{message_prefix}",
            hand_status,
            f"Starting in {max(0, remaining):.1f}s..." if not paused else "PAUSED - press p to resume",
            "p: pause/resume   q: quit"
        ], color=status_color)
        cv2.imshow("Auto Capture", display)

        key = cv2.waitKey(1) & 0xFF
        if key == ord('q'):
            return 'quit'
        if key == ord('p'):
            if not paused:
                paused = True
                pause_started = time.time()
            else:
                start += (time.time() - pause_started)
                paused = False

        if not paused and remaining <= 0:
            return 'done'


def record_one_repetition(cap, hands_detector, rep_num, total):
    """Records RECORD_SECONDS of frames WITH live hand-tracking overlay."""
    sequence = []
    start = time.time()
    while time.time() - start < RECORD_SECONDS:
        ret, frame = cap.read()
        if not ret:
            continue

        features, results = process_frame(hands_detector, frame)
        sequence.append(features)

        display = frame.copy()
        draw_landmarks_on(display, results)
        hand_status = "TRACKING ✅" if results.multi_hand_landmarks else "NO HAND ⚠️"
        status_color = (0, 255, 0) if results.multi_hand_landmarks else (0, 0, 255)
        draw_overlay(display, [
            f"Recording rep {rep_num}/{total}",
            hand_status,
            f"{RECORD_SECONDS - (time.time() - start):.1f}s remaining"
        ], color=status_color)
        cv2.imshow("Auto Capture", display)
        cv2.waitKey(1)

    return np.array(sequence, dtype=np.float32)


def main():
    if len(sys.argv) < 2:
        print("Usage: python auto_capture_word.py <word>")
        return
    word = sys.argv[1].strip().lower()

    word_dir = OUTPUT_ROOT / word
    word_dir.mkdir(parents=True, exist_ok=True)

    existing_files = sorted(word_dir.glob("*.npy"))
    start_index = len(existing_files)
    if start_index >= TARGET_REPS:
        print(f"'{word}' already has {start_index} repetitions (target {TARGET_REPS}). Nothing to do.")
        return

    print(f"Word: {word}")
    print(f"Existing repetitions: {start_index}")
    print(f"Will capture up to: {TARGET_REPS - start_index} more")

    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("ERROR: Could not open camera. Try changing cv2.VideoCapture(0) to (1) if you have multiple cameras.")
        return

    hands_detector = mp_hands.Hands(
        static_image_mode=False,
        max_num_hands=2,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5,
    )

    rep_index = start_index
    saved_count = 0
    rejected_count = 0

    while rep_index < TARGET_REPS:
        result = wait_with_countdown(
            cap, hands_detector, REST_SECONDS,
            f"Get ready to sign: {word.upper()}  ({rep_index}/{TARGET_REPS} done)"
        )
        if result == 'quit':
            break

        raw_seq = record_one_repetition(cap, hands_detector, rep_index + 1, TARGET_REPS)

        if raw_seq.shape[0] == 0:
            print("  ⚠️ No frames captured at all — rejected, retrying this repetition...")
            rejected_count += 1
            continue

        # STRICT CHECK: every single frame must have a hand detected.
        # If even ONE frame is missing a hand, reject the entire repetition.
        frame_has_hand = np.any(raw_seq != 0, axis=1)
        bad_frame_count = int((~frame_has_hand).sum())

        if bad_frame_count > 0:
            print(f"  ❌ Rejected: {bad_frame_count}/{raw_seq.shape[0]} frames had no hand visible. Retrying this repetition...")
            rejected_count += 1
            continue

        final_seq = resample_sequence(raw_seq, SEQ_LEN)
        out_path = word_dir / f"{rep_index + 1}.npy"
        np.save(out_path, final_seq)
        print(f"  ✅ Saved {out_path.name} (all {raw_seq.shape[0]} frames valid)")

        rep_index += 1
        saved_count += 1

    cap.release()
    cv2.destroyAllWindows()
    print(f"\nDone. Saved {saved_count} new repetitions for '{word}'.")
    print(f"Rejected {rejected_count} repetitions along the way (hand not visible in every frame).")
    print(f"Total repetitions now: {rep_index}/{TARGET_REPS}")


if __name__ == "__main__":
    main()
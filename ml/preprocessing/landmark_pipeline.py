import cv2
import mediapipe as mp
import numpy as np
import pandas as pd
from pathlib import Path
from tqdm import tqdm
import joblib

class LandmarkExtractor:
    """
    Extracts MediaPipe landmarks for each video.
    Saves a .npy file containing a sequence of landmarks per frame.
    """
    def __init__(self, metadata_path="dataset/metadata/metadata.csv",
                 output_dir="dataset/processed/landmarks"):
        self.metadata = pd.read_csv(metadata_path)
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.mp_hands = mp.solutions.hands
        self.mp_pose = mp.solutions.pose
        self.mp_holistic = mp.solutions.holistic  # optional

    def extract_landmarks_for_video(self, video_path):
        cap = cv2.VideoCapture(str(video_path))
        if not cap.isOpened():
            return None
        landmarks_list = []
        with self.mp_holistic.Holistic(
            static_image_mode=False,
            model_complexity=1,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5
        ) as holistic:
            while cap.isOpened():
                ret, frame = cap.read()
                if not ret:
                    break
                rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                results = holistic.process(rgb)
                # Extract hand landmarks (left and right)
                left_hand = []
                right_hand = []
                if results.left_hand_landmarks:
                    for lm in results.left_hand_landmarks.landmark:
                        left_hand.extend([lm.x, lm.y, lm.z])
                else:
                    left_hand = [0.0] * 21 * 3  # 21 landmarks
                if results.right_hand_landmarks:
                    for lm in results.right_hand_landmarks.landmark:
                        right_hand.extend([lm.x, lm.y, lm.z])
                else:
                    right_hand = [0.0] * 21 * 3
                # Pose landmarks (optional) – we'll use only selected ones
                pose = []
                if results.pose_landmarks:
                    # Use 33 landmarks, but we can reduce to 25 for efficiency
                    for lm in results.pose_landmarks.landmark:
                        pose.extend([lm.x, lm.y, lm.z])
                else:
                    pose = [0.0] * 33 * 3
                frame_landmarks = np.concatenate([left_hand, right_hand, pose])
                landmarks_list.append(frame_landmarks)
            cap.release()
        if len(landmarks_list) == 0:
            return None
        return np.array(landmarks_list, dtype=np.float32)

    def process_all(self):
        for idx, row in tqdm(self.metadata.iterrows(), total=len(self.metadata)):
            video_path = row['video_path']
            video_id = row['video_id']
            out_file = self.output_dir / f"{video_id}.npy"
            if out_file.exists():
                continue
            landmarks_seq = self.extract_landmarks_for_video(video_path)
            if landmarks_seq is not None:
                np.save(out_file, landmarks_seq)
            else:
                print(f"Failed to extract landmarks for {video_id}")

if __name__ == "__main__":
    extractor = LandmarkExtractor()
    extractor.process_all()
    
    
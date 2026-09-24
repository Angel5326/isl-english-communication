import numpy as np
import cv2
import mediapipe as mp
import tempfile
import os
import sys

# Add the project root to path so we can import the template matcher
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))
from ml.inference.template_matcher import TemplateMatcher

class GestureRecognizer:
    def __init__(self):
        print("Loading template matcher...")
        self.matcher = TemplateMatcher()
        self.matcher.load_templates()
        print("GestureRecognizer ready!")
        
        # Initialize MediaPipe Holistic
        self.mp_holistic = mp.solutions.holistic
        self.holistic = self.mp_holistic.Holistic(
            static_image_mode=False,
            model_complexity=1,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5
        )

    def extract_landmarks_from_video(self, video_path):
        """Extract landmarks from a single video file (same as the pipeline)"""
        cap = cv2.VideoCapture(video_path)
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
                
                # Extract left hand (21 landmarks × 3 = 63)
                left_hand = []
                if results.left_hand_landmarks:
                    for lm in results.left_hand_landmarks.landmark:
                        left_hand.extend([lm.x, lm.y, lm.z])
                else:
                    left_hand = [0.0] * 63
                
                # Extract right hand (21 landmarks × 3 = 63)
                right_hand = []
                if results.right_hand_landmarks:
                    for lm in results.right_hand_landmarks.landmark:
                        right_hand.extend([lm.x, lm.y, lm.z])
                else:
                    right_hand = [0.0] * 63
                
                # Extract pose (33 landmarks × 3 = 99)
                pose = []
                if results.pose_landmarks:
                    for lm in results.pose_landmarks.landmark:
                        pose.extend([lm.x, lm.y, lm.z])
                else:
                    pose = [0.0] * 99
                
                # Combine all landmarks (63 + 63 + 99 = 225)
                frame_landmarks = np.concatenate([left_hand, right_hand, pose])
                landmarks_list.append(frame_landmarks)
            
            cap.release()
        
        if len(landmarks_list) == 0:
            return None
        return np.array(landmarks_list, dtype=np.float32)

    def predict(self, video_file):
        """Process uploaded video file and predict the sign"""
        # Save uploaded file to a temporary location
        with tempfile.NamedTemporaryFile(delete=False, suffix='.mp4') as tmp:
            tmp.write(video_file.read())
            tmp_path = tmp.name
        
        try:
            # Extract landmarks
            landmarks = self.extract_landmarks_from_video(tmp_path)
            if landmarks is None:
                return None, 0.0
            
            # Predict using template matcher
            glosses, scores = self.matcher.predict(landmarks, top_k=1)
            return glosses[0], scores[0]
        finally:
            # Clean up temp file
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
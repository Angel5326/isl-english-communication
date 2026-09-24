import numpy as np
import os
import pickle
from sklearn.preprocessing import StandardScaler

class TemplateMatcher:
    def __init__(self, landmarks_dir="dataset/processed/landmarks", metadata_path="dataset/metadata/metadata.csv"):
        self.landmarks_dir = landmarks_dir
        self.metadata = pd.read_csv(metadata_path)
        self.templates = {}  # gloss -> list of landmarks (we only have 1 per gloss)
        self.glosses = []
        self.features = []
        self.scaler = StandardScaler()
        
    def load_templates(self):
        """Load all landmark files and store them as templates."""
        print("Loading templates...")
        for idx, row in self.metadata.iterrows():
            gloss = row['gloss']
            video_id = row['video_id']
            npy_path = os.path.join(self.landmarks_dir, f"{video_id}.npy")
            if os.path.exists(npy_path):
                landmarks = np.load(npy_path)  # (T, 225)
                # Take the mean of all frames to get a single "signature" per video
                # Or we can take the first 30 frames and flatten them
                # For simplicity, we take the mean across frames
                signature = np.mean(landmarks, axis=0)  # (225,)
                self.templates[gloss] = signature
                self.glosses.append(gloss)
                self.features.append(signature)
        
        self.features = np.array(self.features)
        # Normalize features to zero mean and unit variance
        self.features = self.scaler.fit_transform(self.features)
        print(f"Loaded {len(self.templates)} templates.")
        
    def predict(self, query_landmarks, top_k=3):
        """
        query_landmarks: numpy array of shape (T, 225)
        Returns top_k most similar glosses
        """
        # Take mean of query frames
        query_sig = np.mean(query_landmarks, axis=0).reshape(1, -1)
        query_sig = self.scaler.transform(query_sig)
        
        # Compute Euclidean distance to all templates
        distances = np.linalg.norm(self.features - query_sig, axis=1)
        
        # Get top K indices with smallest distance
        top_indices = np.argsort(distances)[:top_k]
        top_glosses = [self.glosses[i] for i in top_indices]
        top_scores = [distances[i] for i in top_indices]
        
        return top_glosses, top_scores

if __name__ == "__main__":
    import pandas as pd
    matcher = TemplateMatcher()
    matcher.load_templates()
    
    # Test with one video from the dataset
    import sys
    test_video_id = matcher.metadata.iloc[0]['video_id']
    test_landmarks = np.load(f"dataset/processed/landmarks/{test_video_id}.npy")
    gloss, score = matcher.predict(test_landmarks, top_k=1)
    print(f"Predicted: {gloss}, Actual: {matcher.metadata.iloc[0]['gloss']}")
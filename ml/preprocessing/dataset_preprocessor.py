import os
import cv2
import pandas as pd
import json
from pathlib import Path
from tqdm import tqdm

class DatasetPreprocessor:
    """
    Generates metadata.csv from raw videos.
    Expects folder structure: raw/<category>/<video_id>.mp4
    Category = gloss label (e.g., GO, SCHOOL)
    """
    def __init__(self, raw_dir="dataset/raw", metadata_dir="dataset/metadata"):
        self.raw_dir = Path(raw_dir)
        self.metadata_dir = Path(metadata_dir)
        self.metadata_dir.mkdir(parents=True, exist_ok=True)

    def generate_metadata(self):
        records = []
        for category_folder in self.raw_dir.iterdir():
            if not category_folder.is_dir():
                continue
            gloss = category_folder.name
            for video_path in category_folder.glob("*.mp4"):
                cap = cv2.VideoCapture(str(video_path))
                if not cap.isOpened():
                    print(f"Corrupted: {video_path}")
                    continue
                fps = cap.get(cv2.CAP_PROP_FPS)
                frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
                width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
                height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
                duration = frame_count / fps if fps > 0 else 0
                cap.release()
                records.append({
                    "video_id": video_path.stem,
                    "video_path": str(video_path),
                    "gloss": gloss,
                    "english_word": gloss,  # assume gloss is English word
                    "category": gloss,
                    "duration": duration,
                    "frame_count": frame_count,
                    "width": width,
                    "height": height,
                    "fps": fps,
                    "split": "unknown"  # will assign later
                })
        df = pd.DataFrame(records)
        # Save metadata
        df.to_csv(self.metadata_dir / "metadata.csv", index=False)
        print(f"Metadata saved with {len(df)} videos.")
        return df

if __name__ == "__main__":
    preprocessor = DatasetPreprocessor()
    preprocessor.generate_metadata()
    
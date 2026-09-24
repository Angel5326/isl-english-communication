import os
import pandas as pd
import cv2
from pathlib import Path

raw_dir = "dataset/raw"
output_csv = "dataset/metadata/metadata.csv"

os.makedirs("dataset/metadata", exist_ok=True)

records = []
for filename in os.listdir(raw_dir):
    if filename.endswith('.mp4'):
        video_path = os.path.join(raw_dir, filename)
        gloss = filename.replace('.mp4', '').lower()
        
        # Read video metadata
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            print(f"Skipping {filename}: cannot open")
            continue
        fps = cap.get(cv2.CAP_PROP_FPS)
        frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        cap.release()
        
        records.append({
            "video_id": gloss,   # since only one video per gloss, use gloss as ID
            "video_path": video_path,
            "gloss": gloss,
            "split": "train",    # all videos go to train (for template matching)
            "fps": fps,
            "frame_count": frame_count,
            "width": width,
            "height": height,
        })

df = pd.DataFrame(records)
df.to_csv(output_csv, index=False)
print(f"✅ Created {output_csv} with {len(df)} videos.")
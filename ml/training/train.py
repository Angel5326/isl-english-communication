import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader, Dataset
import numpy as np
import pandas as pd
from pathlib import Path
from sklearn.preprocessing import LabelEncoder
import json
from model import CNNLSTM

class SignDataset(Dataset):
    def __init__(self, metadata_df, landmarks_dir, seq_len=30, split='train'):
        self.df = metadata_df[metadata_df['split'] == split]
        self.landmarks_dir = Path(landmarks_dir)
        self.seq_len = seq_len
        self.glosses = self.df['gloss'].values
        self.video_ids = self.df['video_id'].values
        # Encode labels
        self.label_encoder = LabelEncoder()
        self.labels = self.label_encoder.fit_transform(self.glosses)

    def __len__(self):
        return len(self.df)

    def __getitem__(self, idx):
        vid = self.video_ids[idx]
        landmarks_path = self.landmarks_dir / f"{vid}.npy"
        seq = np.load(landmarks_path)  # (T, D)
        # Normalise: zero mean, unit variance per feature? We'll do per-frame scaling.
        # Simple: scale to [0,1] using global min/max from training set (do later)
        # For now, just clip to avoid outliers
        seq = np.clip(seq, -1, 1)
        # Pad or truncate to seq_len
        T = seq.shape[0]
        if T >= self.seq_len:
            # Randomly select a window of length seq_len
            start = np.random.randint(0, T - self.seq_len + 1) if T > self.seq_len else 0
            seq = seq[start:start + self.seq_len]
        else:
            pad_len = self.seq_len - T
            pad = np.zeros((pad_len, seq.shape[1]))
            seq = np.vstack([seq, pad])
        # Convert to tensor
        seq = torch.tensor(seq, dtype=torch.float32)
        label = torch.tensor(self.labels[idx], dtype=torch.long)
        return seq, label

def train():
    # Load metadata
    metadata = pd.read_csv("dataset/metadata/metadata.csv")
    # Create datasets
    train_dataset = SignDataset(metadata, "dataset/processed/landmarks", seq_len=30, split='train')
    val_dataset = SignDataset(metadata, "dataset/processed/landmarks", seq_len=30, split='val')
    train_loader = DataLoader(train_dataset, batch_size=32, shuffle=True)
    val_loader = DataLoader(val_dataset, batch_size=32, shuffle=False)

    # Model
    num_classes = len(train_dataset.label_encoder.classes_)
    model = CNNLSTM(input_dim=225, hidden_dim=128, num_layers=2,
                    num_classes=num_classes, dropout=0.3)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model.to(device)
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=0.001)

    # Save label encoder
    with open("ml/models/class_labels.json", "w") as f:
        json.dump(train_dataset.label_encoder.classes_.tolist(), f)

    best_val_acc = 0.0
    for epoch in range(30):
        model.train()
        total_loss = 0
        for seqs, labels in train_loader:
            seqs, labels = seqs.to(device), labels.to(device)
            optimizer.zero_grad()
            outputs = model(seqs)
            loss = criterion(outputs, labels)
            loss.backward()
            optimizer.step()
            total_loss += loss.item()

        # Validation
        model.eval()
        correct = 0
        total = 0
        with torch.no_grad():
            for seqs, labels in val_loader:
                seqs, labels = seqs.to(device), labels.to(device)
                outputs = model(seqs)
                _, predicted = torch.max(outputs, 1)
                total += labels.size(0)
                correct += (predicted == labels).sum().item()
        val_acc = correct / total
        print(f"Epoch {epoch+1}, Loss: {total_loss/len(train_loader):.4f}, Val Acc: {val_acc:.4f}")
        if val_acc > best_val_acc:
            best_val_acc = val_acc
            torch.save(model.state_dict(), "ml/models/best_model.pt")
            print("Saved best model.")

if __name__ == "__main__":
    train()
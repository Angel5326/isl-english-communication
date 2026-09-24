import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader, Dataset
import json
import os
from pathlib import Path
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder

# --- Configuration ---
DATASET_DIR = Path("dataset/npy_signs")
MODEL_DIR = Path("ml/models")
MODEL_DIR.mkdir(parents=True, exist_ok=True)

SEQ_LEN = 30
FEATURE_DIM = 126
HIDDEN_DIM = 64
NUM_LAYERS = 2
BATCH_SIZE = 16
EPOCHS = 50
LEARNING_RATE = 0.001

# --- Dataset Class ---
class SignDataset(Dataset):
    def __init__(self, data, labels, seq_len=SEQ_LEN):
        self.data = data
        self.labels = labels
        self.seq_len = seq_len

    def __len__(self):
        return len(self.data)

    def __getitem__(self, idx):
        seq = self.data[idx]
        # Pad or truncate to seq_len
        if seq.shape[0] >= self.seq_len:
            # Take a random window
            start = np.random.randint(0, seq.shape[0] - self.seq_len + 1)
            seq = seq[start:start + self.seq_len]
        else:
            pad_len = self.seq_len - seq.shape[0]
            pad = np.zeros((pad_len, FEATURE_DIM))
            seq = np.vstack([seq, pad])
        label = self.labels[idx]
        return torch.tensor(seq, dtype=torch.float32), torch.tensor(label, dtype=torch.long)

# --- LSTM Model ---
class SignLSTM(nn.Module):
    def __init__(self, input_dim, hidden_dim, num_layers, num_classes):
        super().__init__()
        self.lstm = nn.LSTM(input_dim, hidden_dim, num_layers, batch_first=True, dropout=0.3)
        self.dropout = nn.Dropout(0.3)
        self.fc = nn.Linear(hidden_dim, num_classes)

    def forward(self, x):
        lstm_out, _ = self.lstm(x)
        last_out = lstm_out[:, -1, :]
        return self.fc(self.dropout(last_out))

# --- Load Data ---
def load_data():
    all_sequences = []
    all_labels = []
    label_encoder = LabelEncoder()

    # Get all gloss folder names
    gloss_folders = [f for f in DATASET_DIR.iterdir() if f.is_dir()]
    gloss_names = [f.name for f in gloss_folders]

    for gloss in gloss_names:
        gloss_dir = DATASET_DIR / gloss
        npy_files = list(gloss_dir.glob("*.npy"))
        for npy_path in npy_files:
            seq = np.load(npy_path)
            if seq.shape[0] > 5:  # Skip very short sequences
                all_sequences.append(seq)
                all_labels.append(gloss)

    # Encode labels to integers
    encoded_labels = label_encoder.fit_transform(all_labels)

    print(f"✅ Loaded {len(all_sequences)} samples from {len(gloss_names)} signs")

    # Split into train, val, test
    X_train, X_temp, y_train, y_temp = train_test_split(
        all_sequences, encoded_labels, test_size=0.3, random_state=42, stratify=encoded_labels
    )
    X_val, X_test, y_val, y_test = train_test_split(
        X_temp, y_temp, test_size=0.5, random_state=42, stratify=y_temp
    )

    print(f"📊 Train: {len(X_train)}, Val: {len(X_val)}, Test: {len(X_test)}")

    return X_train, y_train, X_val, y_val, X_test, y_test, label_encoder

# --- Train ---
def train():
    X_train, y_train, X_val, y_val, X_test, y_test, label_encoder = load_data()

    # Create datasets
    train_dataset = SignDataset(X_train, y_train)
    val_dataset = SignDataset(X_val, y_val)
    test_dataset = SignDataset(X_test, y_test)

    train_loader = DataLoader(train_dataset, batch_size=BATCH_SIZE, shuffle=True)
    val_loader = DataLoader(val_dataset, batch_size=BATCH_SIZE, shuffle=False)
    test_loader = DataLoader(test_dataset, batch_size=BATCH_SIZE, shuffle=False)

    # Model
    num_classes = len(label_encoder.classes_)
    model = SignLSTM(FEATURE_DIM, HIDDEN_DIM, NUM_LAYERS, num_classes)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model.to(device)

    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=LEARNING_RATE)

    # Save label encoder
    with open(MODEL_DIR / "sequence_labels.json", "w") as f:
        json.dump(label_encoder.classes_.tolist(), f)
    print(f"✅ Saved labels: {label_encoder.classes_.tolist()}")

    best_val_acc = 0.0

    for epoch in range(EPOCHS):
        model.train()
        train_loss = 0.0
        for seqs, labels in train_loader:
            seqs, labels = seqs.to(device), labels.to(device)
            optimizer.zero_grad()
            outputs = model(seqs)
            loss = criterion(outputs, labels)
            loss.backward()
            optimizer.step()
            train_loss += loss.item()

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

        if val_acc > best_val_acc:
            best_val_acc = val_acc
            torch.save(model.state_dict(), MODEL_DIR / "sequence_classifier.pt")
            print(f"💾 Saved best model at epoch {epoch+1} (val_acc: {val_acc:.4f})")

        print(f"Epoch {epoch+1}/{EPOCHS}, Loss: {train_loss/len(train_loader):.4f}, Val Acc: {val_acc:.4f}")

    # Test final model
    model.load_state_dict(torch.load(MODEL_DIR / "sequence_classifier.pt", map_location="cpu"))
    model.eval()
    correct = 0
    total = 0
    with torch.no_grad():
        for seqs, labels in test_loader:
            seqs, labels = seqs.to(device), labels.to(device)
            outputs = model(seqs)
            _, predicted = torch.max(outputs, 1)
            total += labels.size(0)
            correct += (predicted == labels).sum().item()

    test_acc = correct / total
    print(f"🧪 Test Accuracy: {test_acc:.4f}")
    print(f"✅ Training complete! Model saved to {MODEL_DIR / 'sequence_classifier.pt'}")

if __name__ == "__main__":
    train()
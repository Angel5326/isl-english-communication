"""
Trains an LSTM classifier on landmark sequences (30 frames x 126 features)
to recognize dynamic (moving) sign words.
"""
import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import classification_report, accuracy_score
from pathlib import Path
import json

DATA_PATH = Path("ml/models/sequence_dataset_normalized.npz")
MODEL_OUTPUT = Path("ml/models/sequence_classifier_normalized.pt")
LABELS_OUTPUT = Path("ml/models/sequence_labels_normalized.json")

SEQ_LEN = 30
FEATURE_DIM = 126
HIDDEN_DIM = 64
NUM_LAYERS = 1
EPOCHS = 40
BATCH_SIZE = 16
LEARNING_RATE = 0.001


class SequenceDataset(Dataset):
    def __init__(self, X, y):
        self.X = torch.tensor(X, dtype=torch.float32)
        self.y = torch.tensor(y, dtype=torch.long)

    def __len__(self):
        return len(self.X)

    def __getitem__(self, idx):
        return self.X[idx], self.y[idx]


class SignLSTM(nn.Module):
    def __init__(self, input_dim, hidden_dim, num_layers, num_classes):
        super().__init__()
        self.lstm = nn.LSTM(
            input_dim, hidden_dim, num_layers,
            batch_first=True, dropout=0.3 if num_layers > 1 else 0
        )
        self.dropout = nn.Dropout(0.3)
        self.fc = nn.Linear(hidden_dim, num_classes)

    def forward(self, x):
        lstm_out, _ = self.lstm(x)
        last_out = lstm_out[:, -1, :]  # take the final timestep's output
        out = self.dropout(last_out)
        return self.fc(out)


def main():
    data = np.load(DATA_PATH)
    X, y = data["X"], data["y"]

    print(f"Total samples: {len(X)}")
    unique, counts = np.unique(y, return_counts=True)
    for word, count in zip(unique, counts):
        print(f"  {word}: {count}")

    label_encoder = LabelEncoder()
    y_encoded = label_encoder.fit_transform(y)
    num_classes = len(label_encoder.classes_)

    X_train, X_test, y_train, y_test = train_test_split(
        X, y_encoded, test_size=0.2, random_state=42, stratify=y_encoded
    )

    train_dataset = SequenceDataset(X_train, y_train)
    test_dataset = SequenceDataset(X_test, y_test)
    train_loader = DataLoader(train_dataset, batch_size=BATCH_SIZE, shuffle=True)
    test_loader = DataLoader(test_dataset, batch_size=BATCH_SIZE, shuffle=False)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = SignLSTM(FEATURE_DIM, HIDDEN_DIM, NUM_LAYERS, num_classes).to(device)
    criterion = nn.CrossEntropyLoss()
    optimizer = torch.optim.Adam(model.parameters(), lr=LEARNING_RATE)

    best_test_acc = 0.0

    for epoch in range(EPOCHS):
        model.train()
        total_loss = 0
        for sequences, labels in train_loader:
            sequences, labels = sequences.to(device), labels.to(device)
            optimizer.zero_grad()
            outputs = model(sequences)
            loss = criterion(outputs, labels)
            loss.backward()
            optimizer.step()
            total_loss += loss.item()

        model.eval()
        correct = 0
        total = 0
        with torch.no_grad():
            for sequences, labels in test_loader:
                sequences, labels = sequences.to(device), labels.to(device)
                outputs = model(sequences)
                _, predicted = torch.max(outputs, 1)
                total += labels.size(0)
                correct += (predicted == labels).sum().item()
        test_acc = correct / total

        print(f"Epoch {epoch+1}/{EPOCHS} | Loss: {total_loss/len(train_loader):.4f} | Test Acc: {test_acc:.2%}")

        if test_acc > best_test_acc:
            best_test_acc = test_acc
            MODEL_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
            torch.save(model.state_dict(), MODEL_OUTPUT)

    # Final detailed report using the best saved model
    model.load_state_dict(torch.load(MODEL_OUTPUT))
    model.eval()
    all_preds, all_true = [], []
    with torch.no_grad():
        for sequences, labels in test_loader:
            sequences = sequences.to(device)
            outputs = model(sequences)
            _, predicted = torch.max(outputs, 1)
            all_preds.extend(predicted.cpu().numpy())
            all_true.extend(labels.numpy())

    print(f"\nBest test accuracy: {best_test_acc:.2%}")
    print("\nClassification report:")
    print(classification_report(all_true, all_preds, target_names=label_encoder.classes_, zero_division=0))

    with open(LABELS_OUTPUT, "w") as f:
        json.dump(label_encoder.classes_.tolist(), f)
    print(f"\nSaved model to {MODEL_OUTPUT}")
    print(f"Saved labels to {LABELS_OUTPUT}")


if __name__ == "__main__":
    main()
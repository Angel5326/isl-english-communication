import torch
import numpy as np
import json
from ml.training.model import CNNLSTM

class SignRecognizer:
    def __init__(self, model_path="ml/models/best_model.pt",
                 labels_path="ml/models/class_labels.json",
                 seq_len=30, input_dim=225):
        self.seq_len = seq_len
        with open(labels_path, 'r') as f:
            self.labels = json.load(f)
        self.num_classes = len(self.labels)
        self.model = CNNLSTM(input_dim=input_dim, hidden_dim=128,
                             num_layers=2, num_classes=self.num_classes)
        self.model.load_state_dict(torch.load(model_path, map_location='cpu'))
        self.model.eval()

    def predict(self, landmarks_seq):
        # landmarks_seq: numpy array (T, D)
        # Pad/truncate to seq_len
        T = landmarks_seq.shape[0]
        if T >= self.seq_len:
            # Take first seq_len frames (or we could take last)
            seq = landmarks_seq[:self.seq_len]
        else:
            pad_len = self.seq_len - T
            pad = np.zeros((pad_len, landmarks_seq.shape[1]))
            seq = np.vstack([landmarks_seq, pad])
        seq = torch.tensor(seq, dtype=torch.float32).unsqueeze(0)  # (1, seq_len, D)
        with torch.no_grad():
            logits = self.model(seq)
            probs = torch.softmax(logits, dim=1)
            pred_idx = torch.argmax(probs, dim=1).item()
            confidence = probs[0, pred_idx].item()
        return self.labels[pred_idx], confidence
    
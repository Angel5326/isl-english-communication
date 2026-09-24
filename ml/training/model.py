import torch
import torch.nn as nn

class CNNLSTM(nn.Module):
    """
    CNN + LSTM for sign language recognition from landmark sequences.
    Input: (batch, seq_len, num_landmarks*3)
    """
    def __init__(self, input_dim=225, hidden_dim=128, num_layers=2,
                 num_classes=100, dropout=0.3):
        super(CNNLSTM, self).__init__()
        # 1D CNN to process each frame's landmarks independently
        self.cnn = nn.Sequential(
            nn.Conv1d(in_channels=1, out_channels=32, kernel_size=3, padding=1),
            nn.ReLU(),
            nn.MaxPool1d(2),
            nn.Conv1d(32, 64, kernel_size=3, padding=1),
            nn.ReLU(),
            nn.MaxPool1d(2),
            nn.Flatten()
        )
        # Compute CNN output size (depends on input_dim)
        with torch.no_grad():
            dummy = torch.zeros(1, 1, input_dim)
            cnn_out = self.cnn(dummy)
            cnn_features = cnn_out.shape[1]

        self.lstm = nn.LSTM(cnn_features, hidden_dim, num_layers,
                            batch_first=True, dropout=dropout)
        self.classifier = nn.Linear(hidden_dim, num_classes)

    def forward(self, x):
        # x: (batch, seq_len, input_dim)
        batch_size, seq_len, _ = x.shape
        # Reshape for CNN: (batch*seq_len, 1, input_dim)
        x = x.view(batch_size * seq_len, 1, -1)
        cnn_out = self.cnn(x)  # (batch*seq_len, features)
        cnn_out = cnn_out.view(batch_size, seq_len, -1)
        # LSTM
        lstm_out, _ = self.lstm(cnn_out)  # (batch, seq_len, hidden_dim)
        # Use last output
        last_out = lstm_out[:, -1, :]
        logits = self.classifier(last_out)
        return logits
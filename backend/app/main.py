import sys
import os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, File, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uvicorn
import json
import random
import cv2
import numpy as np
import mediapipe as mp
import torch
import torch.nn as nn
import tempfile
from pathlib import Path
from typing import Dict

from nlp.gloss_to_english import GlossToEnglish
from nlp.english_to_gloss import EnglishToGloss

app = FastAPI(title="ISL-English Real-Time Server")

# --- FIXED CORS SETTINGS ---
# We must set allow_credentials=False when using allow_origins=["*"]
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False, 
    allow_methods=["*"],
    allow_headers=["*"],
)

class TranslateRequest(BaseModel):
    gloss: str

class EnglishRequest(BaseModel):
    text: str

class SessionCreate(BaseModel):
    user_id: str

class SessionJoin(BaseModel):
    session_id: str
    user_id: str

gloss_to_english = GlossToEnglish()
english_to_gloss = EnglishToGloss()

mp_hands = mp.solutions.hands

# --- Reusable hand detector (created ONCE at startup, not per-request) ---
hands_detector = mp_hands.Hands(
    static_image_mode=False,
    max_num_hands=2,
    min_detection_confidence=0.5,
    min_tracking_confidence=0.5,
)

# --- Using the NORMALIZED model ---
SEQ_MODEL_PATH = Path("ml/models/sequence_classifier_normalized.pt")
SEQ_LABELS_PATH = Path("ml/models/sequence_labels_normalized.json")
SEQ_LEN = 30
FEATURE_DIM = 126
HIDDEN_DIM = 64

class SignLSTM(nn.Module):
    def __init__(self, input_dim, hidden_dim, num_layers, num_classes):
        super().__init__()
        self.lstm = nn.LSTM(input_dim, hidden_dim, num_layers, batch_first=True)
        self.dropout = nn.Dropout(0.3)
        self.fc = nn.Linear(hidden_dim, num_classes)

    def forward(self, x):
        lstm_out, _ = self.lstm(x)
        last_out = lstm_out[:, -1, :]
        return self.fc(self.dropout(last_out))

sequence_model = None
sequence_labels = None
if SEQ_MODEL_PATH.exists() and SEQ_LABELS_PATH.exists():
    with open(SEQ_LABELS_PATH) as f:
        sequence_labels = json.load(f)
    sequence_model = SignLSTM(FEATURE_DIM, HIDDEN_DIM, 1, len(sequence_labels))
    sequence_model.load_state_dict(torch.load(SEQ_MODEL_PATH, map_location="cpu"))
    sequence_model.eval()
    print(f"✅ Loaded NORMALIZED sequence classifier. Words: {sequence_labels}")
    print(f"   SEQ_LEN={SEQ_LEN}, LSTM layers={sequence_model.lstm.num_layers}")
else:
    print("⚠️ No normalized sequence model found. Run normalize_dataset.py + retrain first.")

def normalize_frame(frame_features: np.ndarray) -> np.ndarray:
    """Same normalization used during training — must match exactly."""
    left = frame_features[:63].reshape(21, 3)
    right = frame_features[63:].reshape(21, 3)

    def normalize_hand(hand: np.ndarray) -> np.ndarray:
        if np.all(hand == 0):
            return hand.flatten()
        wrist = hand[0].copy()
        centered = hand - wrist
        ref_dist = np.linalg.norm(centered[9])
        if ref_dist < 1e-6:
            ref_dist = 1.0
        return (centered / ref_dist).flatten()

    return np.concatenate([normalize_hand(left), normalize_hand(right)])

def extract_landmarks_from_video(video_path: str) -> np.ndarray:
    cap = cv2.VideoCapture(video_path)
    frame_count = 0
    processed_count = 0
    sequence = []

    while True:
        ret, frame = cap.read()
        if not ret:
            break
        frame_count += 1

        if frame_count % 2 != 0:
            continue

        processed_count += 1
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        results = hands_detector.process(rgb)
        left, right = [0.0] * 63, [0.0] * 63
        if results.multi_hand_landmarks and results.multi_handedness:
            for hand_landmarks, handedness in zip(
                results.multi_hand_landmarks, results.multi_handedness
            ):
                coords = []
                for lm in hand_landmarks.landmark:
                    coords.extend([lm.x, lm.y, lm.z])
                label = handedness.classification[0].label
                if label == "Left":
                    left = coords
                else:
                    right = coords
        raw_frame = np.array(left + right, dtype=np.float32)
        sequence.append(normalize_frame(raw_frame))

    cap.release()
    print(f"[extract_landmarks] read {frame_count} raw frames, processed {processed_count}")
    return np.array(sequence, dtype=np.float32)

def resample_sequence(seq: np.ndarray, target_len: int = SEQ_LEN) -> np.ndarray:
    n = seq.shape[0]
    if n == 0:
        return np.zeros((target_len, FEATURE_DIM), dtype=np.float32)
    if n == target_len:
        return seq
    indices = np.linspace(0, n - 1, target_len).astype(int)
    return seq[indices]

class SessionManager:
    def __init__(self):
        self.sessions: Dict[str, Dict] = {}
        self.connections: Dict[str, Dict[str, WebSocket]] = {}

    def create_session(self, session_id: str, user_id: str):
        self.sessions[session_id] = {"users": {user_id}, "messages": []}
        self.connections[session_id] = {}

    def add_user(self, session_id: str, user_id: str):
        if session_id in self.sessions:
            self.sessions[session_id]["users"].add(user_id)

    def add_connection(self, session_id: str, user_id: str, ws: WebSocket):
        if session_id not in self.connections:
            self.connections[session_id] = {}
        self.connections[session_id][user_id] = ws

    def remove_connection(self, session_id: str, user_id: str):
        if session_id in self.connections:
            self.connections[session_id].pop(user_id, None)

    async def broadcast(self, session_id: str, message: dict, exclude_user: str = None):
        if session_id in self.connections:
            for uid, ws in self.connections[session_id].items():
                if uid != exclude_user:
                    try:
                        await ws.send_text(json.dumps(message))
                    except Exception:
                        pass

manager = SessionManager()

@app.post("/api/session/create")
async def create_session(data: SessionCreate):
    session_id = str(random.randint(1000, 9999))
    manager.create_session(session_id, data.user_id)
    return {"session_id": session_id}

@app.post("/api/session/join")
async def join_session(data: SessionJoin):
    if data.session_id not in manager.sessions:
        return {"error": "Session not found"}
    manager.add_user(data.session_id, data.user_id)
    return {"status": "joined"}

@app.get("/api/session/{session_id}/status")
async def session_status(session_id: str):
    if session_id not in manager.sessions:
        return {"error": "Session not found"}
    return {
        "user_count": len(manager.connections.get(session_id, {})),
        "users": list(manager.sessions[session_id]["users"])
    }

@app.post("/api/predict-sign")
async def predict_sign(video: UploadFile = File(...)):
    if sequence_model is None:
        return {"gloss": "Model not trained yet", "confidence": 0.0, "reason": "no_model"}

    contents = await video.read()
    print(f"[predict-sign] received {len(contents)} bytes")

    if len(contents) < 5000:
        return {"gloss": "Video too small", "confidence": 0.0, "reason": "tiny_upload"}

    with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as tmp:
        tmp.write(contents)
        tmp_path = tmp.name

    try:
        raw_seq = extract_landmarks_from_video(tmp_path)
    finally:
        os.remove(tmp_path)

    print(f"[predict-sign] extracted sequence shape: {raw_seq.shape}")

    if raw_seq.shape[0] == 0:
        return {"gloss": "No sign detected", "confidence": 0.0, "reason": "decode_failed"}

    non_zero_frames = np.any(raw_seq != 0, axis=1).sum()
    hand_ratio = non_zero_frames / raw_seq.shape[0]
    print(f"[predict-sign] hand visible in {non_zero_frames}/{raw_seq.shape[0]} frames ({hand_ratio:.0%})")

    if hand_ratio < 0.2:
        return {"gloss": "No hand visible", "confidence": 0.0, "reason": "no_hand"}

    seq = resample_sequence(raw_seq, SEQ_LEN)
    tensor = torch.tensor(seq, dtype=torch.float32).unsqueeze(0)

    with torch.no_grad():
        logits = sequence_model(tensor)
        probs = torch.softmax(logits, dim=1)[0]
        pred_idx = int(torch.argmax(probs))
        confidence = float(probs[pred_idx])

    print(f"[predict-sign] top prediction: {sequence_labels[pred_idx]} ({confidence:.2f})")

    if confidence < 0.4:
        return {"gloss": "Low confidence", "confidence": round(confidence, 2), "reason": "low_confidence"}

    return {"gloss": sequence_labels[pred_idx].upper(), "confidence": round(confidence, 2), "reason": "ok"}

@app.post("/api/translate-gloss")
async def translate_gloss(request: TranslateRequest):
    english = gloss_to_english.translate(request.gloss)
    return {"english": english}

@app.post("/api/english-to-isl")
async def english_to_isl(request: EnglishRequest):
    gloss = english_to_gloss.translate(request.text)
    words = gloss.split()
    videos = [f"{w}.mp4" for w in words]
    return {"gloss": gloss, "videos": videos}

@app.websocket("/ws/{session_id}/{user_id}")
async def websocket_endpoint(websocket: WebSocket, session_id: str, user_id: str):
    await websocket.accept()
    manager.add_connection(session_id, user_id, websocket)
    print(f"✅ User {user_id} joined session {session_id}")

    await manager.broadcast(session_id, {
        "type": "system",
        "text": f"User {user_id} joined the chat.",
        "sender": "system"
    }, exclude_user=user_id)

    try:
        while True:
            data = await websocket.receive_text()
            message = json.loads(data)
            message["sender"] = user_id
            message["type"] = "chat"
            await manager.broadcast(session_id, message, exclude_user=user_id)
    except WebSocketDisconnect:
        manager.remove_connection(session_id, user_id)
        await manager.broadcast(session_id, {
            "type": "system",
            "text": f"User {user_id} left the chat.",
            "sender": "system"
        }, exclude_user=user_id)
        print(f"❌ User {user_id} disconnected")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
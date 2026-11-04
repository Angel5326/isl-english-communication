import sys
import os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, File, UploadFile, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from pydantic import BaseModel, EmailStr
from sqlalchemy import create_engine, Column, Integer, String, Boolean, ForeignKey
from sqlalchemy.orm import declarative_base, sessionmaker, Session
from passlib.context import CryptContext
from jose import JWTError, jwt
from datetime import datetime, timedelta
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
from groq import Groq

# --- DATABASE SETUP ---
SQLALCHEMY_DATABASE_URL = os.environ.get("DATABASE_URL", "sqlite:///./handytalk.db")
engine = create_engine(SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False} if "sqlite" in SQLALCHEMY_DATABASE_URL else {})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String)
    email = Column(String, unique=True, index=True)
    hashed_password = Column(String)
    is_verified = Column(Boolean, default=False)
    otp = Column(String, nullable=True)

class Contact(Base):
    __tablename__ = "contacts"
    id = Column(Integer, primary_key=True, index=True)
    owner_email = Column(String, index=True)
    contact_name = Column(String)
    contact_email = Column(String)

Base.metadata.create_all(bind=engine)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# --- AUTH SETUP ---
SECRET_KEY = "handy_talk_super_secret_key"
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7 # 7 days

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="api/login")

app = FastAPI(title="ISL-English Real-Time Server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False, 
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- PYDANTIC MODELS ---
class UserRegister(BaseModel):
    name: str
    email: EmailStr
    password: str

class OTPVerify(BaseModel):
    email: EmailStr
    otp: str

class ContactAdd(BaseModel):
    contact_name: str
    contact_email: EmailStr

class TranslateRequest(BaseModel):
    gloss: str

class EnglishRequest(BaseModel):
    text: str

# --- AUTH UTILS ---
def create_access_token(data: dict):
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    credentials_exception = HTTPException(status_code=401, detail="Could not validate credentials")
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        email: str = payload.get("sub")
        if email is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception
    user = db.query(User).filter(User.email == email).first()
    if user is None:
        raise credentials_exception
    return user

# --- AUTH ENDPOINTS ---
@app.post("/api/register")
def register(user: UserRegister, db: Session = Depends(get_db)):
    db_user = db.query(User).filter(User.email == user.email).first()
    
    if db_user:
    if db_user.is_verified:
        raise HTTPException(status_code=400, detail="Email already registered. Please login.")
    else:
        # Update password and generate NEW OTP
        db_user.hashed_password = pwd_context.hash(user.password)
        db_user.name = user.name
        otp = str(random.randint(100000, 999999))
        db_user.otp = otp
        db.commit()
        print(f"🔐 NEW OTP for {user.email} is: {otp}")
        return {"message": "New OTP generated."}
    
    # If completely new user
    hashed_pw = pwd_context.hash(user.password)
    otp = str(random.randint(100000, 999999))
    
    new_user = User(name=user.name, email=user.email, hashed_password=hashed_pw, otp=otp)
    db.add(new_user)
    db.commit()
    
    print(f"🔐 OTP for {user.email} is: {otp}")
    return {"message": "User registered. Please check Render logs for OTP."}}

@app.post("/api/login")
def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == form_data.username).first()
    if not user or not pwd_context.verify(form_data.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Incorrect email or password")
    if not user.is_verified:
        raise HTTPException(status_code=403, detail="Please verify your email first")
    
    access_token = create_access_token(data={"sub": user.email})
    return {"access_token": access_token, "token_type": "bearer", "name": user.name, "email": user.email}

# --- CONTACTS ENDPOINTS ---
@app.post("/api/contacts/add")
def add_contact(contact: ContactAdd, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    # Check if the person you are adding actually exists and is verified
    target_user = db.query(User).filter(User.email == contact.contact_email, User.is_verified == True).first()
    if not target_user:
        raise HTTPException(status_code=404, detail="User not found or not verified")
    
    new_contact = Contact(owner_email=current_user.email, contact_name=target_user.name, contact_email=target_user.email)
    db.add(new_contact)
    db.commit()
    return {"message": "Contact added successfully"}

@app.get("/api/contacts")
def get_contacts(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    contacts = db.query(Contact).filter(Contact.owner_email == current_user.email).all()
    return [{"name": c.contact_name, "email": c.contact_email} for c in contacts]


# ==========================================
# YOUR EXISTING ISL / LSTM / WEBSOCKET LOGIC
# ==========================================

gloss_to_english = GlossToEnglish()
groq_client = Groq(api_key=os.environ.get("GROQ_API_KEY"))
english_to_gloss = EnglishToGloss()
mp_hands = mp.solutions.hands

hands_detector = mp_hands.Hands(static_image_mode=False, max_num_hands=2, model_complexity=0, min_detection_confidence=0.5, min_tracking_confidence=0.5)

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
        return self.fc(self.dropout(lstm_out[:, -1, :]))

sequence_model = None
sequence_labels = None
if SEQ_MODEL_PATH.exists() and SEQ_LABELS_PATH.exists():
    with open(SEQ_LABELS_PATH) as f:
        sequence_labels = json.load(f)
    sequence_model = SignLSTM(FEATURE_DIM, HIDDEN_DIM, 1, len(sequence_labels))
    sequence_model.load_state_dict(torch.load(SEQ_MODEL_PATH, map_location="cpu"))
    sequence_model.eval()

def normalize_frame(frame_features: np.ndarray) -> np.ndarray:
    left = frame_features[:63].reshape(21, 3)
    right = frame_features[63:].reshape(21, 3)
    def normalize_hand(hand: np.ndarray) -> np.ndarray:
        if np.all(hand == 0): return hand.flatten()
        wrist = hand[0].copy()
        centered = hand - wrist
        ref_dist = np.linalg.norm(centered[9])
        if ref_dist < 1e-6: ref_dist = 1.0
        return (centered / ref_dist).flatten()
    return np.concatenate([normalize_hand(left), normalize_hand(right)])

def extract_landmarks_from_video(video_path: str) -> np.ndarray:
    cap = cv2.VideoCapture(video_path)
    frame_count, processed_count = 0, 0
    sequence = []
    while True:
        ret, frame = cap.read()
        if not ret: break
        frame_count += 1
        if frame_count % 3 != 0: continue
        processed_count += 1
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        results = hands_detector.process(rgb)
        left, right = [0.0] * 63, [0.0] * 63
        if results.multi_hand_landmarks and results.multi_handedness:
            for hand_landmarks, handedness in zip(results.multi_hand_landmarks, results.multi_handedness):
                coords = []
                for lm in hand_landmarks.landmark: coords.extend([lm.x, lm.y, lm.z])
                if handedness.classification[0].label == "Left": left = coords
                else: right = coords
        sequence.append(normalize_frame(np.array(left + right, dtype=np.float32)))
    cap.release()
    return np.array(sequence, dtype=np.float32)

def resample_sequence(seq: np.ndarray, target_len: int = SEQ_LEN) -> np.ndarray:
    n = seq.shape[0]
    if n == 0: return np.zeros((target_len, FEATURE_DIM), dtype=np.float32)
    if n == target_len: return seq
    indices = np.linspace(0, n - 1, target_len).astype(int)
    return seq[indices]

class SessionManager:
    def __init__(self):
        self.sessions: Dict[str, Dict] = {}
        self.connections: Dict[str, Dict[str, WebSocket]] = {}
    def create_session(self, session_id: str, user_id: str):
        self.sessions[session_id] = {"users": {user_id}}
        self.connections[session_id] = {}
    def add_user(self, session_id: str, user_id: str):
        if session_id in self.sessions: self.sessions[session_id]["users"].add(user_id)
    def add_connection(self, session_id: str, user_id: str, ws: WebSocket):
        if session_id not in self.connections: self.connections[session_id] = {}
        self.connections[session_id][user_id] = ws
    def remove_connection(self, session_id: str, user_id: str):
        if session_id in self.connections: self.connections[session_id].pop(user_id, None)
    async def broadcast(self, session_id: str, message: dict, exclude_user: str = None):
        if session_id in self.connections:
            for uid, ws in self.connections[session_id].items():
                if uid != exclude_user:
                    try: await ws.send_text(json.dumps(message))
                    except Exception: pass

manager = SessionManager()

class SessionCreate(BaseModel):
    user_id: str
class SessionJoin(BaseModel):
    session_id: str
    user_id: str

@app.post("/api/session/invite")
async def invite_session(contact_email: str, current_user: User = Depends(get_current_user)):
    session_id = str(random.randint(1000, 9999))
    manager.create_session(session_id, current_user.email)
    # In a real app, you would send a push notification/email here.
    # For the app, we return the code so the UI can show it.
    return {"session_id": session_id, "message": f"Invite sent to {contact_email}"}

@app.post("/api/session/join")
async def join_session(data: SessionJoin):
    if data.session_id not in manager.sessions: return {"error": "Session not found"}
    manager.add_user(data.session_id, data.user_id)
    return {"status": "joined"}

@app.post("/api/predict-sign")
async def predict_sign(video: UploadFile = File(...)):
    if sequence_model is None: return {"gloss": "No model", "confidence": 0.0}
    contents = await video.read()
    if len(contents) < 5000: return {"gloss": "Video too small", "confidence": 0.0}
    with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as tmp:
        tmp.write(contents)
        tmp_path = tmp.name
    try: raw_seq = extract_landmarks_from_video(tmp_path)
    finally: os.remove(tmp_path)
    if raw_seq.shape[0] == 0: return {"gloss": "No sign", "confidence": 0.0}
    non_zero = np.any(raw_seq != 0, axis=1).sum()
    if non_zero / raw_seq.shape[0] < 0.2: return {"gloss": "No hand", "confidence": 0.0}
    
    seq = resample_sequence(raw_seq, SEQ_LEN)
    tensor = torch.tensor(seq, dtype=torch.float32).unsqueeze(0)
    with torch.no_grad():
        probs = torch.softmax(sequence_model(tensor), dim=1)[0]
        pred_idx = int(torch.argmax(probs))
        confidence = float(probs[pred_idx])
    if confidence < 0.4: return {"gloss": "Low confidence", "confidence": round(confidence, 2)}
    return {"gloss": sequence_labels[pred_idx].upper(), "confidence": round(confidence, 2)}

@app.post("/api/translate-gloss")
async def translate_gloss(request: TranslateRequest):
    gloss_text = request.gloss.strip().upper()
    if not gloss_text: return {"english": ""}
    if " " not in gloss_text: return {"english": gloss_text.capitalize()}
    try:
        chat = groq_client.chat.completions.create(
            messages=[{"role": "system", "content": "Convert ISL Gloss to grammatically correct English."}, {"role": "user", "content": gloss_text}],
            model="llama3-8b-8192", temperature=0.3,
        )
        return {"english": chat.choices[0].message.content.strip()}
    except Exception:
        return {"english": gloss_to_english.translate(request.gloss)}

@app.post("/api/english-to-isl")
async def english_to_isl(request: EnglishRequest):
    gloss = english_to_gloss.translate(request.text)
    return {"gloss": gloss, "videos": [f"{w}.mp4" for w in gloss.split()]}

@app.websocket("/ws/{session_id}/{user_id}")
async def websocket_endpoint(websocket: WebSocket, session_id: str, user_id: str):
    await websocket.accept()
    manager.add_connection(session_id, user_id, websocket)
    await manager.broadcast(session_id, {"type": "system", "text": f"{user_id} joined.", "sender": "system"}, exclude_user=user_id)
    try:
        while True:
            data = await websocket.receive_text()
            message = json.loads(data)
            message["sender"] = user_id
            message["type"] = "chat"
            await manager.broadcast(session_id, message, exclude_user=user_id)
    except WebSocketDisconnect:
        manager.remove_connection(session_id, user_id)
        await manager.broadcast(session_id, {"type": "system", "text": f"{user_id} left.", "sender": "system"}, exclude_user=user_id)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
<div align="center">

# 🤟 Handy Talk
### Bridging Hearts Across Words and Signs

**A Cloud-Native, Real-Time Bidirectional Indian Sign Language (ISL) Translation System**

[![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-005571?style=for-the-badge&logo=fastapi)](https://fastapi.tiangolo.com)
[![PyTorch](https://img.shields.io/badge/PyTorch-%23EE4C2C.svg?style=for-the-badge&logo=PyTorch&logoColor=white)](https://pytorch.org)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-316192?style=for-the-badge&logo=postgresql&logoColor=white)](https://www.postgresql.org)
[![Render](https://img.shields.io/badge/Render-%46E3B7.svg?style=for-the-badge&logo=render&logoColor=white)](https://render.com)

> *"Technology for a More Inclusive World."*

</div>

---

## 📖 The Vision: Why Handy Talk Exists

Effective communication is a fundamental human right, yet the Deaf and Hard-of-Hearing community faces severe daily barriers. With a critical shortage of certified Indian Sign Language (ISL) interpreters, Deaf individuals struggle to communicate in essential scenarios—like medical emergencies, classrooms, and everyday transactions. 

Existing digital solutions are often restricted to local networks, require heavy software downloads, or lack bidirectional translation. **Handy Talk** solves this by providing a **zero-install, cloud-native web application** that acts as a real-time, bidirectional bridge between the Deaf and hearing worlds, regardless of physical distance or network.

---

## 🚀 Key Innovations & Features

*   **🔄 True Bidirectional Communication:** Seamlessly translates **Sign Language to English Text** and **English Text to Sign Language Videos** in a single session.
*   **🌐 Cross-Network Cloud Architecture:** Leverages Secure WebSockets (`WSS`) hosted on the cloud. A user on 5G mobile data can communicate with a user on a completely different Wi-Fi network in real-time.
*   **📸 Camera-Invariant Normalization:** A custom spatial algorithm scales 3D hand landmarks relative to the wrist and middle-finger base. This ensures the AI recognizes the *shape* of the sign, regardless of the user's distance from the camera.
*   **🧠 LLM-Powered Grammar Correction:** Raw ISL gloss (e.g., "ME GO MARKET") is passed through a Llama-3 LLM (via Groq) to generate grammatically correct natural English ("I am going to the market").
*   **🎯 Advanced Motion Gating & Smoothing:** Filters out static hand movements and uses temporal smoothing to prevent false positives, ensuring only deliberate signs are translated.
*   **🔐 Enterprise-Grade Security:** Full user authentication with email OTP verification, JWT-based session management, and secure PostgreSQL data storage.

---

## 🏗️ System Architecture

Handy Talk is built on a modern, scalable architecture. The heavy AI computations are offloaded to the cloud, ensuring the client device only needs a lightweight web browser.

```mermaid
graph TD
    subgraph Cloud ["☁️ Cloud Infrastructure (Render)"]
        DB[(PostgreSQL Database)]
        API[FastAPI Backend]
        Auth[Auth & JWT]
        Session[Session Manager]
        MP[MediaPipe Extraction]
        LSTM[PyTorch LSTM Model]
        LLM[Groq LLM Grammar]
        NLP[NLP Gloss Translator]

        DB <--> API
        API --- Auth
        API --- Session
        API --- MP
        API --- LSTM
        API --- LLM
        API --- NLP
    end

    subgraph ClientA ["📱 Device A (Deaf User)"]
        Cam[Camera Capture]
        Play[ISL Video Playback]
        FlutterA[Flutter Web App]
        Cam --- FlutterA
        Play --- FlutterA
    end

    subgraph ClientB ["💻 Device B (Hearing User)"]
        Type[Text Input]
        Read[Translated Text Display]
        FlutterB[Flutter Web App]
        Type --- FlutterB
        Read --- FlutterB
    end

    FlutterA <-->|WSS / HTTPS| API
    FlutterB <-->|WSS / HTTPS| API
⚙️ The Pipeline: How It Works
1️⃣ Sign to Text (ISL ➡️ English)
Capture: The frontend records a 1.5-second video of the user signing.

Spatial Extraction: The video is sent to the cloud. MediaPipe extracts 21 3D hand landmarks (126 features per frame).

Normalization & Gating: Custom algorithm centers the hands, and motion variance is checked to ignore static hands.

Temporal Classification: A PyTorch LSTM processes a sequence of 30 frames to predict the dynamic sign motion.

Grammar Correction: The predicted words (Gloss) are sent to the Groq LLM (Llama-3-8B) to form a grammatically perfect English sentence.

Delivery: The text is instantly broadcasted to the partner's device via WebSockets.

2️⃣ Text to Sign (English ➡️ ISL)
Input: The hearing user types a message (e.g., "I need a doctor").

NLP Processing: A custom NLP module converts English grammar into ISL Gloss format (e.g., "DOCTOR NEED ME").

Video Mapping: The system maps the gloss to pre-recorded ISL video assets.

Delivery: The video sequence is streamed to the Deaf user's device and loops until a new message arrives.

🛠️ Technology Stack
Domain	Technologies Used
Frontend	Flutter (Dart), WebSockets, Shared Preferences (JWT Storage)
Backend Framework	Python 3.11, FastAPI, Uvicorn
Machine Learning	PyTorch (LSTM Sequence Classifier), MediaPipe, OpenCV, NumPy
NLP & LLM	Groq API (Llama-3), Custom Gloss-to-English Algorithms
Database & Auth	PostgreSQL, SQLAlchemy (ORM), Passlib (Bcrypt), JWT (OAuth2)
DevOps & Cloud	Docker (Containerization), Render (Web Service & Static Site)
🚦 Getting Started (Local Development)
Prerequisites
Python 3.11+

Flutter SDK

PostgreSQL (or use local SQLite fallback)

1. Backend Setup
bash
# Clone the repository
git clone https://github.com/Angel5326/isl-english-communication.git
cd isl-english-communication

# Create and activate virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r backend/requirements.txt

# Setup Environment Variables (.env file)
# DATABASE_URL="postgresql://user:pass@localhost:5432/handytalk"
# GROQ_API_KEY="your_groq_api_key"

# Run the FastAPI server
uvicorn backend.app.main:app --host 0.0.0.0 --port 8000 --reload
The backend will be available at http://localhost:8000

2. Frontend Setup
bash
cd new_flutter_app

# Get dependencies
flutter pub get

# Run the web app (Ensure backend URL is set to localhost in code)
flutter run -d chrome
🛡️ Deployment Architecture
The project is fully containerized and deployed on Render:

Backend: Deployed as a Docker Web Service (handles AI inference, WebSockets, and Auth).

Frontend: Deployed as a Static Site (Flutter Web Build) served via a global CDN.

Database: Managed PostgreSQL instance.

Keep-Alive: Maintained via UptimeRobot pinging the /docs endpoint to prevent Render's free-tier from sleeping.

🔮 Future Scope
On-Device Inference: Converting the PyTorch LSTM to TensorFlow Lite to enable offline processing directly on mobile devices.

Expanded Vocabulary: Scaling the dataset from 40 foundational words to 1000+ ISL signs.

WebRTC Video Calling: Integrating peer-to-peer video calling alongside sign translation.

Idle Class Detection: Training the model on a "No Sign" class to further reduce false positives.

👥 Team Sign Nexus
Abi Angelin A - AI/ML & Backend Architecture

Aslim Ahamed A - Frontend & UI/UX Design

Mohanapriya S - Data Processing & Testing

Vishal G - Cloud Deployment & Documentation

Guided by: Balakrishnan G (Professor) & Jenifer J (Assistant Professor)
Department of Computer Science & Engineering, Indra Ganesan College of Engineering.

<div align="center"> <b>Built with ❤️ for a more inclusive world.</b> </div>
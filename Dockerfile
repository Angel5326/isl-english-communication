# Use Python 3.11
FROM python:3.11-slim

# Install Linux system dependencies required for MediaPipe/OpenCV
RUN apt-get update && apt-get install -y \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 1. Install CPU-only PyTorch (saves massive memory and build time)
RUN pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu

# 2. Copy and install the render-specific requirements
COPY backend/requirements-render.txt .
RUN pip install --no-cache-dir -r requirements-render.txt

# 3. Copy the backend code
COPY backend ./backend

EXPOSE 8000

# Start FastAPI
CMD uvicorn backend.app.main:app --host 0.0.0.0 --port ${PORT:-8000}
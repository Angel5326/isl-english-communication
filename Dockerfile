# Use Python 3.11 (matches your venv)
FROM python:3.11-slim

# Install Linux system dependencies required for MediaPipe, OpenCV, and PyTorch
RUN apt-get update && apt-get install -y \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

# Set the working directory inside the container
WORKDIR /app

# Copy only the requirements file first (for faster caching)
COPY backend/requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy the entire backend folder into the container
COPY backend ./backend

# Expose port 8000 (Render will override this with $PORT)
EXPOSE 8000

# Start FastAPI using Uvicorn, using Render's $PORT variable
CMD uvicorn backend.app.main:app --host 0.0.0.0 --port ${PORT:-8000}
from fastapi import APIRouter, File, UploadFile, HTTPException
from ...services.gesture_recognizer import GestureRecognizer
from ...models.schemas import PredictionResponse

router = APIRouter()

# Initialize the recognizer (this will load all 2064 templates)
recognizer = GestureRecognizer()

@router.post("/predict-sign", response_model=PredictionResponse)
async def predict_sign(video: UploadFile = File(...)):
    try:
        # Predict the sign from the uploaded video
        gloss, confidence = recognizer.predict(video)
        
        if gloss is None:
            raise HTTPException(status_code=400, detail="Could not extract landmarks from video")
        
        return {
            "gloss": gloss,
            "confidence": confidence,
            "message": "success"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
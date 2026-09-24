from pydantic import BaseModel

class PredictionResponse(BaseModel):
    gloss: str
    confidence: float
    message: str
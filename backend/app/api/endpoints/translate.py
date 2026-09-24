from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from ...nlp.gloss_to_english import EnhancedGlossToEnglish

router = APIRouter()
translator = EnhancedGlossToEnglish()

class TranslateRequest(BaseModel):
    gloss: str

@router.post("/translate-gloss")
async def translate_gloss(request: TranslateRequest):
    english = translator.translate(request.gloss)
    return {"english": english}
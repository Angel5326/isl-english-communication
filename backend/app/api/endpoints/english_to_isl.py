from fastapi import APIRouter
from pydantic import BaseModel
from ...nlp.english_to_gloss import EnglishToGloss
from ...services.video_retriever import VideoRetriever

router = APIRouter()
e2g = EnglishToGloss()
retriever = VideoRetriever()

class EnglishRequest(BaseModel):
    text: str

void _sendTextMessage() async {
  if (_textController.text.isEmpty) return;
  String text = _textController.text;
  _textController.clear();

  try {
    final response = await http.post(
      Uri.parse('http://$_baseUrl/api/english-to-isl'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text}),
    );
    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      String gloss = data['gloss'] ?? '';
      _sendMessage(text: text, gloss: gloss);
    } else {
      _sendMessage(text: text);
    }
  } catch (e) {
    _sendMessage(text: text);
  }
}
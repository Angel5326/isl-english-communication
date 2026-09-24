from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
import uuid
from ...services.session_manager import session_manager

router = APIRouter()

class SessionCreate(BaseModel):
    user_id: str

class SessionJoin(BaseModel):
    session_id: str
    user_id: str

// --- Create New Session ---
Future<void> _createNewSession() async {
  try {
    final response = await http.post(
      Uri.parse('http://$_baseUrl/api/session/create'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': _userId}),
    );
    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      setState(() {
        _sessionId = data['session_id'];
        _isConnected = true;
      });
      _connectWebSocket();
      _startAutoDetection();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Session Created: $_sessionId. Share this with others!')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create session: ${response.statusCode} ${response.body}')),
      );
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error creating session: $e')),
    );
  }
}

// --- Join Existing Session ---
Future<void> _joinSession(String sessionId) async {
  try {
    final response = await http.post(
      Uri.parse('http://$_baseUrl/api/session/join'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'session_id': sessionId, 'user_id': _userId}),
    );
    if (response.statusCode == 200) {
      setState(() {
        _sessionId = sessionId;
        _isConnected = true;
      });
      _connectWebSocket();
      _startAutoDetection();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Joined Session: $_sessionId')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to join session: ${response.statusCode} ${response.body}')),
      );
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error joining session: $e')),
    );
  }
}

from typing import Dict, Set, List
from fastapi import WebSocket

class SessionManager:
    def __init__(self):
        self.sessions: Dict[str, Dict] = {}  # session_id -> {users, messages, connections}
        self.connections: Dict[str, Dict[str, WebSocket]] = {}  # session_id -> {user_id: WebSocket}

    def create_session(self, session_id: str, creator_id: str):
        self.sessions[session_id] = {
            "users": {creator_id},
            "messages": [],
            "created_at": timestamp
        }
        self.connections[session_id] = {}

    def session_exists(self, session_id: str) -> bool:
        return session_id in self.sessions

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

    def broadcast(self, session_id: str, message: str, exclude_user: str = None):
        if session_id in self.connections:
            for uid, ws in self.connections[session_id].items():
                if uid != exclude_user:
                    try:
                        ws.send_text(message)
                    except:
                        pass

    def get_session_data(self, session_id: str):
        return self.sessions.get(session_id, {})

session_manager = SessionManager()
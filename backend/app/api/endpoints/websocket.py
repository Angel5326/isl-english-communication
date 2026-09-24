from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from ...services.session_manager import session_manager

router = APIRouter()

@router.websocket("/ws/{session_id}/{user_id}")
async def websocket_endpoint(websocket: WebSocket, session_id: str, user_id: str):
    await websocket.accept()
    session_manager.add_connection(session_id, user_id, websocket)
    try:
        while True:
            data = await websocket.receive_text()
            # Broadcast to all users in the session
            session_manager.broadcast(session_id, data, exclude_user=user_id)
    except WebSocketDisconnect:
        session_manager.remove_connection(session_id, user_id)
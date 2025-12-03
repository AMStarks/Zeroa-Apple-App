#!/usr/bin/env python3
"""
Zeroa Messaging Server
Decentralized P2P messaging relay service
"""

import asyncio
import json
import logging
import os
import uuid
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Set
from urllib.parse import urlparse

import redis.asyncio as redis
import uvicorn
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import httpx
from cryptography.fernet import Fernet
import base64
import hashlib

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/opt/zeroa-messaging/logs/server.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="Zeroa Messaging Server",
    description="Decentralized P2P messaging relay service",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Pydantic models
class MessageRequest(BaseModel):
    sender_address: str = Field(..., description="Sender's TLS address")
    receiver_address: str = Field(..., description="Receiver's TLS address")
    encrypted_content: str = Field(..., description="Encrypted message content")
    message_type: str = Field(default="text", description="Message type")
    signature: str = Field(..., description="Digital signature")
    timestamp: datetime = Field(default_factory=datetime.utcnow)

class PeerRegistration(BaseModel):
    address: str = Field(..., description="Peer's TLS address")
    public_key: str = Field(..., description="Peer's public key")
    connection_info: Dict = Field(default_factory=dict, description="Connection details")
    is_online: bool = Field(default=True, description="Online status")

class MessageResponse(BaseModel):
    success: bool
    message_id: Optional[str] = None
    error: Optional[str] = None
    timestamp: datetime = Field(default_factory=datetime.utcnow)

class PeerInfo(BaseModel):
    address: str
    public_key: str
    last_seen: datetime
    is_online: bool
    connection_info: Dict

# Global variables
redis_client: Optional[redis.Redis] = None
active_connections: Dict[str, WebSocket] = {}
peer_registry: Dict[str, PeerInfo] = {}
message_queue: List[Dict] = []

# Configuration
TLS_API_URL = os.getenv("TLS_API_URL", "https://telestai.cryptoscope.io/api")
ENCRYPTION_KEY = os.getenv("ENCRYPTION_KEY")
if not ENCRYPTION_KEY:
    ENCRYPTION_KEY = Fernet.generate_key().decode()
fernet = Fernet(ENCRYPTION_KEY.encode())

class MessagingService:
    def __init__(self):
        self.redis_client = None
        self.active_peers: Set[str] = set()
        self.message_history: List[Dict] = []
        
    async def initialize(self):
        """Initialize Redis connection"""
        try:
            self.redis_client = redis.Redis(
                host='redis',  # Use Docker service name
                port=6379,
                db=0,
                decode_responses=True
            )
            await self.redis_client.ping()
            logger.info("✅ Redis connection established")
        except Exception as e:
            logger.error(f"❌ Redis connection failed: {e}")
            self.redis_client = None
    
    async def store_message(self, message: Dict) -> str:
        """Store message in Redis"""
        message_id = str(uuid.uuid4())
        message['id'] = message_id
        message['timestamp'] = datetime.utcnow().isoformat()
        
        if self.redis_client:
            await self.redis_client.hset(
                f"message:{message_id}",
                mapping=message
            )
            await self.redis_client.expire(f"message:{message_id}", 86400)  # 24 hours
        
        self.message_history.append(message)
        logger.info(f"📨 Message stored: {message_id}")
        return message_id
    
    async def get_messages_for_peer(self, address: str) -> List[Dict]:
        """Get messages for a specific peer"""
        if not self.redis_client:
            return []
        
        messages = []
        pattern = f"message:*"
        async for key in self.redis_client.scan_iter(match=pattern):
            message_data = await self.redis_client.hgetall(key)
            if (message_data.get('sender_address') == address or 
                message_data.get('receiver_address') == address):
                messages.append(message_data)
        
        return sorted(messages, key=lambda x: x.get('timestamp', ''))
    
    async def register_peer(self, peer: PeerRegistration):
        """Register a peer for discovery"""
        peer_info = PeerInfo(
            address=peer.address,
            public_key=peer.public_key,
            last_seen=datetime.utcnow(),
            is_online=peer.is_online,
            connection_info=peer.connection_info
        )
        
        peer_registry[peer.address] = peer_info
        if peer.is_online:
            self.active_peers.add(peer.address)
        
        if self.redis_client:
            await self.redis_client.hset(
                f"peer:{peer.address}",
                mapping=peer_info.dict()
            )
            await self.redis_client.expire(f"peer:{peer.address}", 3600)  # 1 hour
        
        logger.info(f"👥 Peer registered: {peer.address}")
    
    async def discover_peers(self, requester_address: str) -> List[PeerInfo]:
        """Discover online peers"""
        online_peers = []
        
        if self.redis_client:
            pattern = "peer:*"
            async for key in self.redis_client.scan_iter(match=pattern):
                peer_data = await self.redis_client.hgetall(key)
                if peer_data.get('is_online') == 'True':
                    peer_info = PeerInfo(**peer_data)
                    if peer_info.address != requester_address:
                        online_peers.append(peer_info)
        else:
            # Fallback to in-memory registry
            for peer in peer_registry.values():
                if peer.is_online and peer.address != requester_address:
                    online_peers.append(peer)
        
        return online_peers
    
    async def relay_message(self, message: MessageRequest) -> MessageResponse:
        """Relay message to recipient"""
        try:
            # Validate message
            if not message.sender_address or not message.receiver_address:
                return MessageResponse(
                    success=False,
                    error="Invalid sender or receiver address"
                )
            
            # Store message
            message_dict = message.dict()
            message_id = await self.store_message(message_dict)
            
            # Check if recipient is online (P2P)
            if message.receiver_address in self.active_peers:
                # Try to send via P2P
                if message.receiver_address in active_connections:
                    try:
                        await active_connections[message.receiver_address].send_text(
                            json.dumps({
                                "type": "message",
                                "data": message_dict
                            })
                        )
                        logger.info(f"📤 Message relayed via P2P: {message_id}")
                        return MessageResponse(
                            success=True,
                            message_id=message_id
                        )
                    except Exception as e:
                        logger.warning(f"⚠️ P2P delivery failed: {e}")
            
            # Fallback to blockchain
            blockchain_success = await self.send_to_blockchain(message)
            if blockchain_success:
                logger.info(f"📤 Message sent to blockchain: {message_id}")
                return MessageResponse(
                    success=True,
                    message_id=message_id
                )
            else:
                # Store for later delivery
                await self.queue_message(message_dict)
                logger.info(f"📥 Message queued for later delivery: {message_id}")
                return MessageResponse(
                    success=True,
                    message_id=message_id
                )
                
        except Exception as e:
            logger.error(f"❌ Message relay failed: {e}")
            return MessageResponse(
                success=False,
                error=str(e)
            )
    
    async def send_to_blockchain(self, message: MessageRequest) -> bool:
        """Send message to TLS blockchain as fallback"""
        try:
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    f"{TLS_API_URL}/send",
                    json={
                        "fromAddress": message.sender_address,
                        "toAddress": message.receiver_address,
                        "amount": 0.001,  # Small fee
                        "message": message.encrypted_content,
                        "messageType": message.message_type,
                        "signature": message.signature
                    },
                    timeout=10.0
                )
                
                if response.status_code == 200:
                    return True
                else:
                    logger.warning(f"⚠️ Blockchain send failed: {response.status_code}")
                    return False
                    
        except Exception as e:
            logger.error(f"❌ Blockchain integration error: {e}")
            return False
    
    async def queue_message(self, message: Dict):
        """Queue message for later delivery"""
        if self.redis_client:
            await self.redis_client.lpush("message_queue", json.dumps(message))
            await self.redis_client.expire("message_queue", 86400)  # 24 hours

# Initialize messaging service
messaging_service = MessagingService()

@app.on_event("startup")
async def startup_event():
    """Initialize services on startup"""
    await messaging_service.initialize()
    logger.info("🚀 Zeroa Messaging Server started")

@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    logger.info("🛑 Zeroa Messaging Server shutting down")

# API Endpoints
@app.post("/api/v1/message/relay", response_model=MessageResponse)
async def relay_message(message: MessageRequest):
    """Relay encrypted message to recipient"""
    return await messaging_service.relay_message(message)

@app.post("/api/v1/peer/register")
async def register_peer(peer: PeerRegistration):
    """Register peer for discovery"""
    await messaging_service.register_peer(peer)
    return {"success": True, "message": "Peer registered successfully"}

@app.get("/api/v1/peers/discover")
async def discover_peers(address: str):
    """Discover online peers"""
    peers = await messaging_service.discover_peers(address)
    return {
        "success": True,
        "peers": [peer.dict() for peer in peers],
        "count": len(peers)
    }

@app.get("/api/v1/messages/{address}")
async def get_messages(address: str):
    """Get messages for a specific address"""
    messages = await messaging_service.get_messages_for_peer(address)
    return {
        "success": True,
        "messages": messages,
        "count": len(messages)
    }

@app.get("/api/v1/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "active_peers": len(messaging_service.active_peers),
        "queued_messages": len(message_queue)
    }

# WebSocket for real-time messaging
@app.websocket("/ws/{address}")
async def websocket_endpoint(websocket: WebSocket, address: str):
    """WebSocket endpoint for real-time messaging"""
    await websocket.accept()
    active_connections[address] = websocket
    
    # Register peer as online
    await messaging_service.register_peer(PeerRegistration(
        address=address,
        public_key="",  # Will be updated via API
        is_online=True,
        connection_info={"websocket": True}
    ))
    
    logger.info(f"🔗 WebSocket connected: {address}")
    
    try:
        while True:
            # Receive messages from client
            data = await websocket.receive_text()
            message_data = json.loads(data)
            
            if message_data.get("type") == "message":
                # Relay message to recipient
                message = MessageRequest(**message_data["data"])
                response = await messaging_service.relay_message(message)
                await websocket.send_text(json.dumps(response.dict()))
                
    except WebSocketDisconnect:
        logger.info(f"🔌 WebSocket disconnected: {address}")
    except Exception as e:
        logger.error(f"❌ WebSocket error: {e}")
    finally:
        # Cleanup
        if address in active_connections:
            del active_connections[address]
        
        # Mark peer as offline
        await messaging_service.register_peer(PeerRegistration(
            address=address,
            public_key="",
            is_online=False,
            connection_info={}
        ))

if __name__ == "__main__":
    uvicorn.run(
        "zeroa_messaging_server:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info"
    ) 
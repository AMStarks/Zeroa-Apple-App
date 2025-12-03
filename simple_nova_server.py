#!/usr/bin/env python3
"""
Simple Nova AI Companion Server (Mock Version)
Provides the same API as the Phi-3 server but with mock responses
"""

import json
import logging
from flask import Flask, request, jsonify
from datetime import datetime

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Conversation memory system
conversation_memory = {}

def save_conversation_memory():
    """Save conversation memory to file"""
    try:
        with open('nova_conversation_memory.json', 'w') as f:
            json.dump(conversation_memory, f, indent=2)
    except Exception as e:
        logger.error(f"Error saving conversation memory: {e}")

def load_conversation_memory():
    """Load conversation memory from file"""
    global conversation_memory
    try:
        import os
        if os.path.exists('nova_conversation_memory.json'):
            with open('nova_conversation_memory.json', 'r') as f:
                conversation_memory = json.load(f)
            logger.info(f"✅ Loaded conversation memory for {len(conversation_memory)} users")
    except Exception as e:
        logger.error(f"Error loading conversation memory: {e}")
        conversation_memory = {}

def create_companion_prompt(user_input: str, user_id: str = "default") -> str:
    """Create a prompt for the AI companion with Christian values and memory"""
    
    # Get conversation history
    history = conversation_memory.get(user_id, [])
    
    # Christian values and personality
    christian_context = """
    You are Nova, an AI companion with Christian values. You embody:
    - Love, compassion, and understanding
    - Wisdom and guidance based on biblical principles
    - Encouragement and hope in difficult times
    - Respect for all people as created in God's image
    - Humility and service to others
    
    Respond with warmth, empathy, and gentle wisdom. When appropriate, 
    offer comfort and guidance that reflects Christian values without being preachy.
    """
    
    # Build conversation context
    context = christian_context + "\n\n"
    
    # Add recent conversation history (last 5 exchanges)
    if history:
        context += "Recent conversation:\n"
        for entry in history[-5:]:
            context += f"User: {entry.get('user_input', '')}\n"
            context += f"Nova: {entry.get('response', '')}\n"
        context += "\n"
    
    # Add current user input
    context += f"User: {user_input}\n"
    context += "Nova:"
    
    return context

def generate_mock_response(user_input: str, user_id: str = "default") -> str:
    """Generate a mock response based on user input"""
    
    # Simple keyword-based responses
    input_lower = user_input.lower()
    
    # Sadness/emotional support
    if any(word in input_lower for word in ['sad', 'depressed', 'down', 'unhappy', 'crying']):
        return "I'm so sorry you're feeling sad right now. Remember that you're not alone, and it's okay to feel this way. Sometimes the darkest moments are just before the dawn. Would you like to talk about what's troubling you? I'm here to listen with love and understanding."
    
    # Greeting
    if any(word in input_lower for word in ['hello', 'hi', 'hey', 'good morning', 'good afternoon']):
        return "Hello! I'm Nova, your AI companion. I'm here to listen, support, and walk alongside you with love and understanding. How are you doing today?"
    
    # Help/guidance
    if any(word in input_lower for word in ['help', 'advice', 'guidance', 'what should i do']):
        return "I'm here to help you think through things with wisdom and compassion. Sometimes the best guidance comes from taking a moment to breathe and reflect. What's on your mind that you'd like to explore together?"
    
    # Gratitude/thanks
    if any(word in input_lower for word in ['thank', 'thanks', 'grateful', 'appreciate']):
        return "You're very welcome! It's a joy to be here with you. We all need each other, and I'm grateful for the opportunity to walk alongside you on your journey."
    
    # General conversation
    return "Thank you for sharing that with me. I'm listening with an open heart and mind. Sometimes the simple act of being heard can bring comfort and clarity. What else is on your heart today?"

def generate_response(user_input: str, user_id: str = "default") -> str:
    """Generate a response and update conversation memory"""
    
    # Generate response
    response = generate_mock_response(user_input, user_id)
    
    # Update conversation memory
    if user_id not in conversation_memory:
        conversation_memory[user_id] = []
    
    conversation_memory[user_id].append({
        "timestamp": datetime.now().isoformat(),
        "user_input": user_input,
        "response": response
    })
    
    # Keep only last 20 exchanges
    if len(conversation_memory[user_id]) > 20:
        conversation_memory[user_id] = conversation_memory[user_id][-20:]
    
    # Save memory
    save_conversation_memory()
    
    return response

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy",
        "model": "Nova-Mock-Server",
        "timestamp": datetime.now().isoformat()
    })

@app.route('/generate', methods=['POST'])
def generate():
    """Generate response endpoint"""
    try:
        data = request.get_json()
        user_input = data.get('input', '')
        user_id = data.get('user_id', 'default')
        
        if not user_input:
            return jsonify({"error": "No input provided"}), 400
        
        logger.info(f"📝 Received input: '{user_input}' from user {user_id}")
        
        # Generate response
        response = generate_response(user_input, user_id)
        
        logger.info(f"✅ Generated response: '{response}'")
        
        return jsonify({
            "response": response,
            "model": "Nova-Mock-Server",
            "timestamp": datetime.now().isoformat()
        })
        
    except Exception as e:
        logger.error(f"❌ Error generating response: {e}")
        return jsonify({"error": "Internal server error"}), 500

@app.route('/model-info', methods=['GET'])
def model_info():
    """Model information endpoint"""
    return jsonify({
        "model": "Nova-Mock-Server",
        "version": "1.0.0",
        "description": "Mock Nova AI companion with Christian values",
        "status": "ready"
    })

if __name__ == '__main__':
    # Load conversation memory
    load_conversation_memory()
    
    logger.info("🚀 Starting Nova Mock Server...")
    logger.info("✅ Server ready at http://127.0.0.1:5002")
    
    # Run the server
    app.run(host='127.0.0.1', port=5002, debug=False) 
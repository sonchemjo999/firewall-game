import os
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

# Database
DB_HOST = os.getenv('DB_HOST', '127.0.0.1')
DB_PORT = int(os.getenv('DB_PORT', '3306'))
DB_USER = os.getenv('DB_USER', 'nroshield')
DB_PASS = os.getenv('DB_PASS', '')
DB_NAME = os.getenv('DB_NAME', 'nroshield')

# AI Settings
AI_ENGINE_PORT = int(os.getenv('AI_ENGINE_PORT', '8000'))
AI_LEARNING_DAYS = int(os.getenv('AI_LEARNING_DAYS', '7'))
AI_RETRAIN_INTERVAL = int(os.getenv('AI_RETRAIN_INTERVAL', '3600'))
AI_COLLECT_INTERVAL = int(os.getenv('AI_COLLECT_INTERVAL', '5'))
AI_BLOCK_THRESHOLD = float(os.getenv('AI_BLOCK_THRESHOLD', '0.8'))
AI_RATE_LIMIT_THRESHOLD = float(os.getenv('AI_RATE_LIMIT_THRESHOLD', '0.6'))

# Model paths
MODEL_DIR = os.getenv('MODEL_DIR', '/opt/nroshield/ai_models')
os.makedirs(MODEL_DIR, exist_ok=True)

# VPS
VPS_PUBLIC_IP = os.getenv('VPS_PUBLIC_IP', '')

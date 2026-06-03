"""Database connection for AI Engine"""
import mysql.connector
import config

_db = None

def get_db():
    global _db
    if _db is None or not _db.is_connected():
        _db = mysql.connector.connect(
            host=config.DB_HOST,
            port=config.DB_PORT,
            user=config.DB_USER,
            password=config.DB_PASS,
            database=config.DB_NAME,
            autocommit=False
        )
    return _db

def init_db():
    """Test connection on startup"""
    try:
        db = get_db()
        cursor = db.cursor()
        cursor.execute("SELECT 1")
        cursor.fetchone()
        print("[AI DB] MySQL connected")
    except Exception as e:
        print(f"[AI DB] Connection error: {e}")

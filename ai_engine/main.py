"""
NRO Shield AI Engine — FastAPI Server
Anomaly detection, baseline learning, auto-mitigation
"""
import asyncio
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from apscheduler.schedulers.asyncio import AsyncIOScheduler

import config
from collector.traffic_collector import TrafficCollector
from models.ensemble import EnsembleDetector
from detector.anomaly_scorer import AnomalyScorer
from reactor.auto_mitigator import AutoMitigator
from trainer.model_trainer import ModelTrainer
from storage.db import get_db, init_db

scheduler = AsyncIOScheduler()
collector = TrafficCollector()
ensemble = EnsembleDetector()
scorer = AnomalyScorer()
mitigator = AutoMitigator()
trainer = ModelTrainer()

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup / shutdown"""
    print("[AI Engine] Starting...")
    init_db()
    
    # Load models if exist
    ensemble.load_models()
    
    # Schedule tasks
    scheduler.add_job(collect_and_analyze, 'interval', seconds=config.AI_COLLECT_INTERVAL, id='collect')
    scheduler.add_job(trainer.retrain_models, 'interval', seconds=config.AI_RETRAIN_INTERVAL, id='retrain')
    scheduler.start()
    
    print(f"[AI Engine] Running on port {config.AI_ENGINE_PORT}")
    print(f"[AI Engine] Collect every {config.AI_COLLECT_INTERVAL}s, retrain every {config.AI_RETRAIN_INTERVAL}s")
    yield
    
    scheduler.shutdown()
    print("[AI Engine] Stopped")

app = FastAPI(title="NRO Shield AI Engine", version="1.0.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

async def collect_and_analyze():
    """Main loop: collect → extract features → score → react"""
    try:
        metrics = collector.collect()
        if not metrics:
            return
        
        features = collector.extract_features(metrics)
        score = ensemble.predict(features)
        
        if score is None:
            return
        
        anomaly_type = scorer.classify(features, score)
        action = mitigator.decide_action(score)
        
        if action != 'log':
            await mitigator.execute(action, metrics, score, anomaly_type)
        
        # Save to DB
        scorer.save_detection(metrics, features, score, anomaly_type, action)
        
    except Exception as e:
        print(f"[AI] Analyze error: {e}")

@app.get("/")
async def root():
    return {"service": "NRO Shield AI Engine", "status": "running"}

@app.get("/status")
async def status():
    return {
        "models_loaded": ensemble.is_loaded(),
        "model_versions": ensemble.get_versions(),
        "learning_mode": not ensemble.is_loaded(),
        "collect_interval": config.AI_COLLECT_INTERVAL,
        "retrain_interval": config.AI_RETRAIN_INTERVAL,
        "thresholds": {
            "block": config.AI_BLOCK_THRESHOLD,
            "rate_limit": config.AI_RATE_LIMIT_THRESHOLD,
        }
    }

@app.post("/retrain")
async def retrain():
    try:
        result = trainer.retrain_models()
        return {"message": "Retrain completed", "result": result}
    except Exception as e:
        raise HTTPException(500, str(e))

@app.get("/health")
async def health():
    return {"status": "ok", "engine": "ai"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=config.AI_ENGINE_PORT, reload=False)

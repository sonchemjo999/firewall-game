"""Ensemble anomaly detector — IsolationForest + Autoencoder"""
import os
import numpy as np
import joblib
from sklearn.ensemble import IsolationForest
import config

FEATURE_NAMES = [
    'pps', 'bps', 'conn_count', 'syn_count', 'ack_count',
    'udp_count', 'unique_src_ips', 'avg_pkt_size',
    'syn_ack_ratio', 'new_conn_rate', 'conntrack_usage'
]

class EnsembleDetector:
    def __init__(self):
        self.isolation_forest = None
        self.scaler = None
        self._loaded = False
        self._version = 0
    
    def is_loaded(self):
        return self._loaded
    
    def get_versions(self):
        return {'isolation_forest': self._version}
    
    def load_models(self):
        """Load saved models from disk"""
        if_path = os.path.join(config.MODEL_DIR, 'isolation_forest.pkl')
        sc_path = os.path.join(config.MODEL_DIR, 'scaler.pkl')
        
        if os.path.exists(if_path) and os.path.exists(sc_path):
            self.isolation_forest = joblib.load(if_path)
            self.scaler = joblib.load(sc_path)
            self._loaded = True
            self._version += 1
            print(f"[AI] Models loaded v{self._version}")
        else:
            print("[AI] No saved models found — learning mode")
    
    def save_models(self):
        """Save models to disk"""
        if self.isolation_forest and self.scaler:
            joblib.dump(self.isolation_forest, os.path.join(config.MODEL_DIR, 'isolation_forest.pkl'))
            joblib.dump(self.scaler, os.path.join(config.MODEL_DIR, 'scaler.pkl'))
            print("[AI] Models saved")
    
    def train(self, data_matrix):
        """Train IsolationForest on normal traffic data"""
        if len(data_matrix) < 100:
            print(f"[AI] Need at least 100 samples, got {len(data_matrix)}")
            return False
        
        from sklearn.preprocessing import StandardScaler
        
        self.scaler = StandardScaler()
        X = self.scaler.fit_transform(data_matrix)
        
        self.isolation_forest = IsolationForest(
            n_estimators=200,
            max_samples='auto',
            contamination=0.05,  # 5% expected anomalies
            random_state=42,
            n_jobs=-1
        )
        self.isolation_forest.fit(X)
        
        self._loaded = True
        self._version += 1
        self.save_models()
        
        print(f"[AI] Trained v{self._version} on {len(data_matrix)} samples")
        return True
    
    def predict(self, features):
        """Get anomaly score (0-1, higher = more anomalous)"""
        if not self._loaded or not features:
            return None
        
        try:
            vec = np.array([[features.get(f, 0) for f in FEATURE_NAMES]])
            X = self.scaler.transform(vec)
            
            # IsolationForest: decision_function returns negative for anomalies
            raw_score = -self.isolation_forest.decision_function(X)[0]
            
            # Normalize to 0-1 range
            score = max(0, min(1, (raw_score + 0.5) / 1.0))
            return float(score)
        except Exception as e:
            print(f"[AI] Predict error: {e}")
            return None

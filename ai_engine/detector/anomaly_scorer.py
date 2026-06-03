"""Anomaly scorer — classifies anomaly type and saves detections"""
import config
from storage.db import get_db

class AnomalyScorer:
    def classify(self, features, score):
        """Classify anomaly type based on feature patterns"""
        if not features or score is None:
            return 'unknown'
        
        syn_ratio = features.get('syn_ack_ratio', 0)
        conn = features.get('conn_count', 0)
        pps = features.get('pps', 0)
        udp = features.get('udp_count', 0)
        unique_ips = features.get('unique_src_ips', 0)
        
        if syn_ratio > 5 and pps > 1000:
            return 'syn_flood'
        elif udp > conn * 0.7 and pps > 5000:
            return 'udp_flood'
        elif conn > 500 and unique_ips < 5:
            return 'slowloris'
        elif pps > 10000:
            return 'volumetric'
        elif conn > 300 and unique_ips > 100:
            return 'distributed'
        elif score > config.AI_BLOCK_THRESHOLD:
            return 'anomaly_high'
        else:
            return 'anomaly_low'
    
    def save_detection(self, metrics, features, score, anomaly_type, action):
        """Save detection to database"""
        try:
            db = get_db()
            cursor = db.cursor()
            
            import json
            features_json = json.dumps(features) if features else None
            
            cursor.execute("""
                INSERT INTO ai_detections (anomaly_score, anomaly_type, features_snapshot, action_taken, detected_at)
                VALUES (%s, %s, %s, %s, NOW())
            """, (score, anomaly_type, features_json, action))
            
            # Also save traffic snapshot
            if features:
                cursor.execute("""
                    INSERT INTO ai_traffic_snapshots 
                    (timestamp, pps, bps, conn_count, syn_count, ack_count, udp_count, unique_src_ips,
                     avg_pkt_size, syn_ack_ratio, new_conn_rate, is_attack)
                    VALUES (NOW(), %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """, (
                    features.get('pps', 0), features.get('bps', 0),
                    features.get('conn_count', 0), features.get('syn_count', 0),
                    features.get('ack_count', 0), features.get('udp_count', 0),
                    features.get('unique_src_ips', 0), features.get('avg_pkt_size', 0),
                    features.get('syn_ack_ratio', 0), features.get('new_conn_rate', 0),
                    score > config.AI_RATE_LIMIT_THRESHOLD
                ))
            
            db.commit()
        except Exception as e:
            print(f"[Scorer] Save error: {e}")

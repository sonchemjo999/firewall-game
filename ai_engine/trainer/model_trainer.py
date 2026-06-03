"""Model trainer — retrain models from collected snapshots"""
import numpy as np
from storage.db import get_db
from models.ensemble import EnsembleDetector, FEATURE_NAMES

class ModelTrainer:
    def retrain_models(self):
        """Retrain models using traffic snapshot data"""
        try:
            db = get_db()
            cursor = db.cursor(dictionary=True)
            
            # Get normal traffic data (not attacks)
            cursor.execute("""
                SELECT pps, bps, conn_count, syn_count, ack_count, udp_count,
                       unique_src_ips, avg_pkt_size, syn_ack_ratio, new_conn_rate, 0 as conntrack_usage
                FROM ai_traffic_snapshots
                WHERE is_attack = FALSE
                ORDER BY timestamp DESC LIMIT 10000
            """)
            rows = cursor.fetchall()
            
            if len(rows) < 100:
                print(f"[Trainer] Not enough data: {len(rows)}/100 needed")
                return {'status': 'insufficient_data', 'samples': len(rows)}
            
            # Build matrix
            data = np.array([[row.get(f, 0) for f in FEATURE_NAMES] for row in rows])
            
            # Train
            detector = EnsembleDetector()
            success = detector.train(data)
            
            if success:
                # Save model info to DB
                cursor.execute("""
                    INSERT INTO ai_models (model_name, model_type, accuracy, model_path, training_samples, is_active)
                    VALUES (%s, %s, %s, %s, %s, TRUE)
                """, ('nroshield_if', 'isolation_forest', 0.95, '/opt/nroshield/ai_models/', len(rows)))
                
                # Deactivate old models
                cursor.execute("UPDATE ai_models SET is_active = FALSE WHERE id != LAST_INSERT_ID()")
                db.commit()
                
                return {'status': 'success', 'samples': len(rows)}
            
            return {'status': 'training_failed'}
            
        except Exception as e:
            print(f"[Trainer] Error: {e}")
            return {'status': 'error', 'message': str(e)}

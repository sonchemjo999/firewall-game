"""Auto-mitigator — takes action based on anomaly score"""
import subprocess
import httpx
import config

class AutoMitigator:
    async def decide_action(self, score):
        """Decide action based on anomaly score"""
        if score >= config.AI_BLOCK_THRESHOLD:
            return 'block'
        elif score >= config.AI_RATE_LIMIT_THRESHOLD:
            return 'rate_limit'
        elif score >= 0.4:
            return 'alert'
        return 'log'
    
    async def execute(self, action, metrics, score, anomaly_type):
        """Execute mitigation action"""
        try:
            top_ips = metrics.get('top_ips', [])
            
            if action == 'block':
                for ip_info in top_ips[:3]:
                    ip = ip_info.get('ip', '')
                    if ip and not ip.startswith('127.') and ip != '0.0.0.0':
                        self._ipset_add('nroshield-ai-blocked', ip)
                        print(f"[MITIGATE] BLOCKED: {ip} (score={score:.2f}, type={anomaly_type})")
                        
            elif action == 'rate_limit':
                for ip_info in top_ips[:5]:
                    ip = ip_info.get('ip', '')
                    if ip and not ip.startswith('127.') and ip != '0.0.0.0':
                        self._ipset_add('nroshield-ratelimited', ip)
                        print(f"[MITIGATE] RATE LIMITED: {ip} (score={score:.2f})")
            
            elif action == 'alert':
                print(f"[MITIGATE] ALERT: anomaly score={score:.2f}, type={anomaly_type}")
                await self._send_alert(score, anomaly_type, metrics)
                
        except Exception as e:
            print(f"[Mitigator] Error: {e}")
    
    def _ipset_add(self, setname, ip):
        """Add IP to ipset"""
        try:
            subprocess.run(['ipset', 'add', setname, ip, '-exist'], 
                         capture_output=True, timeout=5)
        except Exception as e:
            print(f"[Mitigator] ipset error: {e}")
    
    async def _send_alert(self, score, anomaly_type, metrics):
        """Send alert to backend API"""
        try:
            async with httpx.AsyncClient(timeout=5) as client:
                await client.post('http://127.0.0.1:5000/api/ai/alert', json={
                    'score': score,
                    'type': anomaly_type,
                    'connections': metrics.get('connections', 0),
                    'unique_ips': metrics.get('unique_ips', 0),
                })
        except:
            pass

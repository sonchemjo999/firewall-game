"""Traffic metric collector — reads system stats for AI analysis"""
import subprocess
import re
import time

class TrafficCollector:
    def __init__(self):
        self.last_rx_bytes = 0
        self.last_tx_bytes = 0
        self.last_time = time.time()
    
    def collect(self):
        """Collect current traffic metrics from system"""
        try:
            metrics = {
                'timestamp': time.time(),
                'connections': self._get_connections(),
                'conntrack': self._get_conntrack(),
                'syn_count': self._get_tcp_state_count('SYN'),
                'ack_count': self._get_tcp_state_count('ESTAB'),
                'rx_bytes': 0, 'tx_bytes': 0,
                'rx_pps': 0, 'tx_pps': 0,
                'unique_ips': self._get_unique_ips(),
                'top_ips': self._get_top_ips(10),
            }
            
            # Calculate rates
            rx, tx = self._get_interface_bytes()
            now = time.time()
            dt = now - self.last_time if self.last_time else 1
            if dt > 0 and self.last_rx_bytes > 0:
                metrics['rx_pps'] = (rx - self.last_rx_bytes) / dt
                metrics['tx_pps'] = (tx - self.last_tx_bytes) / dt
            self.last_rx_bytes, self.last_tx_bytes, self.last_time = rx, tx, now
            
            return metrics
        except Exception as e:
            print(f"[Collector] Error: {e}")
            return None
    
    def extract_features(self, metrics):
        """Extract feature vector for ML model"""
        if not metrics:
            return None
        
        total_conn = metrics.get('connections', 0)
        syn = metrics.get('syn_count', 0)
        ack = metrics.get('ack_count', 0)
        
        return {
            'pps': metrics.get('rx_pps', 0),
            'bps': metrics.get('rx_pps', 0) * 800,  # approx
            'conn_count': total_conn,
            'syn_count': syn,
            'ack_count': ack,
            'udp_count': max(0, total_conn - syn - ack),
            'unique_src_ips': metrics.get('unique_ips', 0),
            'avg_pkt_size': 800 if metrics.get('rx_pps', 0) > 0 else 0,
            'syn_ack_ratio': syn / max(ack, 1),
            'new_conn_rate': syn,
            'conntrack_usage': metrics.get('conntrack', {}).get('usage_pct', 0),
        }
    
    def _get_connections(self):
        try:
            out = subprocess.check_output(['ss', '-s'], text=True, timeout=5)
            m = re.search(r'TCP:\s+(\d+)', out)
            return int(m.group(1)) if m else 0
        except:
            return 0
    
    def _get_conntrack(self):
        try:
            count = int(open('/proc/sys/net/netfilter/nf_conntrack_count').read().strip())
            maxc = int(open('/proc/sys/net/netfilter/nf_conntrack_max').read().strip())
            return {'count': count, 'max': maxc, 'usage_pct': count / max(maxc, 1) * 100}
        except:
            return {'count': 0, 'max': 0, 'usage_pct': 0}
    
    def _get_tcp_state_count(self, state):
        """Get count of TCP connections in a given state"""
        # Map friendly names to standard ss state names
        state_map = {
            'SYN': 'syn-sent',
            'ESTAB': 'established',
            'FIN-WAIT': 'fin-wait-1',
            'TIME-WAIT': 'time-wait',
            'CLOSE-WAIT': 'close-wait',
        }
        ss_state = state_map.get(state.upper(), state.lower())
        
        # Ensure we use names that ss definitely likes
        if ss_state == 'syn': ss_state = 'syn-sent'
        if ss_state == 'estab': ss_state = 'established'
        
        try:
            # -n: no DNS, -t: tcp, -a: all (including syn-sent)
            out = subprocess.check_output(
                ['ss', '-tna', 'state', ss_state],
                text=True, timeout=5, stderr=subprocess.STDOUT
            )
            lines = [l for l in out.strip().split('\n') if l and not l.startswith('State')]
            return len(lines)
        except subprocess.CalledProcessError as e:
            # If 'state' filter fails, fallback to grep
            try:
                out = subprocess.check_output(['ss', '-tna'], text=True, timeout=5)
                # Count occurrences in the whole output
                if ss_state == 'syn-sent':
                    return out.lower().count('syn-sent') + out.lower().count('syn-recv')
                return out.lower().count(ss_state.lower())
            except:
                return 0
        except:
            return 0

    
    def _get_unique_ips(self):
        try:
            out = subprocess.check_output("ss -tn | awk '{print $5}' | cut -d: -f1 | sort -u | wc -l",
                                          shell=True, text=True, timeout=5)
            return int(out.strip())
        except:
            return 0
    
    def _get_top_ips(self, n=10):
        try:
            out = subprocess.check_output(
                f"ss -tn | awk '{{print $5}}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -{n}",
                shell=True, text=True, timeout=5)
            result = []
            for line in out.strip().split('\n'):
                parts = line.strip().split()
                if len(parts) == 2:
                    result.append({'ip': parts[1], 'count': int(parts[0])})
            return result
        except:
            return []
    
    def _get_interface_bytes(self):
        try:
            with open('/proc/net/dev') as f:
                for line in f:
                    if 'eth0' in line or 'ens' in line:
                        parts = line.split()
                        return int(parts[1]), int(parts[9])
        except:
            pass
        return 0, 0

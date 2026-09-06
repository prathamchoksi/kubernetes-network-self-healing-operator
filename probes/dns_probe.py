"""
DNS Probe for CoreDNS Health Monitoring

Monitors CoreDNS pod status and DNS latency.
Reports findings for the operator to act on.
"""

import time
import logging
import subprocess
import json
from datetime import datetime
from typing import Dict, List
from prometheus_client import start_http_server, Gauge

DNS_LATENCY = Gauge('dns_latency_ms', 'DNS resolution latency in milliseconds')
DNS_HEALTHY = Gauge('dns_healthy', 'DNS resolution health status (1 = healthy, 0 = unhealthy)')

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - DNS_PROBE - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class DNSProbe:
    """Monitor CoreDNS health and latency."""
    
    def __init__(self, interval_seconds: int = 10):
        self.interval = interval_seconds
        self.test_domain = "kubernetes.default.svc.cluster.local"
        self.results = {
            "healthy": True,
            "latency_ms": 0,
            "last_check": None,
            "failure_count": 0,
            "error_message": None
        }
    
    def check_dns_resolution(self) -> Dict:
        """
        Check if DNS resolution works.
        Returns dict with health status and latency.
        """
        start_time = time.time()
        result = {
            "success": False,
            "latency_ms": 0,
            "timestamp": datetime.now().isoformat()
        }
        
        try:
            # Try to resolve kubernetes service
            import socket
            start = time.perf_counter()
            socket.gethostbyname(self.test_domain)
            elapsed = (time.perf_counter() - start) * 1000  # Convert to ms
            
            result["success"] = True
            result["latency_ms"] = elapsed
            
            logger.info(f"DNS resolution successful: {elapsed:.2f}ms")
            
            # Check for latency threshold (e.g., >100ms is slow)
            if elapsed > 100:
                logger.warning(f"DNS latency high: {elapsed:.2f}ms (threshold: 100ms)")
                result["latency_warning"] = True
            
        except socket.gaierror as e:
            logger.error(f"DNS resolution failed: {e}")
            result["success"] = False
            result["error"] = str(e)
        except Exception as e:
            logger.error(f"Unexpected DNS probe error: {e}")
            result["success"] = False
            result["error"] = str(e)
        
        return result
    
    def check_coredns_pod_status(self) -> Dict:
        """
        Check CoreDNS pod status using kubectl.
        Returns pod health information.
        """
        result = {
            "pod_running": False,
            "restart_count": 0,
            "pod_name": None,
            "timestamp": datetime.now().isoformat()
        }
        
        try:
            # Get CoreDNS pod status
            cmd = [
                "kubectl", "get", "pods", "-n", "kube-system",
                "-l", "k8s-app=kube-dns",
                "-o", "json"
            ]
            output = subprocess.check_output(cmd, text=True)
            pods_data = json.loads(output)
            
            if pods_data.get("items"):
                pod = pods_data["items"][0]  # Get first CoreDNS pod
                result["pod_name"] = pod["metadata"]["name"]
                
                status = pod.get("status", {})
                phase = status.get("phase", "Unknown")
                result["phase"] = phase
                result["pod_running"] = phase == "Running"
                
                # Check container restart count
                if status.get("containerStatuses"):
                    restart_count = status["containerStatuses"][0].get("restartCount", 0)
                    result["restart_count"] = restart_count
                    
                    if restart_count > 3:
                        logger.warning(f"CoreDNS pod has restarted {restart_count} times")
                        result["restart_warning"] = True
                
                logger.info(f"CoreDNS pod: {result['pod_name']} phase={phase} restarts={restart_count}")
            else:
                logger.error("No CoreDNS pods found")
                result["error"] = "No CoreDNS pods found"
        
        except subprocess.CalledProcessError as e:
            logger.error(f"kubectl command failed: {e}")
            result["error"] = str(e)
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse kubectl output: {e}")
            result["error"] = str(e)
        except Exception as e:
            logger.error(f"Unexpected error checking CoreDNS pod: {e}")
            result["error"] = str(e)
        
        return result
    
    def run(self):
        """
        Main probe loop.
        Check DNS health at regular intervals and log results.
        """
        logger.info(f"Starting DNS probe (check every {self.interval}s)")
        
        # Start Prometheus metrics server
        start_http_server(8000)
        logger.info("Prometheus metrics server started on port 8000")
        
        try:
            while True:
                logger.info("--- DNS Probe Check ---")
                
                # Check DNS resolution
                dns_result = self.check_dns_resolution()
                
                # Check CoreDNS pod status
                pod_result = self.check_coredns_pod_status()
                
                # Update results
                self.results = {
                    "healthy": dns_result.get("success", False) and pod_result.get("pod_running", False),
                    "latency_ms": dns_result.get("latency_ms", 0),
                    "pod_running": pod_result.get("pod_running", False),
                    "pod_name": pod_result.get("pod_name"),
                    "restart_count": pod_result.get("restart_count", 0),
                    "last_check": datetime.now().isoformat(),
                    "dns_success": dns_result.get("success", False),
                    "error_message": dns_result.get("error") or pod_result.get("error")
                }
                
                # Update Prometheus metrics
                DNS_LATENCY.set(self.results["latency_ms"])
                DNS_HEALTHY.set(1 if self.results["healthy"] else 0)
                
                # Log summary
                status = "HEALTHY" if self.results["healthy"] else "UNHEALTHY"
                logger.info(f"Probe result: {status} | Latency: {self.results['latency_ms']:.2f}ms | Pod: {pod_result.get('phase', 'Unknown')}")
                
                time.sleep(self.interval)
        
        except KeyboardInterrupt:
            logger.info("DNS probe stopped by user")
        except Exception as e:
            logger.error(f"DNS probe crashed: {e}")
            raise


if __name__ == "__main__":
    probe = DNSProbe(interval_seconds=10)
    probe.run()

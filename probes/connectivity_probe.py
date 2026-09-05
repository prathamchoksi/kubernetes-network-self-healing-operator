"""
Connectivity Probe for Pod-to-Pod Communication Monitoring

Monitors connectivity between pods in different namespaces.
Detects NetworkPolicy blocking and pod communication failures.
Reports findings for the operator to act on.
"""

import time
import logging
import subprocess
import json
from datetime import datetime
from typing import Dict, List, Tuple

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - CONNECTIVITY_PROBE - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class ConnectivityProbe:
    """Monitor pod-to-pod connectivity and NetworkPolicy effectiveness."""
    
    def __init__(self, interval_seconds: int = 15):
        self.interval = interval_seconds
        # Test connectivity between these pods
        self.test_cases = [
            {
                "source_ns": "test-namespace-2",
                "source_pod": "curl-client-2",
                "target_ns": "test-namespace-1",
                "target_service": "nginx-server-1",
                "target_port": 80,
                "name": "curl-2-to-nginx-1"
            },
            {
                "source_ns": "test-namespace-1",
                "source_pod": "curl-client-1",
                "target_ns": "test-namespace-1",
                "target_service": "nginx-server-1",
                "target_port": 80,
                "name": "curl-1-to-nginx-1-same-ns"
            }
        ]
        self.results = {}
    
    def test_pod_connectivity(self, source_ns: str, source_pod: str, 
                             target_ns: str, target_service: str, 
                             target_port: int, timeout: int = 5) -> Dict:
        """
        Test connectivity from one pod to a service.
        Uses kubectl exec + curl inside the source pod.
        """
        result = {
            "success": False,
            "response_time_ms": 0,
            "http_code": None,
            "timestamp": datetime.now().isoformat(),
            "error": None
        }
        
        # Build curl URL
        # Format: service-name.namespace.svc.cluster.local
        target_url = f"http://{target_service}.{target_ns}.svc.cluster.local:{target_port}/"
        
        try:
            # Build kubectl exec command with curl
            cmd = [
                "kubectl", "exec", source_pod, "-n", source_ns, "--",
                "curl", "-s", "-w", "%{http_code}", "-m", str(timeout), target_url
            ]
            
            import time as time_module
            start = time_module.perf_counter()
            output = subprocess.check_output(cmd, text=True, timeout=timeout + 2)
            elapsed = (time_module.perf_counter() - start) * 1000  # ms
            
            # Parse response
            http_code = output[-3:] if len(output) >= 3 else "000"
            result["http_code"] = http_code
            result["response_time_ms"] = elapsed
            result["success"] = http_code.startswith("2") or http_code.startswith("3")
            
            if result["success"]:
                logger.info(f"Connectivity OK: {http_code} in {elapsed:.2f}ms")
            else:
                logger.warning(f"Connectivity failed: HTTP {http_code} in {elapsed:.2f}ms")
            
        except subprocess.TimeoutExpired:
            logger.error(f"Connectivity check timeout (>{timeout}s)")
            result["error"] = "timeout"
        except subprocess.CalledProcessError as e:
            logger.error(f"Pod connectivity check failed: {e}")
            # Try to get stderr for more info
            result["error"] = str(e)
        except Exception as e:
            logger.error(f"Unexpected connectivity check error: {e}")
            result["error"] = str(e)
        
        return result
    
    def check_network_policy_status(self, namespace: str) -> Dict:
        """
        Check if NetworkPolicies are applied in a namespace.
        Returns list of NetworkPolicies and their status.
        """
        result = {
            "policies": [],
            "timestamp": datetime.now().isoformat()
        }
        
        try:
            cmd = [
                "kubectl", "get", "networkpolicies", "-n", namespace, "-o", "json"
            ]
            output = subprocess.check_output(cmd, text=True)
            policies_data = json.loads(output)
            
            for policy in policies_data.get("items", []):
                policy_info = {
                    "name": policy["metadata"]["name"],
                    "namespace": namespace,
                    "pod_selector": policy["spec"].get("podSelector", {}),
                    "ingress_rules": len(policy["spec"].get("ingress", [])),
                    "egress_rules": len(policy["spec"].get("egress", []))
                }
                result["policies"].append(policy_info)
            
            logger.info(f"Found {len(result['policies'])} NetworkPolicies in {namespace}")
        
        except subprocess.CalledProcessError as e:
            logger.warning(f"Failed to get NetworkPolicies: {e}")
            result["error"] = str(e)
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse NetworkPolicies: {e}")
            result["error"] = str(e)
        
        return result
    
    def run(self):
        """
        Main probe loop.
        Test connectivity at regular intervals and log results.
        """
        logger.info(f"Starting connectivity probe (check every {self.interval}s)")
        logger.info(f"Test cases: {len(self.test_cases)}")
        
        try:
            while True:
                logger.info("--- Connectivity Probe Check ---")
                
                all_healthy = True
                
                for test_case in self.test_cases:
                    logger.info(f"Testing: {test_case['name']}")
                    
                    result = self.test_pod_connectivity(
                        source_ns=test_case["source_ns"],
                        source_pod=test_case["source_pod"],
                        target_ns=test_case["target_ns"],
                        target_service=test_case["target_service"],
                        target_port=test_case["target_port"]
                    )
                    
                    self.results[test_case["name"]] = result
                    
                    if not result["success"]:
                        all_healthy = False
                        logger.warning(f"FAILED: {test_case['name']} - {result.get('error', 'unknown error')}")
                    else:
                        logger.info(f"PASSED: {test_case['name']} - {result['response_time_ms']:.2f}ms")
                
                # Check NetworkPolicies in test namespaces
                logger.info("Checking NetworkPolicies...")
                for ns in ["test-namespace-1", "test-namespace-2"]:
                    policy_result = self.check_network_policy_status(ns)
                    self.results[f"policies-{ns}"] = policy_result
                
                # Summary
                status = "ALL OK" if all_healthy else "ISSUES DETECTED"
                logger.info(f"Probe result: {status}")
                
                time.sleep(self.interval)
        
        except KeyboardInterrupt:
            logger.info("Connectivity probe stopped by user")
        except Exception as e:
            logger.error(f"Connectivity probe crashed: {e}")
            raise


def apply_bad_network_policy(namespace: str, policy_name: str = "block-all"):
    """
    Create a NetworkPolicy that blocks all traffic (for testing).
    Simulates a misconfigured NetworkPolicy.
    """
    logger.info(f"Creating blocking NetworkPolicy in {namespace}")
    
    policy_yaml = f"""
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {policy_name}
  namespace: {namespace}
spec:
  podSelector: {{}}
  policyTypes:
  - Ingress
  - Egress
  ingress: []
  egress: []
"""
    
    try:
        # Use kubectl apply to create the policy
        cmd = ["kubectl", "apply", "-f", "-"]
        subprocess.run(cmd, input=policy_yaml, text=True, check=True)
        logger.info(f"NetworkPolicy {policy_name} applied")
    except Exception as e:
        logger.error(f"Failed to apply NetworkPolicy: {e}")


def remove_bad_network_policy(namespace: str, policy_name: str = "block-all"):
    """
    Remove a blocking NetworkPolicy (for recovery).
    """
    logger.info(f"Removing NetworkPolicy {policy_name} from {namespace}")
    
    try:
        cmd = ["kubectl", "delete", "networkpolicy", policy_name, "-n", namespace]
        subprocess.run(cmd, check=True)
        logger.info(f"NetworkPolicy {policy_name} removed")
    except Exception as e:
        logger.error(f"Failed to remove NetworkPolicy: {e}")


if __name__ == "__main__":
    probe = ConnectivityProbe(interval_seconds=15)
    probe.run()

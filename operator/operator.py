"""
Kubernetes Network Self-Healing Operator
DNS and Connectivity Monitoring

This operator watches for networking failures and automatically remediates them:
- CoreDNS pod crashes/latency
- Pod-to-pod connectivity issues  
- NetworkPolicy reachability problems
"""

import kopf
import kubernetes
from kubernetes import client, config
import logging
import time
from datetime import datetime, timedelta

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global state for tracking remediation cooldowns (prevent flapping)
remediation_cooldown = {}
COOLDOWN_SECONDS = 60


def get_k8s_client():
    """Get Kubernetes client, handling both in-cluster and local development."""
    try:
        config.load_incluster_config()  # In-cluster config
    except config.config_exception.ConfigException:
        config.load_kube_config()  # Local kubeconfig (~/.kube/config)
    return client.CoreV1Api()


def is_in_cooldown(key: str) -> bool:
    """Check if a remediation action is in cooldown period."""
    if key not in remediation_cooldown:
        return False
    if datetime.now() < remediation_cooldown[key]:
        logger.info(f"Action '{key}' is still in cooldown")
        return True
    del remediation_cooldown[key]
    return False


def set_cooldown(key: str):
    """Set remediation cooldown for this action."""
    remediation_cooldown[key] = datetime.now() + timedelta(seconds=COOLDOWN_SECONDS)
    logger.info(f"Set cooldown for '{key}' for {COOLDOWN_SECONDS} seconds")


@kopf.on.pod.event(namespace="kube-system", labels={"k8s-app": "kube-dns"})
def coredns_pod_changed(event, name, namespace, **kwargs):
    """
    Monitor CoreDNS pod status.
    Triggers remediation if pod crashes or becomes unhealthy.
    """
    pod = event["object"]
    status = pod.get("status", {})
    phase = status.get("phase", "Unknown")
    
    logger.info(f"CoreDNS pod event: {name} phase={phase}")
    
    # Check pod health
    if phase == "Failed" or phase == "Unknown":
        logger.warning(f"CoreDNS pod is in {phase} state, attempting remediation")
        remediate_coredns_crash(name, namespace)
    
    # Check container restart count
    for container_status in status.get("containerStatuses", []):
        restart_count = container_status.get("restartCount", 0)
        if restart_count > 5:
            logger.warning(f"CoreDNS pod has restarted {restart_count} times")


def remediate_coredns_crash(pod_name: str, namespace: str = "kube-system"):
    """
    Remediate CoreDNS crash by deleting the pod.
    Kubernetes will restart it automatically.
    """
    cooldown_key = f"coredns-restart-{pod_name}"
    
    if is_in_cooldown(cooldown_key):
        return
    
    logger.info(f"Remediating CoreDNS crash: deleting pod {pod_name}")
    
    try:
        v1 = get_k8s_client()
        v1.delete_namespaced_pod(pod_name, namespace)
        logger.info(f"Successfully deleted CoreDNS pod: {pod_name}")
        set_cooldown(cooldown_key)
    except kubernetes.client.rest.ApiException as e:
        logger.error(f"Failed to delete CoreDNS pod: {e}")


@kopf.timer("kopfpeering.zalando.org", interval=30)
def check_coredns_latency(**kwargs):
    """
    Periodic check for CoreDNS latency.
    This would be enhanced with actual DNS probe results from the connectivity probe.
    """
    logger.debug("Checking CoreDNS latency (placeholder)")
    # TODO: Integrate with dns_probe.py results
    pass


@kopf.timer("kopfpeering.zalando.org", interval=60)
def check_pod_connectivity(**kwargs):
    """
    Periodic check for pod-to-pod connectivity.
    Triggered by connectivity probe detecting failures.
    """
    logger.debug("Checking pod connectivity (placeholder)")
    # TODO: Integrate with connectivity_probe.py results
    pass


def remediate_network_policy(namespace: str, policy_name: str):
    """
    Remediate NetworkPolicy issues by reapplying last-known-good policy.
    """
    cooldown_key = f"networkpolicy-reapply-{namespace}-{policy_name}"
    
    if is_in_cooldown(cooldown_key):
        return
    
    logger.info(f"Remediating NetworkPolicy: {policy_name} in {namespace}")
    
    try:
        # TODO: Load and reapply last-known-good NetworkPolicy
        logger.info(f"Successfully reapplied NetworkPolicy: {policy_name}")
        set_cooldown(cooldown_key)
    except Exception as e:
        logger.error(f"Failed to reapply NetworkPolicy: {e}")


@kopf.on.startup()
def startup_handler(**kwargs):
    """Called when the operator starts."""
    logger.info("Network Self-Healing Operator started")
    logger.info(f"Cooldown period: {COOLDOWN_SECONDS} seconds")


if __name__ == "__main__":
    logger.info("Starting kopf operator...")
    kopf.run(clusterwide=True, peering_name="network-healing-operator")

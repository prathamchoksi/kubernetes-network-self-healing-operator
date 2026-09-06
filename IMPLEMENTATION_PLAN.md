# Kubernetes Network Self-Healing Operator: Full Scope Implementation Plan

This document defines the complete technical implementation plan to achieve the full scope of the **Kubernetes Network Self-Healing Operator** project without feature cuts.

---

## 1. Overview & Objectives

Kubernetes natively provides pod restarts and node rescheduling, but lacks automated recovery for networking-specific infrastructure failures:

- **CNI plugin failures** (e.g., crashing Calico/Flannel node pods)
- **DNS failures & degradation** (e.g., CoreDNS crashes, elevated query latency)
- **Pod-to-pod connectivity breakage** (e.g., misconfigured or broken NetworkPolicies blocking application traffic)

This project builds a custom Kubernetes operator and active probe monitoring system to automatically detect these network failures and execute remediations:

- **Auto-restarting failed DNS pods** or performing DNS failover
- **Auto-remediating CNI node pods / DaemonSets**
- **Reverting / reapplying valid NetworkPolicies** upon detected reachability drops
- **Observability pipeline**: Prometheus + Alertmanager alert routing, metrics scraping via ServiceMonitors, and Loki/Grafana log/metric dashboards

---

## 2. Architectural Design & Component Interactions

```
+-------------------------------------------------------------+
|                     Kubernetes Cluster                      |
|                                                             |
|  +--------------------+             +--------------------+  |
|  |     DNS Probe      |             | Connectivity Probe |  |
|  |  (dns_latency_ms)  |             | (conn_success=0/1) |  |
|  +---------+----------+             +---------+----------+  |
|            |                                  |             |
|            +-----------------+----------------+             |
|                              |                              |
|                              v                              |
|               +-----------------------------+               |
|               |  Prometheus + kube-state    |               |
|               |   (Evaluates Alert Rules)   |               |
|               +--------------+--------------+               |
|                              |                              |
|                              v                              |
|               +-----------------------------+               |
|               |        Alertmanager         |               |
|               |  (Routes alerts to webhook) |               |
|               +--------------+--------------+               |
|                              |                              |
+------------------------------|------------------------------+
                               v (HTTP POST /webhook)
          +-----------------------------------------+
          |      Network Self-Healing Operator      |
          |           (Python + Kopf)               |
          | - Event Watchers (CoreDNS, CNI pods)    |
          | - Alertmanager Webhook Receiver         |
          | - Cooldown & Anti-Flap Management       |
          | - Kubernetes API Remediation Actions    |
          +--------------------+--------------------+
                               |
        +----------------------+----------------------+
        |                      |                      |
        v                      v                      v
[Restart CoreDNS]       [Restart CNI Pods]     [Reapply NetworkPolicy]
```

---

## 3. Scope Breakdown & Implementation Phases

### Phase 1: Probes Containerization & ServiceMonitors

1. **Containerize Probes (`probes/Dockerfile`, `probes/requirements.txt`)**:
   - Package `dns_probe.py` and `connectivity_probe.py` into a single container image.
   - Include `curl` and `kubectl` to support remote pod exec connectivity tests.
2. **Kubernetes Deployments & RBAC (`manifests/probes.yaml`)**:
   - Deploy `dns-probe` (port 8000) and `connectivity-probe` (port 8001) in the `monitoring` namespace.
   - Provide a dedicated `ServiceAccount` and `ClusterRoleBinding` granting pod exec and network policy read permissions.
3. **Prometheus Scraping (`manifests/monitoring/service-monitors.yaml`)**:
   - Define `ServiceMonitor` resources matching the probes to enable continuous metric scraping by Prometheus.

### Phase 2: Alert Rules & Alertmanager Routing

1. **Prometheus Alert Rules (`manifests/monitoring/alerts.yaml`)**:
   - `DNSResolutionFailed`: Triggered when `dns_healthy == 0`.
   - `DNSLatencyHigh`: Triggered when `dns_latency_ms > 100`.
   - `PodConnectivityBlocked`: Triggered when `connectivity_success == 0`.
   - `CNIPodCrash`: Triggered when Calico (`calico-system`) or Flannel (`kube-flannel`) pods fail or experience repeated container restarts.
2. **Alertmanager Webhook Config (`manifests/monitoring/alertmanager-config.yaml`)**:
   - Configure receiver webhooks to forward active alerts directly to the operator's HTTP webhook endpoint (`/webhook`).

### Phase 3: Multi-CNI Cluster Support

1. **Cluster Provisioning Script (`cluster-setup.ps1`)**:
   - Add parameterization (`-CNI Calico` or `-CNI Flannel`).
   - Support automated download and deployment of the official Flannel manifest (`https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml`).
   - Retain Calico Tigera operator installation as default.

### Phase 4: Fault Injection Suite

1. **Script Upgrades (`fault-injection/inject_faults.sh`)**:
   - Implement `kill-cni` action: Detects and kills active Calico (`calico-node`) or Flannel (`kube-flannel-ds`) pods.
   - Retain and verify:
     - `kill-coredns` (force deletion of CoreDNS pod).
     - `apply-bad-policy` (creates zero-ingress blocking NetworkPolicy).
     - `remove-bad-policy` (cleans up policy).
     - `check-connectivity` and `check-dns` (manual verification).
     - `full-scenario` (automated end-to-end verification sequence).

### Phase 5: Operator Enhancements & Remediations

1. **Alertmanager Webhook Listener (`operator/operator.py`)**:
   - Run an internal lightweight HTTP server (e.g. threading HTTP server or Flask) listening for Alertmanager alert payloads.
2. **Remediation Handlers**:
   - **CoreDNS Crash / High Latency**: Delete failed/high-latency CoreDNS pods to force clean restarts.
   - **CNI Pod Failure**: Evict/restart the crashing CNI pod in `calico-system` or `kube-flannel`.
   - **Broken NetworkPolicy**: Detect blocking policy (`block-all-ingress` or faulty ingress/egress rules) and automatically delete/restore the baseline configuration.
3. **Anti-Flap & Cooldown**:
   - Ensure an exponential backoff or 60-second cooldown per target to prevent thrashing restart loops.

### Phase 6: Observability (Loki & Grafana Dashboards)

1. **Grafana Dashboards (`manifests/monitoring/grafana-dashboards.yaml`)**:
   - Create dashboard panels visualizing:
     - DNS latency trends (`dns_latency_ms`)
     - Pod-to-pod connectivity status (`connectivity_success`)
     - CNI pod restarts
     - Log stream from Loki capturing Operator remediation events.

---

## 4. Verification & Testing Matrix

| Scenario                | Fault Injected                        | Expected Detection                                  | Expected Operator Remediation          | Success Criteria                             |
| :---------------------- | :------------------------------------ | :-------------------------------------------------- | :------------------------------------- | :------------------------------------------- |
| **DNS Failure**         | `./inject_faults.sh kill-coredns`     | Prometheus `DNSResolutionFailed` / `DNSLatencyHigh` | Deletes/restarts CoreDNS pod           | DNS resolution succeeds within 30s           |
| **NetworkPolicy Block** | `./inject_faults.sh apply-bad-policy` | Prometheus `PodConnectivityBlocked`                 | Reverts/deletes blocking NetworkPolicy | Curl connectivity test returns `HTTP 200`    |
| **CNI Crash**           | `./inject_faults.sh kill-cni`         | Prometheus `CNIPodCrash` / Pod Event Watcher        | Restarts failed CNI node pod           | CNI pod returns to `1/1 Running`, node Ready |
| **Multi-CNI Setup**     | Run `cluster-setup.ps1 -CNI Flannel`  | Pod status checks                                   | Proper CNI pod scheduling              | All nodes `Ready` under Flannel              |

---

## 5. Next Steps

1. Run the cluster setup script with the preferred CNI plugin.
2. Build and apply probe container manifests and ServiceMonitors.
3. Apply updated Prometheus alerting rules and Alertmanager configurations.
4. Launch the enhanced operator and validate the full test suite using `./fault-injection/inject_faults.sh full-scenario`.

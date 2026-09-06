# Parallel Work Allocation Plan: 2-Developer Split

This document splits the remaining project tasks between **Developer 1** and **Developer 2** to enable 100% concurrent progress **without Git merge conflicts**.

---

## 1. Zero-Conflict Architecture & File Boundaries

To prevent merge conflicts, each developer works in strictly isolated directories and files. The two tracks integrate exclusively over the network via the **Alertmanager Webhook Contract** (`POST http://<operator-host>:8080/webhook`).

```
+-------------------------------------------------------------------------------+
|                       ISOLATED COMPONENT BOUNDARIES                           |
+---------------------------------------+---------------------------------------+
|  DEVELOPER 1 (Operator Track)         |  DEVELOPER 2 (Monitoring & Probes)    |
+---------------------------------------+---------------------------------------+
|  Directory: operator-go/              |  Directories:                         |
|  Files:                               |    - manifests/monitoring/            |
|    - operator-go/main.go              |    - manifests/probes.yaml            |
|    - operator-go/remediation.go (new) |    - probes/                          |
|    - operator-go/main_test.go (new)   |    - fault-injection/                 |
|    - manifests/operator.yaml (new)    |    - manifests/monitoring/grafana.yaml|
+---------------------------------------+---------------------------------------+
```

---

## 2. Developer 1: Operator Core & Remediation Engine

**Branch**: `feature/dev1-operator-remediation`  
**Owned Scope**: `operator-go/`, `manifests/operator.yaml`

### Key Responsibilities:

1. **Anti-Flap & Cooldown Mechanism (`operator-go/main.go`)**:
   - Implement an in-memory thread-safe cooldown cache (`sync.Map` or mutex-guarded map).
   - Prevent repeat remediations (e.g. restart loops) on the same target within 60 seconds of a previous action.
2. **Policy Rollback Engine (`remediateNetworkPolicy`)**:
   - Instead of merely deleting blocking policies, restore the baseline test policy from a predefined manifest or embedded specification so traffic flows normally.
3. **Backup DNS Deployment Logic (`deployBackupDNS`)**:
   - Implement the actual fallback logic: either patch CoreDNS ConfigMap to append public upstream forwarders (e.g., `8.8.8.8`, `1.1.1.1`) or deploy a local DNS forwarder pod.
4. **Containerization & Deployment Manifest (`manifests/operator.yaml`)**:
   - Add a `Dockerfile` inside `operator-go/` to build the Go binary into a scratch/distroless container.
   - Create `manifests/operator.yaml` with Deployment, Service (port 8080), and RBAC `ClusterRole` permissions to allow running the operator natively inside the cluster.
5. **Unit Testing (`operator-go/main_test.go`)**:
   - Mock Alertmanager webhook payloads and test alert dispatch logic locally (`go test ./...`).

---

## 3. Developer 2: Monitoring, Probes, Grafana & Chaos Testing

**Branch**: `feature/dev2-monitoring-probes`  
**Owned Scope**: `probes/`, `manifests/monitoring/`, `manifests/probes.yaml`, `fault-injection/`

### Key Responsibilities:

1. **Probe Container Build & Verification**:
   - Build and test the probe container image:
     ```bash
     docker build -t network-probes:latest probes/
     kind load docker-image network-probes:latest --name k8s-network-healing
     ```
   - Verify probes start cleanly and expose metrics on ports `8000` (DNS) and `8001` (Connectivity).
2. **ServiceMonitors & Prometheus Rules Verification (`manifests/monitoring/`)**:
   - Apply `manifests/probes.yaml` and `manifests/monitoring/service-monitors.yaml`.
   - Verify Prometheus targets page shows both probes as `UP`.
   - Test firing of `DNSLatencyHigh`, `PodConnectivityBlocked`, and `CNIPodCrash` rules in Prometheus UI.
3. **Grafana Dashboard Manifest (`manifests/monitoring/grafana-dashboards.yaml`)**:
   - Create a preconfigured Grafana Dashboard ConfigMap containing panels for:
     - DNS Latency gauge & time series (`dns_latency_ms`)
     - Connectivity status boolean (`connectivity_success`)
     - CNI pod restart counters (`kube_pod_container_status_restarts_total`)
4. **Chaos Injection Suite Expansion (`fault-injection/inject_faults.sh`)**:
   - Add automated verification assertions to `full_scenario()`:
     - Verify DNS recovery latency after pod deletion.
     - Verify connectivity restore after NetworkPolicy recovery.
   - Add a test summary report generator at the end of `full_scenario`.

---

## 4. Integration Contract (The Interface Between Dev 1 & Dev 2)

Neither developer needs to wait for the other. The interface is strictly governed by the Prometheus Alertmanager webhook payload sent to `POST :8080/webhook`:

```json
{
  "receiver": "operator-webhook",
  "status": "firing",
  "alerts": [
    {
      "status": "firing",
      "labels": {
        "alertname": "DNSResolutionFailed",
        "severity": "critical",
        "component": "dns"
      },
      "annotations": {
        "summary": "DNS resolution is failing"
      }
    }
  ]
}
```

### Supported `alertname` values:

- `DNSResolutionFailed` / `DNSLatencyHigh` $\rightarrow$ triggers `remediateDNS()`
- `PodConnectivityBlocked` $\rightarrow$ triggers `remediateNetworkPolicy()`
- `CNIPodCrash` $\rightarrow$ triggers `remediateCNI()`

---

## 5. Git Workflow to Guarantee Zero Conflicts

### Step 1: Create Independent Branches

Both developers branch off `gobuild`:

```bash
# Developer 1:
git checkout gobuild
git pull origin gobuild
git checkout -b feature/dev1-operator-remediation

# Developer 2:
git checkout gobuild
git pull origin gobuild
git checkout -b feature/dev2-monitoring-probes
```

### Step 2: Work & Commit Strictly Within Assigned Folders

- Dev 1 **only** modifies files in `operator-go/` and `manifests/operator.yaml`.
- Dev 2 **only** modifies files in `probes/`, `manifests/monitoring/`, `manifests/probes.yaml`, and `fault-injection/`.

### Step 3: Clean Merge Back to `gobuild`

Because the file sets are completely disjoint:

1. **Developer 1 merges first**:
   ```bash
   git checkout gobuild
   git merge feature/dev1-operator-remediation
   git push origin gobuild
   ```
2. **Developer 2 rebases and merges second**:
   ```bash
   git checkout feature/dev2-monitoring-probes
   git pull --rebase origin gobuild
   git checkout gobuild
   git merge feature/dev2-monitoring-probes
   git push origin gobuild
   ```
   _(Result: Fast-forward or 100% clean merge with zero conflicts)._

---

## 6. Joint End-to-End Verification Checkpoint

Once both branches are merged into `gobuild`:

1. Start KIND cluster: `.\cluster-setup.ps1`
2. Deploy probes: `kubectl apply -f manifests/probes.yaml`
3. Apply monitoring & alerts: `kubectl apply -f manifests/monitoring/`
4. Start Operator: `cd operator-go && go run .`
5. Run full automated fault injection:
   ```bash
   ./fault-injection/inject_faults.sh full-scenario
   ```
6. Confirm both detection and self-healing complete successfully.

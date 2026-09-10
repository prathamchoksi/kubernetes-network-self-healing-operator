# Kubernetes Network Self-Healing Operator

A custom Kubernetes operator built in Go that automatically detects and remediates network-level failures in real-time:

- **CoreDNS Health Monitoring**: Detects DNS resolution failures and latency spikes, triggering automated recovery.
- **NetworkPolicy Reachability Detection**: Detects blocked cross-namespace pod-to-pod communication and automatically restores baseline NetworkPolicies.
- **CNI Node Health Tracking**: Monitors Calico / Flannel pod container restarts across cluster nodes.
- **Full Observability Stack**: Integrated Prometheus rules, Alertmanager webhooks, Loki log aggregation, and Grafana real-time dashboards.
- **Automated Fault Injection & Verification Suite**: Scripts for testing self-healing loops end-to-end.

---

## System Architecture

```
                                  +---------------------------------------+
                                  |    Grafana + Loki Observability       |
                                  |  (Dashboards & Remediation Logs)      |
                                  +-------------------+-------------------+
                                                      ^
                                                      | Metrics & Logs
+----------------------------+    Metrics    +--------+-------------------+
| Custom Python Probes       | ------------> | Prometheus + Alertmanager  |
| (dns-probe & connectivity) |               | (ServiceMonitors & Rules) |
+----------------------------+               +-------------------+-------+
                                                                 |
                                                                 | Webhook Alert HTTP POST (:8080)
                                                                 v
+----------------------------+  K8s API Calls  +-----------------+-------+
|  Test Workloads / Network  | <-------------- |   Go Self-Healing      |
| (nginx, curl, NetPolicies) |                 |   Operator             |
+----------------------------+                 +-------------------------+
```

---

## Project Structure

```
.
├── AI_Used/                    # Documentation on setup and development process
│   ├── IMPLEMENTATION_PLAN.md
│   ├── Project_details.md
│   └── SETUP_SUMMARY.md
└── code/                       # Source code directory
    ├── kind-config.yaml            # KIND 3-node cluster configuration (1 control-plane, 2 workers)
    ├── cluster-setup.ps1           # Automated cluster setup script (Calico/Flannel + Monitoring)
    ├── install-tools.ps1           # Tool installer (Docker, KIND, kubectl, helm)
    ├── manifests/
    │   ├── calico-custom-resources.yaml
    │   ├── operator.yaml           # Deployment and RBAC for Go network operator
    │   ├── probes.yaml             # Deployment and RBAC for Python metrics probes
    │   ├── test-app/
    │   │   └── test-app.yaml       # Test workloads (nginx-server-1, curl-client-1/2)
    │   └── monitoring/             # Monitoring stack resources
    │       ├── alertmanager-config.yaml  # Webhook receiver config (:8080)
    │       ├── alerts.yaml               # Prometheus alert rules
    │       ├── grafana-dashboards.yaml   # Pre-configured Grafana dashboard ConfigMap
    │       └── service-monitors.yaml     # Scrape targets for custom probes
    ├── operator-go/
    │   ├── main.go                 # Go operator entrypoint & HTTP webhook receiver (:8080)
    │   ├── main_test.go            # Go unit tests
    │   └── remediation.go          # K8s API remediation logic (NetworkPolicy, DNS, CNI)
    ├── probes/
    │   ├── Dockerfile
    │   ├── requirements.txt
    │   ├── dns_probe.py            # CoreDNS health probe (exposes port 8000)
    │   └── connectivity_probe.py   # Pod-to-pod connectivity probe (exposes port 8001)
    └── fault-injection/
        └── inject_faults.sh        # Fault injection & automated E2E test runner
```

---

## Quick Start & Setup Guide

### Step 1: Environment Setup

Run PowerShell as **Administrator**:

```powershell
cd code
.\install-tools.ps1
```

Verify required tools:

```powershell
docker --version
kubectl version --client
kind version
helm version
```

### Step 2: Cluster & Stack Bring-up

Run the cluster setup script from the `code` directory:

```powershell
cd code
.\cluster-setup.ps1
```

This script automatically:

1. Creates a 3-node KIND cluster named `k8s-network-healing`.
2. Installs Project Calico CNI.
3. Deploys test applications (`nginx-server-1` in `test-namespace-1`, `curl-client-2` in `test-namespace-2`).
4. Builds and loads probe and operator container images.
5. Deploys `network-operator` and `network-probes`.
6. Installs Prometheus, Alertmanager, Loki, and Grafana.
7. Applies custom ServiceMonitors, Alerting Rules, Webhook configs, and Grafana Dashboards.

### Step 3: Accessing Grafana Dashboard

To open Grafana in your web browser:

1. **Port-Forward Grafana**:
   ```powershell
   kubectl port-forward -n monitoring svc/loki-grafana 3000:80
   ```
2. **Get Grafana Admin Password**:
   In PowerShell:
   ```powershell
   [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String((kubectl get secret -n monitoring loki-grafana -o jsonpath="{.data.admin-password}")))
   ```
3. **Open Grafana**:
   Navigating to `http://localhost:3000` in your browser.
   - **Username**: `admin`
   - **Password**: _(The decoded password from command above)_
   - Go to **Dashboards** $\rightarrow$ **Kubernetes Network Self-Healing Overview**.

---

## Testing & Verification Commands

> **Note for Path Formats**:
>
> - In **Git Bash**: Always use forward slashes `/` (e.g. `./code/fault-injection/inject_faults.sh full-scenario`).
> - In **PowerShell**: Use `bash .\code\fault-injection\inject_faults.sh full-scenario`.

### 1. Automated Full Test Suite (E2E Integration Test)

Run the full automated test scenario:

**Git Bash**:

```bash
./code/fault-injection/inject_faults.sh full-scenario
```

**PowerShell**:

```powershell
bash .\code\fault-injection\inject_faults.sh full-scenario
```

> **Expected Output**: Executes baseline checks, CoreDNS crash recovery, NetworkPolicy blocking/remediation, and CNI node crashes, concluding with:
> `=== ALL SCENARIOS PASSED SUCCESSFULLY ===`

---

### 2. NetworkPolicy Fault Injection & Self-Healing

Apply a blocking NetworkPolicy that cuts off cross-namespace traffic:

**Git Bash**:

```bash
./code/fault-injection/inject_faults.sh apply-bad-policy
```

**PowerShell**:

```powershell
bash .\code\fault-injection\inject_faults.sh apply-bad-policy
```

- **Observe in Grafana**:
  1. Within ~15s, **`Pod-to-Pod Connectivity`** panel turns **RED** (`BLOCKED`).
  2. The Go operator receives the `PodConnectivityBlocked` alert, deletes `block-all-ingress`, and restores `baseline-allow-all`.
  3. Within ~30s total, Grafana turns back to **GREEN** (`CONNECTED`).

---

### 3. CNI Node Container Restart Test

Trigger a CNI container process crash:

**Git Bash**:

```bash
./code/fault-injection/inject_faults.sh kill-cni
```

**PowerShell**:

```powershell
bash .\code\fault-injection\inject_faults.sh kill-cni
```

- **Observe in Grafana**:
  The **`CNI Pod Restarts`** stat card increments by **`1`** (e.g., from `0` to `1`) after `kube-state-metrics` scrapes Kubelet (~15-30s).

---

### 4. CoreDNS Diagnostic Check

Check CoreDNS resolution status:

**Git Bash**:

```bash
./code/fault-injection/inject_faults.sh check-dns
```

**PowerShell**:

```powershell
bash .\code\fault-injection\inject_faults.sh check-dns
```

---

### 5. Running Go Operator Unit Tests

Run the Go unit test suite:

```bash
cd code/operator-go
go test -v ./...
```

> **Expected Output**:
>
> ```text
> === RUN   TestWebhookRejectsGet
> --- PASS: TestWebhookRejectsGet (0.00s)
> === RUN   TestWebhookAcceptsValidAlert
> --- PASS: TestWebhookAcceptsValidAlert (0.00s)
> === RUN   TestCooldownMechanism
> --- PASS: TestCooldownMechanism (0.00s)
> PASS
> ```

---

### 6. Verifying Operator Logs Directly

Inspect live remediation logs from the Go operator pod:

```bash
kubectl logs -n kube-system deployment/network-operator --tail=30
```

> **Expected Log Output**:
>
> ```text
> Received firing alert: PodConnectivityBlocked
> Remediating NetworkPolicy: Restoring baseline allow-all policy...
> Deleting blocking NetworkPolicy block-all-ingress in test-namespace-1
> Restored baseline NetworkPolicy in test-namespace-1
> Restored baseline NetworkPolicy in test-namespace-2
> ```

---

## Self-Healing SLA & Timeline

| Stage            | Component       | Duration | Description                                                                           |
| :--------------- | :-------------- | :------- | :------------------------------------------------------------------------------------ |
| **Detection**    | Python Probes   | ~15s     | Probes detect traffic failure (`connectivity_success = 0`).                           |
| **Evaluation**   | Prometheus Rule | ~15s     | Prometheus verifies `for: 15s` before marking alert as Firing.                        |
| **Dispatch**     | Alertmanager    | ~10s     | Alertmanager buffers alert (`groupWait: 10s`) and sends HTTP POST to `:8080/webhook`. |
| **Remediation**  | Go Operator     | < 1s     | Operator deletes invalid NetworkPolicy & applies `baseline-allow-all`.                |
| **Verification** | Probe + Grafana | ~15s     | Next probe cycle passes (`connectivity_success = 1`), updating Grafana to Green.      |

**Total Self-Healing SLA**: **~50 - 60 seconds** end-to-end.

---

## Troubleshooting

### Nodes or Calico Pods Not Ready

```powershell
kubectl get nodes
kubectl get pods -n calico-system
```

Wait until all nodes are `Ready` and Calico pods show `1/1 Running`.

### Grafana Panels Show "No data"

Ensure probe pods are running:

```powershell
kubectl get pods -n monitoring -l 'app in (dns-probe, connectivity-probe)'
```

If missing, re-apply probes:

```powershell
kubectl apply -f code/manifests/probes.yaml
```

---

## Cluster Tear-Down & Resource Cleanup Guide

When you have finished testing and recording your demo, follow these steps to completely tear down the cluster and free up CPU/RAM resources on your machine so there are no background leaks:

### 1. Stop Active Port-Forwarding Terminals

If you ran `kubectl port-forward` to access Grafana, press **`Ctrl + C`** in your terminal window to terminate the background proxy process.

### 2. Delete the KIND Cluster

Delete the entire local Kubernetes cluster (nodes, containers, and virtual network interfaces):

**Git Bash / PowerShell**:

```bash
kind delete cluster --name k8s-network-healing
```

> **Verification**: Run `kind get clusters` — it should output `No kind clusters found.`

### 3. Prune Unused Docker Cache & Temp Container Data

Clean up temporary Docker images and build layers created during cluster setup:

```bash
docker system prune -f
```

### 4. Close Docker Desktop (Optional)

If you do not need Docker for other work, right-click the Docker Desktop icon in your Windows system tray and select **Quit Docker Desktop** to free up system memory.

---

## License

MIT License - Created for Kubernetes Network Engineering & Self-Healing Automation.

# Kubernetes Network Self-Healing Operator

A custom Kubernetes operator that automatically detects and remediates networking failures:

- CoreDNS health monitoring with auto-restart
- NetworkPolicy reachability detection with policy reapplication
- Fault injection scripts for testing

**Team**: 5 people | **Deadline**: Tuesday (~3 days)

## Project Structure

```
.
├── AI_Used/                    # Documentation on AI contributions and setup
│   ├── IMPLEMENTATION_PLAN.md
│   ├── Project_details.md
│   └── SETUP_SUMMARY.md
├── code/                       # Main source code folder
│   ├── kind-config.yaml            # KIND cluster configuration
│   ├── cluster-setup.ps1           # Automates cluster creation (Calico / Flannel)
│   ├── install-tools.ps1           # Installs Docker, KIND, kubectl, helm
│   ├── manifests/
│   │   ├── calico-custom-resources.yaml
│   │   ├── test-app/
│   │   │   └── test-app.yaml       # Test pods and services
│   │   ├── monitoring/             # Prometheus rules, Alertmanager config, ServiceMonitors
│   │   └── probes.yaml             # In-cluster probe deployments and RBAC
│   ├── operator-go/
│   │   ├── go.mod
│   │   ├── go.sum
│   │   └── main.go                 # Go operator + Alertmanager webhook receiver (:8080)
│   ├── probes/
│   │   ├── Dockerfile
│   │   ├── requirements.txt
│   │   ├── dns_probe.py            # CoreDNS health checking
│   │   └── connectivity_probe.py   # Pod-to-pod connectivity testing
│   └── fault-injection/
│       └── inject_faults.sh        # Fault injection scripts
```

## Quick Start

### Step 0: Environment Setup

**Windows users**: Run as Administrator

```powershell
# 1. Install tools (kubectl, KIND, Docker, Helm)
cd code
.\install-tools.ps1

# 2. For Docker Desktop, download and install manually:
# https://www.docker.com/products/docker-desktop

# 3. Restart PowerShell to update PATH

# 4. Verify installation:
docker --version
kubectl version --client
kind version
helm version
```

### Step 1: Cluster Bring-up

```powershell
cd code
.\cluster-setup.ps1
```

This will:

1. Create a KIND cluster with 3 nodes (1 control-plane, 2 workers)
2. Install Calico CNI (or Flannel) and monitoring stack (Prometheus, Alertmanager, Grafana, Loki)
3. Deploy test apps (nginx server + curl clients)

**Checkpoint**:

- `kubectl get nodes` shows all Ready
- `kubectl get pods -n calico-system` shows Calico Running
- Test app pods are Running in test-namespace-1 and test-namespace-2

### Step 2: Test Cluster Connectivity

```powershell
# Test pod-to-pod communication across namespaces
kubectl exec -it curl-client-2 -n test-namespace-2 -- curl -v http://nginx-server-1.test-namespace-1

# Should see: HTTP/1.1 200 OK
```

## Implementation Phases

### Phase 1: Fault Injection (Step 2)

Build scripts to simulate failures:

- Kill CoreDNS pod
- Apply broken NetworkPolicy

**Location**: `fault-injection/inject_faults.sh`

### Phase 2: Probes & Operator Skeleton (Step 3)

Build independent components:

- **Track A**: DNS probe - monitor CoreDNS latency/crashes
- **Track B**: Connectivity probe - test pod-to-pod traffic
- **Track C**: Operator skeleton - watch CoreDNS pod status

**Location**: `probes/` and `operator-go/`

### Phase 3: Remediation Loops (Steps 4-5)

Wire together detection + fixes:

- CoreDNS crash detection → auto-restart pod
- Connectivity failure → reapply NetworkPolicy

### Phase 4: Integration & Hardening (Step 6)

Run both scenarios, fix edge cases

### Phase 5: Observability & Demo (Steps 7-8)

- Minimal Grafana dashboard (optional)
- Record backup demo video
- Write README and report

## Key Commands

```bash
# Cluster management
kind get clusters                                          # List clusters
kind delete cluster --name k8s-network-healing            # Delete cluster

# Kubernetes inspection
kubectl get nodes                                          # Nodes status
kubectl get pods --all-namespaces                         # All pods
kubectl get pods -n calico-system                         # Calico CNI
kubectl logs -f <pod-name> -n <namespace>                 # Pod logs
kubectl exec -it <pod> -n <ns> -- /bin/sh                 # Pod shell

# Test connectivity
kubectl exec -it curl-client-2 -n test-namespace-2 -- curl http://nginx-server-1.test-namespace-1

# Simulate faults (to be built in Step 2)
./fault-injection/inject_faults.sh kill-coredns           # Kill CoreDNS
./fault-injection/inject_faults.sh apply-bad-policy       # Bad NetworkPolicy
```

## Tech Stack

- **Cluster**: KIND (Kubernetes in Docker)
- **CNI**: Calico / Flannel (configurable)
- **Operator**: Go (`client-go`) + Alertmanager Webhook Receiver
- **Monitoring**: Prometheus + Alertmanager + Probes (HTTP metrics 8000/8001)
- **Observability**: Grafana + Loki
- **Fault Injection**: Bash + kubectl

## Documentation

- **[Project Details](./Project_details.md)** - Full specification, scope decisions, plan
- **[Setup Summary](./SETUP_SUMMARY.md)** - Teammate setup and verification guide

## Common Issues

### Docker not found

```powershell
# Add Docker to PATH after installation, or
# Download Docker Desktop manually from https://www.docker.com/products/docker-desktop
```

### kubectl cluster context

```powershell
# KIND automatically sets up kubeconfig, but you can verify:
kubectl config current-context    # Should show: kind-k8s-network-healing
```

### Calico pods not starting

```powershell
# Wait a bit longer, or check logs:
kubectl logs -n calico-system -l app=calico-node
```

## Status Checklist

- [ ] Docker, KIND, kubectl installed
- [ ] Python 3.10+ with kopf, kubernetes packages
- [ ] KIND cluster up and Calico installed
- [ ] Test app pods running in both namespaces
- [ ] Connectivity test passes (curl across namespaces)
- [ ] Fault injection scripts working
- [ ] DNS probe detecting failures
- [ ] Operator skeleton logging pod status
- [ ] Connectivity probe detecting blocked traffic
- [ ] CoreDNS remediation loop working
- [ ] NetworkPolicy remediation loop working
- [ ] All scenarios integrated and tested
- [ ] Demo video recorded
- [ ] README and report written

---

**Last Updated**: Saturday, ~Day 1 of 3
**Team Size**: 5
**Deadline**: Tuesday

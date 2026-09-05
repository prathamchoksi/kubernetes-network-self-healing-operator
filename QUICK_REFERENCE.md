# Quick Reference Card

## Project Setup Status
- Environment: 90% complete (waiting for Docker)
- Cluster: Ready to create after Docker installation
- All code skeletons: Ready
- Testing framework: Ready

---

## IMMEDIATE NEXT STEPS

### 1. Install Docker (BLOCKING STEP)
```
https://www.docker.com/products/docker-desktop
Download → Run installer → Restart computer → Restart PowerShell
Verify: docker --version
```

### 2. Bring Up Cluster (5 minutes)
```powershell
cd C:\Users\prath\Documents\CN_Project
.\cluster-setup.ps1
```

### 3. Verify Cluster
```bash
kubectl get nodes                    # 3 nodes Ready
kubectl get pods --all-namespaces   # All pods Running
```

---

## Available Commands

### Cluster Management
```bash
kind get clusters                                      # List clusters
kind delete cluster --name k8s-network-healing        # Delete cluster

kubectl cluster-info                                  # Cluster info
kubectl get nodes                                    # Node status
kubectl get pods --all-namespaces                    # All pods
```

### Run Tests/Probes
```bash
# Fault injection (complete test cycle)
./fault-injection/inject_faults.sh full-scenario

# Individual tests
./fault-injection/inject_faults.sh kill-coredns
./fault-injection/inject_faults.sh apply-bad-policy
./fault-injection/inject_faults.sh check-connectivity
./fault-injection/inject_faults.sh check-dns

# Probe monitoring
python probes/dns_probe.py                           # DNS monitoring
python probes/connectivity_probe.py                  # Connectivity monitoring

# Operator
python operator/operator.py                          # Start operator
```

### View Logs
```bash
# Pod logs
kubectl logs -f <pod-name> -n <namespace>

# CoreDNS
kubectl logs -f -n kube-system -l k8s-app=kube-dns

# Test app
kubectl logs -f -n test-namespace-1 <pod-name>
```

### Access Pods
```bash
# Enter test pod shell
kubectl exec -it curl-client-2 -n test-namespace-2 -- /bin/sh

# Run command in pod
kubectl exec curl-client-2 -n test-namespace-2 -- curl http://nginx-server-1.test-namespace-1
```

---

## File Locations

| Component | Files |
|-----------|-------|
| Cluster | kind-config.yaml, cluster-setup.ps1 |
| Operator | operator/operator.py |
| DNS Probe | probes/dns_probe.py |
| Connectivity Probe | probes/connectivity_probe.py |
| Fault Injection | fault-injection/inject_faults.sh |
| Test Workloads | manifests/test-app/test-app.yaml |

---

## Team Roles

| Role | Focus | Files |
|------|-------|-------|
| **Cluster Lead** | Infrastructure, KIND, Calico | kind-config.yaml, cluster-setup.ps1 |
| **DNS/Connectivity Lead** | Monitoring, detection | dns_probe.py, connectivity_probe.py |
| **Operator Lead** | Event watching, wiring | operator.py |
| **Remediation Lead** | Fix logic, anti-flap | operator.py remediation functions |
| **QA/Observability** | Testing, demo, docs | All test scripts, README |

---

## Troubleshooting

**Docker not installing?**  
→ Check Windows version (need Win 10/11)  
→ Enable WSL2 backend  
→ Check disk space (20GB+)

**Cluster won't start?**  
→ Verify Docker is running: `docker ps`  
→ Check resources: `docker system df`

**kubectl command not found?**  
→ Restart PowerShell  
→ Or: `$env:PATH += ";C:\Users\prath\AppData\Local\Programs\KubeTools"`

**Calico pods won't start?**  
→ Wait 2-3 minutes  
→ Check logs: `kubectl logs -n calico-system`

---

## Success Indicators

When cluster is up:
- [ ] 3 nodes showing "Ready"
- [ ] Calico pods all "Running"
- [ ] Test app pods all "Running"
- [ ] curl works across namespaces

When probes run:
- [ ] DNS probe shows healthy status
- [ ] Connectivity probe shows successful connections
- [ ] Fault injection creates detectable failures

When operator runs:
- [ ] Operator detects CoreDNS pod events
- [ ] Operator auto-restarts failed pods
- [ ] Anti-flap prevents continuous restarts

---

## Key Dates

- **TODAY**: Install Docker, bring up cluster
- **DAY 2**: Implement remediation loops
- **DAY 3**: Integration testing + demo

---

## Important URLs

- Docker Desktop: https://www.docker.com/products/docker-desktop
- KIND Docs: https://kind.sigs.k8s.io/
- Calico Docs: https://docs.tigera.io/calico/latest/
- kopf Docs: https://kopf.readthedocs.io/
- Kubernetes Docs: https://kubernetes.io/docs/

---

**Questions?** → See PROJECT_PROGRESS.md or README.md
**Stuck?** → Check INSTALLATION_GUIDE.md or SETUP_STATUS.md

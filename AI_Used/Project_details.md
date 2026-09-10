# Project: Kubernetes Network Self-Healing Operator

## Deadline

**Target: Tuesday** (may need to complete earlier than originally planned Friday deadline). Started planning Saturday. ~3 days total, team of 5.

## Problem Statement

Kubernetes has built-in self-healing (pod restarts, node rescheduling) but does **not** automatically recover from networking-related failures:

- CNI plugin crashes (Calico/Flannel)
- CoreDNS issues (latency, crashes)
- Broken NetworkPolicies blocking legitimate traffic
- General pod-to-pod connectivity failures

This project builds a **custom Kubernetes operator** that detects these networking failures and automatically remediates them (restart pods, reapply NetworkPolicies, DNS failover).

## Scope Decision

The team was able to implement the full scope of the original proposal, successfully integrating advanced features beyond the MVP.

**In scope (Fully Implemented):**

1. CoreDNS health monitoring (pod crash / latency) → auto-restart CoreDNS on failure
2. NetworkPolicy reachability monitoring → detect blocked pod-to-pod traffic → reapply last-known-good NetworkPolicy
3. CNI node crash monitoring → auto-restart Calico/Flannel pods on failure
4. Fault-injection scripts to simulate failures on demand (used for testing AND demo)
5. Grafana dashboard for observability
6. Loki log aggregation and Alertmanager routing
7. Multi-CNI support (Calico and Flannel)

## Tech Stack (final decisions)

- **Cluster**: KIND (not Minikube) — faster startup, easier multi-node
- **CNI**: Calico or Flannel
- **Operator framework**: Go + `client-go` with Alertmanager Webhook Receiver
- **Monitoring**: Prometheus + Alertmanager
- **Dashboards**: Grafana + Loki for logs
- **Fault injection**: Bash scripts using `kubectl delete pod`, `kubectl apply` with a bad NetworkPolicy

## Team Structure (5 people)

1. **Cluster/CNI lead** — KIND setup, Calico install, fault-injection scripts
2. **DNS & connectivity lead** — CoreDNS latency probe, pod-to-pod connectivity probe, NetworkPolicy reachability check
3. **Operator core lead** — kopf operator skeleton, watches CoreDNS pod status / connectivity probe results
4. **Remediation & alerting lead** — remediation actions (restart CoreDNS, reapply NetworkPolicy), anti-flap/cooldown logic
5. **Observability & QA lead** — Grafana dashboard, end-to-end test scenarios, README/report, demo recording

## Repo Structure

```
project/
├── AI_Used/                    # Documentation on AI contributions and setup
│   ├── IMPLEMENTATION_PLAN.md
│   ├── Project_details.md
│   └── SETUP_SUMMARY.md
└── code/                       # Main source code folder
    ├── kind-config.yaml
    ├── cluster-setup.ps1
    ├── install-tools.ps1
    ├── manifests/
    ├── operator-go/
    │   └── main.go             # Go operator + webhook receiver
    ├── probes/
    │   ├── dns_probe.py
    │   └── connectivity_probe.py
    └── fault-injection/
        └── inject_faults.sh
```

## Stepwise Plan (not tied to specific days — work through in order, in parallel where marked)

**Step 0 — Environment setup** _(everyone, do first, together if possible)_

- Install Docker, KIND, kubectl, helm on every machine
- Clone shared repo with the folder structure

**Step 1 — Cluster bring-up** _(together / one person drives, screen-share)_

- Create KIND cluster (3 nodes: 1 control-plane, 2 workers), default CNI disabled
- Install Calico
- Deploy test app (nginx + curl pod in different namespaces) as connectivity targets
- Checkpoint: `kubectl get nodes` shows all Ready, Calico pods Running

**Step 2 — Fault injection scripts** _(build this before/alongside Step 3, others depend on it)_

- Script to kill CoreDNS pod (simulate crash)
- Script to apply a deliberately broken NetworkPolicy (blocks legitimate traffic)
- Checkpoint: both faults can be triggered and manually confirmed (DNS fails, curl fails)

**Step 3 — Parallel track: probes + operator skeleton** _(4 people split here)_

- _Track A_: DNS probe — checks CoreDNS latency/failures on an interval, logs/exposes result
- _Track B_: Connectivity/NetworkPolicy probe — periodic curl across namespaces, logs success/failure
- _Track C_: Operator skeleton — Go app that receives webhooks and logs state changes (no remediation yet)
- Checkpoint: each piece independently detects its failure when the Step 2 scripts are run — nothing wired together yet

**Step 4 — Wire in first remediation (CoreDNS)**

- Operator: on CoreDNS crash/latency detection → delete/restart CoreDNS pod
- Test: run fault injection → confirm operator detects → confirm auto-restart → confirm DNS probe shows recovery
- Checkpoint: full loop works end-to-end for CoreDNS scenario

**Step 5 — Wire in second remediation (NetworkPolicy)**

- Operator: on connectivity probe reporting blocked traffic → reapply last-known-good NetworkPolicy
- Add basic anti-flap/cooldown logic so operator doesn't loop-restart or reapply repeatedly
- Checkpoint: full loop works end-to-end for NetworkPolicy scenario

**Step 6 — Integration & hardening**

- Run both fault scenarios back-to-back, confirm no interference between the two remediation paths
- Fix edge cases (e.g., operator acting on stale state, race conditions between probe and operator)

**Step 7 — Observability polish** _(can run in parallel with Step 6 for one person)_

- Minimal Grafana dashboard: DNS latency panel + connectivity status panel (skip if time-constrained — not blocking)

**Step 8 — Demo + docs**

- Record a backup demo video of both fault→detect→fix loops working (insurance against live demo failure)
- Write README covering architecture, what was built, what was cut and why

**Step 9 — Final buffer**

- Rehearse live demo, fix any last bugs, submit

## Current Progress Checkpoint (update as you go)

- [ ] Cluster up, Calico healthy, test app deployed
- [ ] `inject_faults.sh` can kill CoreDNS and apply a bad NetworkPolicy on demand
- [ ] DNS probe detects failure when CoreDNS is killed
- [ ] Operator skeleton logs "CoreDNS pod down" when watching pod events
- [ ] Connectivity probe detects broken traffic when bad NetworkPolicy is applied
- [ ] CoreDNS remediation loop working end-to-end
- [ ] NetworkPolicy remediation loop working end-to-end
- [ ] Grafana dashboard (optional)
- [ ] Demo video recorded
- [ ] README/report written

## Key Working Principles

- Prefer the simplest thing that demonstrably works over the "correct" full implementation — time is the binding constraint, not sophistication
- Integrate early, don't build in isolation until the end
- Always keep a fallback (e.g., recorded demo video) in case live demo fails
- If asked to expand scope, push back and check against the "explicitly out of scope" list above first

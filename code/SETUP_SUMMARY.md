# Setup Summary

This guide helps each teammate set up and verify the Kubernetes Network Self-Healing Operator project on Windows.

## 1. Install prerequisites

Install and start Docker Desktop:

```powershell
winget install --id Docker.DockerDesktop -e
```

Restart Windows after installation, open Docker Desktop, and wait until it reports that Docker is running.

Install the remaining tools:

```powershell
winget install --id Kubernetes.kubectl -e
winget install --id Kubernetes.kind -e
```

Restart PowerShell so the updated `PATH` is loaded.

Verify the tools:

```powershell
docker --version
docker info
kubectl version --client
kind version
python --version
```

Python 3.10 or newer is required. Install the operator dependencies:

```powershell
python -m pip install --upgrade pip
python -m pip install kopf kubernetes pyyaml
```

## 2. Get the project

```powershell
git clone https://github.com/prathamchoksi/kubernetes-network-self-healing-operator.git
cd kubernetes-network-self-healing-operator
```

If you already cloned it, update it with:

```powershell
git pull origin main
```

## 3. Create the cluster

Run PowerShell from the project directory:

```powershell
.\cluster-setup.ps1
```

The script creates:

- A KIND cluster named `k8s-network-healing`
- One control-plane node and two worker nodes
- Calico as the CNI
- Two test namespaces
- An nginx server and curl clients

The first run can take several minutes while container images are downloaded.

## 4. Verify the setup

All three nodes should be `Ready`:

```powershell
kubectl get nodes
```

Calico should be running:

```powershell
kubectl get pods -n calico-system
```

The test workloads should be running:

```powershell
kubectl get pods -n test-namespace-1
kubectl get pods -n test-namespace-2
```

Test cross-namespace connectivity:

```powershell
kubectl exec curl-client-2 -n test-namespace-2 -- `
  curl --fail --silent --show-error `
  http://nginx-server-1.test-namespace-1.svc.cluster.local/
```

The command should return the nginx welcome page.

## 5. Useful commands

Check the active context:

```powershell
kubectl config current-context
```

Expected context:

```text
kind-k8s-network-healing
```

Inspect all workloads:

```powershell
kubectl get pods --all-namespaces
```

Delete and recreate the local cluster:

```powershell
kind delete cluster --name k8s-network-healing
.\cluster-setup.ps1
```

## 6. Troubleshooting

### Docker command is not found

Restart PowerShell after installing Docker Desktop. If necessary, start Docker Desktop manually and wait for it to finish starting.

### Nodes remain `NotReady`

Check Calico:

```powershell
kubectl get pods -n calico-system
kubectl get tigerastatus
```

Wait until the Calico node pods are `1/1 Running`.

### The cluster already exists

Inspect it first:

```powershell
kind get clusters
kubectl get nodes
```

If it is incomplete, recreate it:

```powershell
kind delete cluster --name k8s-network-healing
.\cluster-setup.ps1
```

### Connectivity fails

Check the nginx endpoint and pod status:

```powershell
kubectl get svc -n test-namespace-1
kubectl get pods -n test-namespace-1 -n test-namespace-2
```

## 7. Current project checkpoint

After successful setup, confirm:

- [ ] Docker Desktop is running
- [ ] `kubectl get nodes` shows three `Ready` nodes
- [ ] Calico pods are running
- [ ] nginx and curl test pods are running
- [ ] Cross-namespace curl returns the nginx page

Once these checks pass, continue with fault injection and probe testing described in `README.md`.

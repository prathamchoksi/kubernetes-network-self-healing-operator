#!/usr/bin/env pwsh
# Kubernetes Network Self-Healing Operator - Cluster Setup

param(
    [ValidateSet("Calico", "Flannel")]
    [string]$CNI = "Calico"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
$KindConfig = Join-Path $ProjectRoot "kind-config.yaml"
$TestAppManifest = Join-Path $ProjectRoot "manifests\test-app\test-app.yaml"
$CalicoCustomResources = Join-Path $ProjectRoot "manifests\calico-custom-resources.yaml"
$FlannelManifest = "https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"
$ClusterName = "k8s-network-healing"

Write-Host "=== Verifying prerequisites ===" -ForegroundColor Cyan
foreach ($cmd in @("docker", "kind", "kubectl", "helm")) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        throw "$cmd not found"
    }
    Write-Host "OK: $cmd" -ForegroundColor Green
}

Write-Host "`n=== Creating KIND cluster ===" -ForegroundColor Cyan
& kind create cluster --config $KindConfig --wait 2m
if ($LASTEXITCODE -ne 0) { throw "KIND cluster creation failed" }

Write-Host "`n=== Waiting for nodes ===" -ForegroundColor Cyan
$attempt = 0
while ($attempt -lt 30) {
    $ready = kubectl get nodes --no-headers 2>$null | Select-String "Ready" | Measure-Object | Select-Object -ExpandProperty Count
    if ($ready -eq 3) {
        Write-Host "All nodes ready" -ForegroundColor Green
        break
    }
    Write-Host "Ready: $ready/3"
    Start-Sleep -Seconds 2
    $attempt++
}

Write-Host "`n=== Node Status ===" -ForegroundColor Cyan
kubectl get nodes

if ($CNI -eq "Calico") {
    Write-Host "`n=== Installing Calico ===" -ForegroundColor Cyan
    kubectl apply --server-side -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml
    Start-Sleep -Seconds 10
    kubectl apply --server-side -f $CalicoCustomResources
    Start-Sleep -Seconds 10

    Write-Host "`n=== Waiting for Calico ===" -ForegroundColor Cyan
    $attempt = 0
    while ($attempt -lt 60) {
        $readyNodes = @(kubectl get nodes --no-headers 2>$null | Select-String " Ready ").Count
        $readyCalicoNodes = @(kubectl get pods -n calico-system -l k8s-app=calico-node --no-headers 2>$null | Select-String "1/1.*Running").Count
        if (($readyNodes -eq 3) -and ($readyCalicoNodes -eq 3)) {
            Write-Host "Calico ready" -ForegroundColor Green
            break
        }
        Write-Host "Ready nodes: $readyNodes/3; Calico nodes: $readyCalicoNodes/3"
        Start-Sleep -Seconds 2
        $attempt++
    }
    if ($attempt -eq 60) { throw "Calico did not become ready within 120 seconds" }
    Write-Host "`n=== Calico Status ===" -ForegroundColor Cyan
    kubectl get pods -n calico-system
}
else {
    Write-Host "`n=== Installing Flannel ===" -ForegroundColor Cyan
    kubectl apply -f $FlannelManifest
    Start-Sleep -Seconds 10

    Write-Host "`n=== Waiting for Flannel ===" -ForegroundColor Cyan
    $attempt = 0
    while ($attempt -lt 60) {
        $readyNodes = @(kubectl get nodes --no-headers 2>$null | Select-String " Ready ").Count
        $readyFlannelNodes = @(kubectl get pods -n kube-flannel -l app=flannel --no-headers 2>$null | Select-String "1/1.*Running").Count
        if (($readyNodes -eq 3) -and ($readyFlannelNodes -eq 3)) {
            Write-Host "Flannel ready" -ForegroundColor Green
            break
        }
        Write-Host "Ready nodes: $readyNodes/3; Flannel nodes: $readyFlannelNodes/3"
        Start-Sleep -Seconds 2
        $attempt++
    }
    if ($attempt -eq 60) { throw "Flannel did not become ready within 120 seconds" }
    Write-Host "`n=== Flannel Status ===" -ForegroundColor Cyan
    kubectl get pods -n kube-flannel
}

Write-Host "`n=== Deploying test app ===" -ForegroundColor Cyan
kubectl apply -f $TestAppManifest
kubectl wait --for=condition=Ready pod/curl-client-2 -n test-namespace-2 --timeout=180s
kubectl wait --for=condition=Available deployment/nginx-server-1 -n test-namespace-1 --timeout=180s

Write-Host "`n=== Test app status ===" -ForegroundColor Cyan
kubectl get pods -n test-namespace-1
kubectl get pods -n test-namespace-2

Write-Host "`n=== Building and Loading Custom Images ===" -ForegroundColor Cyan
# Build and load probes
docker build -t network-probes:latest (Join-Path $ProjectRoot "probes")
kind load docker-image network-probes:latest --name $ClusterName

# Build and load operator
docker build -t network-operator:latest (Join-Path $ProjectRoot "operator-go")
kind load docker-image network-operator:latest --name $ClusterName

Write-Host "`n=== Deploying Probes and Operator ===" -ForegroundColor Cyan
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f (Join-Path $ProjectRoot "manifests\probes.yaml")
kubectl apply -f (Join-Path $ProjectRoot "manifests\operator.yaml")

Write-Host "`n=== Installing Monitoring Stack (Prometheus, Alertmanager, Grafana, Loki) ===" -ForegroundColor Cyan
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack (Prometheus + Alertmanager)
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace --set alertmanager.enabled=true --set grafana.enabled=false

# Install Loki stack (Loki + Promtail + Grafana with dashboard sidecar enabled)
helm upgrade --install loki grafana/loki-stack --namespace monitoring --create-namespace --set grafana.enabled=true,grafana.sidecar.dashboards.enabled=true,prometheus.enabled=true,prometheus.isDefault=false,prometheus.url=http://prometheus-kube-prometheus-prometheus.monitoring:9090

Write-Host "`n=== Applying Custom Monitoring Configurations ===" -ForegroundColor Cyan
kubectl apply -f (Join-Path $ProjectRoot "manifests\monitoring\service-monitors.yaml")
kubectl apply -f (Join-Path $ProjectRoot "manifests\monitoring\alerts.yaml")
kubectl apply -f (Join-Path $ProjectRoot "manifests\monitoring\alertmanager-config.yaml")
kubectl apply -f (Join-Path $ProjectRoot "manifests\monitoring\grafana-dashboards.yaml")

Write-Host "`n=== CLUSTER READY ===" -ForegroundColor Green
Write-Host "Cluster: $ClusterName"
Write-Host "Nodes: 3 (1 control-plane, 2 workers)"
Write-Host "CNI: $CNI"

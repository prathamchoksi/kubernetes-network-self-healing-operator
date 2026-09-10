# Automated installation of Docker, KIND, and kubectl for Windows
# Run this script as Administrator

param(
    [switch]$SkipDocker = $false,
    [switch]$SkipKind = $false,
    [switch]$SkipKubectl = $false
)

$ErrorActionPreference = "Continue"

function Test-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal $currentUser
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Add-ToPath {
    param([string]$Path)
    $currentPath = $env:PATH
    if ($currentPath -notlike "*$Path*") {
        $env:PATH += ";$Path"
        [Environment]::SetEnvironmentVariable("PATH", $env:PATH, [EnvironmentVariableTarget]::Machine)
        Write-Host "Added $Path to PATH" -ForegroundColor Green
    }
}

Write-Host "=== Kubernetes Tools Installer ===" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Admin)) {
    Write-Host "ERROR: This script must be run as Administrator" -ForegroundColor Red
    Write-Host "Please right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

# Check if Chocolatey is installed
$choco = Get-Command choco -ErrorAction SilentlyContinue
if ($choco) {
    Write-Host "Chocolatey found, using it for installation" -ForegroundColor Green
    
    if (-not $SkipDocker) {
        Write-Host "`nInstalling Docker Desktop..." -ForegroundColor Cyan
        choco install docker-desktop -y
    }
    
    if (-not $SkipKubectl) {
        Write-Host "`nInstalling kubectl..." -ForegroundColor Cyan
        choco install kubernetes-cli -y
    }
    
    if (-not $SkipKind) {
        Write-Host "`nInstalling KIND..." -ForegroundColor Cyan
        choco install kind -y
    }
} else {
    Write-Host "Chocolatey not found. Using manual installation..." -ForegroundColor Yellow
    
    $installDir = "C:\Program Files\KubeTools"
    if (-not (Test-Path $installDir)) {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        Write-Host "Created $installDir" -ForegroundColor Green
    }
    
    if (-not $SkipKubectl) {
        Write-Host "`nDownloading kubectl..." -ForegroundColor Cyan
        $kubectlUrl = "https://dl.k8s.io/release/v1.28.3/bin/windows/amd64/kubectl.exe"
        $kubectlPath = Join-Path $installDir "kubectl.exe"
        try {
            Invoke-WebRequest -Uri $kubectlUrl -OutFile $kubectlPath -UseBasicParsing
            Write-Host "kubectl downloaded" -ForegroundColor Green
            Add-ToPath $installDir
        } catch {
            Write-Host "Failed to download kubectl: $_" -ForegroundColor Red
        }
    }
    
    if (-not $SkipKind) {
        Write-Host "`nDownloading KIND..." -ForegroundColor Cyan
        $kindUrl = "https://kind.sigs.k8s.io/dl/v0.20.0/kind-windows-amd64"
        $kindPath = Join-Path $installDir "kind.exe"
        try {
            Invoke-WebRequest -Uri $kindUrl -OutFile $kindPath -UseBasicParsing
            Write-Host "KIND downloaded" -ForegroundColor Green
            Add-ToPath $installDir
        } catch {
            Write-Host "Failed to download KIND: $_" -ForegroundColor Red
        }
    }
    
    if (-not $SkipDocker) {
        Write-Host "`nDocker Desktop must be installed manually" -ForegroundColor Yellow
        Write-Host "Download from: https://www.docker.com/products/docker-desktop" -ForegroundColor Cyan
        Write-Host "After installation, restart PowerShell" -ForegroundColor Yellow
    }
}

Write-Host "`n=== Verification ===" -ForegroundColor Cyan
Write-Host "Checking installation..." -ForegroundColor Yellow
$tools = @("docker", "kubectl", "kind")
foreach ($tool in $tools) {
    $cmd = Get-Command $tool -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Host "OK: $tool is installed" -ForegroundColor Green
        & $tool --version 2>$null
    } else {
        Write-Host "MISSING: $tool not found" -ForegroundColor Red
    }
}

Write-Host "`n=== Next Steps ===" -ForegroundColor Cyan
Write-Host "1. If Docker is not installed, download and run Docker Desktop installer"
Write-Host "2. Restart PowerShell to reload PATH"
Write-Host "3. Run: cd C:\Users\prath\Documents\CN_Project"
Write-Host "4. Run: .\cluster-setup.ps1" -ForegroundColor Yellow

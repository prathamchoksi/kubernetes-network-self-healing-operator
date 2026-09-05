# Installation Guide for Kubernetes Network Self-Healing Operator
# Windows 10/11 Setup for Docker, KIND, and kubectl

## Prerequisites Check
# Run PowerShell as Administrator and execute this script

## Step 1: Install Docker Desktop
# Method 1: Using Chocolatey (if installed)
# choco install docker-desktop -y

# Method 2: Download from Docker
# https://www.docker.com/products/docker-desktop
# Run the installer and follow the prompts
# This will automatically set up Docker and add it to PATH

## Step 2: Install kubectl
# Using Chocolatey:
# choco install kubernetes-cli -y

# Or using curl:
# curl.exe -L "https://dl.k8s.io/release/$(curl.exe -L -s https://dl.k8s.io/release/stable.txt)/bin/windows/amd64/kubectl.exe" -o kubectl.exe
# Add kubectl.exe to a folder in PATH (e.g., C:\Program Files\kubectl\)

## Step 3: Install KIND
# Using Chocolatey:
# choco install kind -y

# Or download directly:
# curl.exe -Lo kind-windows-amd64.exe https://kind.sigs.k8s.io/dl/v0.20.0/kind-windows-amd64
# Rename to kind.exe and add to PATH (e.g., C:\Program Files\kind\)

## Step 4: Verify Installation
# Open PowerShell and run:
# docker --version
# kubectl version --client
# kind version

## Manual Installation Steps for Windows:

### Docker Desktop:
1. Download from https://www.docker.com/products/docker-desktop
2. Run installer (Docker Desktop for Windows)
3. Accept license agreement
4. Check "Install required Windows components"
5. Restart computer when prompted
6. Verify: docker --version

### kubectl:
1. Download from https://kubernetes.io/docs/tasks/tools/
   OR use: 
   curl.exe -L "https://dl.k8s.io/release/v1.28.3/bin/windows/amd64/kubectl.exe" -o kubectl.exe
2. Move to C:\Program Files\kubectl\
3. Add C:\Program Files\kubectl\ to PATH environment variable
4. Verify: kubectl version --client

### KIND:
1. Download from https://kind.sigs.k8s.io/dl/v0.20.0/kind-windows-amd64
2. Rename to kind.exe
3. Move to C:\Program Files\kind\
4. Add C:\Program Files\kind\ to PATH environment variable
5. Verify: kind version

## PATH Configuration:
1. Search "Environment Variables" in Windows
2. Click "Edit the system environment variables"
3. Click "Environment Variables" button
4. Under "System variables", select "Path" and click "Edit"
5. Add these paths (if not already present):
   - C:\Program Files\Docker\Docker\resources\bin
   - C:\Program Files\kubectl
   - C:\Program Files\kind
6. Click OK and restart PowerShell

## Verification Script:
After installation, run this in PowerShell to verify everything is installed:

docker --version
kubectl version --client
kind version

If all three commands work, you're ready to proceed with cluster setup!

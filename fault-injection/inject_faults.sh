#!/bin/bash
# Kubernetes Network Self-Healing Operator - Fault Injection Script
# Simulates networking failures for testing the operator's remediation capabilities

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Kubernetes Network Self-Healing Operator - Fault Injection ===${NC}\n"

# Verify kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}ERROR: kubectl not found${NC}"
    exit 1
fi

# Get cluster context
CONTEXT=$(kubectl config current-context)
echo -e "${GREEN}Connected to cluster: $CONTEXT${NC}\n"

# Function: Show usage
show_usage() {
    echo "Usage: $0 <fault-type>"
    echo ""
    echo "Fault types:"
    echo "  kill-coredns              - Kill CoreDNS pod to simulate DNS failure"
    echo "  restart-coredns           - Trigger CoreDNS pod restart detection"
    echo "  apply-bad-policy          - Apply a NetworkPolicy that blocks all traffic"
    echo "  remove-bad-policy         - Remove the blocking NetworkPolicy"
    echo "  check-connectivity        - Test pod-to-pod connectivity"
    echo "  check-dns                 - Test DNS resolution"
    echo "  status                    - Show cluster and pod status"
    echo "  full-scenario             - Run complete test scenario"
    echo ""
}

# Function: Kill CoreDNS pod
kill_coredns() {
    echo -e "${YELLOW}[Fault] Killing CoreDNS pod...${NC}"
    POD=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$POD" ]; then
        echo -e "${RED}No CoreDNS pod found${NC}"
        return 1
    fi
    echo "Deleting pod: $POD"
    kubectl delete pod $POD -n kube-system --grace-period=0 --force 2>/dev/null || true
    echo -e "${GREEN}Pod deleted${NC}"
    echo "Kubernetes will automatically restart it..."
    sleep 2
    echo "Waiting for new CoreDNS pod to start..."
    sleep 5
}

# Function: Restart CoreDNS detection (gentle trigger)
restart_coredns() {
    echo -e "${YELLOW}[Fault] Triggering CoreDNS pod restart detection...${NC}"
    POD=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$POD" ]; then
        echo -e "${RED}No CoreDNS pod found${NC}"
        return 1
    fi
    # This just reports the current status without forcefully killing
    echo "Current CoreDNS pod status:"
    kubectl get pod $POD -n kube-system
}

# Function: Apply bad NetworkPolicy
apply_bad_policy() {
    echo -e "${YELLOW}[Fault] Applying blocking NetworkPolicy...${NC}"
    
    # Create namespace if needed
    kubectl create namespace test-namespace-1 --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1 || true
    
    # Apply NetworkPolicy that blocks all traffic
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: block-all-ingress
  namespace: test-namespace-1
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress: []
EOF
    
    echo -e "${GREEN}NetworkPolicy applied${NC}"
    echo "All ingress traffic to pods in test-namespace-1 is now blocked"
    sleep 2
}

# Function: Remove bad NetworkPolicy
remove_bad_policy() {
    echo -e "${YELLOW}[Fix] Removing blocking NetworkPolicy...${NC}"
    
    kubectl delete networkpolicy block-all-ingress -n test-namespace-1 2>/dev/null || true
    
    echo -e "${GREEN}NetworkPolicy removed${NC}"
    echo "Traffic should be restored"
    sleep 2
}

# Function: Test connectivity
check_connectivity() {
    echo -e "${YELLOW}[Test] Checking pod-to-pod connectivity...${NC}"
    
    SOURCE_POD="curl-client-2"
    SOURCE_NS="test-namespace-2"
    TARGET="nginx-server-1.test-namespace-1"
    
    echo "Source: $SOURCE_POD (namespace: $SOURCE_NS)"
    echo "Target: $TARGET"
    echo ""
    
    # Check if source pod exists
    if ! kubectl get pod $SOURCE_POD -n $SOURCE_NS &> /dev/null; then
        echo -e "${RED}Source pod not found${NC}"
        return 1
    fi
    
    # Test connectivity with curl
    echo "Running: curl http://$TARGET"
    kubectl exec -it $SOURCE_POD -n $SOURCE_NS -- curl -v http://$TARGET 2>&1 | tail -20
}

# Function: Test DNS
check_dns() {
    echo -e "${YELLOW}[Test] Checking DNS resolution...${NC}"
    
    POD="curl-client-2"
    NS="test-namespace-2"
    DOMAIN="kubernetes.default.svc.cluster.local"
    
    echo "Testing DNS from pod: $POD (namespace: $NS)"
    echo "Domain to resolve: $DOMAIN"
    echo ""
    
    # Test nslookup inside pod
    echo "Running: nslookup"
    kubectl exec -it $POD -n $NS -- nslookup $DOMAIN
}

# Function: Show status
show_status() {
    echo -e "${BLUE}=== Cluster Status ===${NC}"
    echo ""
    echo -e "${YELLOW}Nodes:${NC}"
    kubectl get nodes
    echo ""
    
    echo -e "${YELLOW}CoreDNS Pods:${NC}"
    kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
    echo ""
    
    echo -e "${YELLOW}Calico Pods:${NC}"
    kubectl get pods -n calico-system -o wide
    echo ""
    
    echo -e "${YELLOW}Test App Pods:${NC}"
    kubectl get pods -n test-namespace-1 -n test-namespace-2 --all-namespaces
    echo ""
    
    echo -e "${YELLOW}NetworkPolicies:${NC}"
    kubectl get networkpolicy --all-namespaces
}

# Function: Full scenario test
full_scenario() {
    echo -e "${BLUE}=== Running Full Test Scenario ===${NC}\n"
    
    # Step 1: Show initial status
    echo -e "${YELLOW}Step 1: Initial status${NC}"
    show_status
    sleep 3
    
    # Step 2: Check connectivity before fault
    echo -e "\n${YELLOW}Step 2: Testing connectivity before fault${NC}"
    check_connectivity
    sleep 3
    
    # Step 3: Inject CoreDNS fault
    echo -e "\n${YELLOW}Step 3: Injecting CoreDNS fault${NC}"
    kill_coredns
    sleep 10
    
    # Step 4: Check CoreDNS recovery
    echo -e "\n${YELLOW}Step 4: Checking CoreDNS recovery${NC}"
    show_status | grep -A 5 "CoreDNS"
    sleep 3
    
    # Step 5: Test connectivity after DNS recovery
    echo -e "\n${YELLOW}Step 5: Testing connectivity after DNS recovery${NC}"
    check_connectivity
    sleep 3
    
    # Step 6: Inject NetworkPolicy fault
    echo -e "\n${YELLOW}Step 6: Injecting NetworkPolicy fault${NC}"
    apply_bad_policy
    sleep 5
    
    # Step 7: Verify connectivity is blocked
    echo -e "\n${YELLOW}Step 7: Verifying connectivity is blocked${NC}"
    check_connectivity || echo "Connection blocked as expected"
    sleep 3
    
    # Step 8: Remove bad policy
    echo -e "\n${YELLOW}Step 8: Removing bad NetworkPolicy${NC}"
    remove_bad_policy
    sleep 5
    
    # Step 9: Verify connectivity is restored
    echo -e "\n${YELLOW}Step 9: Verifying connectivity is restored${NC}"
    check_connectivity
    sleep 3
    
    echo -e "\n${GREEN}=== Full Scenario Complete ===${NC}"
}

# Parse arguments
FAULT_TYPE="${1:-}"

case "$FAULT_TYPE" in
    kill-coredns)
        kill_coredns
        ;;
    restart-coredns)
        restart_coredns
        ;;
    apply-bad-policy)
        apply_bad_policy
        ;;
    remove-bad-policy)
        remove_bad_policy
        ;;
    check-connectivity)
        check_connectivity
        ;;
    check-dns)
        check_dns
        ;;
    status)
        show_status
        ;;
    full-scenario)
        full_scenario
        ;;
    *)
        show_usage
        exit 1
        ;;
esac

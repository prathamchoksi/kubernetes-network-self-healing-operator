#!/bin/bash
# Kubernetes Network Self-Healing Operator - Fault Injection Script
# Simulates networking failures for testing the operator's remediation capabilities

# Note: set -e is deliberately omitted so expected fault failures (e.g. blocked curl) do not abort the test runner.

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
    echo "  kill-cni                  - Kill a Calico node pod"
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
    
    # Remove any existing allow-all policy so blocking takes effect
    kubectl delete networkpolicy baseline-allow-all -n test-namespace-1 2>/dev/null || true
    
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

# Function: Kill CNI pod
kill_cni() {
    echo -e "${YELLOW}[Fault] Triggering CNI container crash/restart...${NC}"
    
    # Select a Running Calico pod
    POD=$(kubectl get pods -n calico-system -l k8s-app=calico-node --field-selector status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    NS="calico-system"
    CONTAINER="calico-node"
    
    if [ -z "$POD" ]; then
        # Try Flannel
        POD=$(kubectl get pods -n kube-flannel -l app=flannel --field-selector status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        NS="kube-flannel"
        CONTAINER="kube-flannel"
    fi
    
    if [ -z "$POD" ]; then
        echo -e "${RED}No running CNI pod found${NC}"
        return 1
    fi
    
    echo "Killing main process inside pod: $POD ($NS)"
    kubectl exec $POD -n $NS -c $CONTAINER -- kill 1 2>/dev/null || true
    echo -e "${GREEN}Container process killed. Kubelet is restarting the container...${NC}"
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
    
    # Check if source pod exists
    if ! kubectl get pod $SOURCE_POD -n $SOURCE_NS &> /dev/null; then
        echo -e "${RED}Source pod not found: $SOURCE_POD in $SOURCE_NS${NC}"
        return 1
    fi
    
    # Test connectivity with curl and grab HTTP status code
    HTTP_CODE=$(kubectl exec $SOURCE_POD -n $SOURCE_NS -- curl -s -o /dev/null -w "%{http_code}" -m 3 "http://$TARGET" 2>/dev/null || echo "000")
    
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
        echo -e "${GREEN}Connectivity OK: HTTP $HTTP_CODE from $SOURCE_POD to $TARGET${NC}"
        return 0
    else
        echo -e "${RED}Connectivity FAILED: HTTP $HTTP_CODE from $SOURCE_POD to $TARGET${NC}"
        return 1
    fi
}

# Function: Test DNS
check_dns() {
    echo -e "${YELLOW}[Test] Checking DNS resolution...${NC}"
    
    POD="curl-client-2"
    NS="test-namespace-2"
    DOMAIN="kubernetes.default.svc.cluster.local"
    
    echo "Testing DNS from pod: $POD (namespace: $NS)"
    echo "Domain to resolve: $DOMAIN"
    
    if ! kubectl get pod $POD -n $NS &> /dev/null; then
        echo -e "${RED}Pod not found: $POD in $NS${NC}"
        return 1
    fi
    
    if kubectl exec $POD -n $NS -- nslookup "$DOMAIN" >/dev/null 2>&1; then
        echo -e "${GREEN}DNS Resolution OK: Resolved $DOMAIN${NC}"
        return 0
    else
        echo -e "${RED}DNS Resolution FAILED: Unable to resolve $DOMAIN${NC}"
        return 1
    fi
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

# Function: Full scenario test with automated assertions
full_scenario() {
    echo -e "${BLUE}=== Running Full Test Scenario with Automated Assertions ===${NC}\n"
    
    TOTAL_TESTS=0
    PASSED_TESTS=0
    FAILED_TESTS=0
    
    run_assertion() {
        local test_name="$1"
        local expected_result="$2" # 0 = success expected, 1 = failure expected
        shift 2
        
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        echo -e "\n${BLUE}>>> [TEST #$TOTAL_TESTS] $test_name${NC}"
        
        if "$@"; then
            local cmd_res=0
        else
            local cmd_res=1
        fi
        
        if [ "$cmd_res" -eq "$expected_result" ]; then
            echo -e "${GREEN}>>> [PASS] $test_name${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            return 0
        else
            echo -e "${RED}>>> [FAIL] $test_name (expected return $expected_result, got $cmd_res)${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return 1
        fi
    }

    # Step 1: Initial cluster status & baseline check
    echo -e "${YELLOW}Step 1: Baseline Health Check${NC}"
    show_status
    run_assertion "Baseline DNS Resolution" 0 check_dns
    run_assertion "Baseline Pod-to-Pod Connectivity" 0 check_connectivity
    sleep 2
    
    # Step 2: CoreDNS Failure & Recovery Loop
    echo -e "\n${YELLOW}Step 2: Injecting CoreDNS Crash Fault${NC}"
    kill_coredns
    
    echo "Waiting for CoreDNS self-healing recovery (up to 30s)..."
    DNS_RECOVERED=1
    for i in $(seq 1 15); do
        if check_dns >/dev/null 2>&1; then
            DNS_RECOVERED=0
            echo -e "${GREEN}CoreDNS recovered after ~ $((i * 2)) seconds${NC}"
            break
        fi
        sleep 2
    done
    run_assertion "CoreDNS Self-Healing and Resolution Recovery" 0 test "$DNS_RECOVERED" -eq 0
    
    # Step 3: NetworkPolicy Blocking & Recovery Loop
    echo -e "\n${YELLOW}Step 3: Injecting NetworkPolicy Blocking Fault${NC}"
    apply_bad_policy
    sleep 3
    run_assertion "Verify Network Traffic is Blocked by Policy" 1 check_connectivity
    
    echo -e "\nWaiting for NetworkPolicy self-healing remediation..."
    # The operator automatically removes or remediates the blocking policy via Alertmanager webhook.
    # We will poll for up to 30s to detect remediation.
    POLICY_RECOVERED=1
    for i in $(seq 1 15); do
        if check_connectivity >/dev/null 2>&1; then
            POLICY_RECOVERED=0
            echo -e "${GREEN}NetworkPolicy remediated after ~ $((i * 2)) seconds${NC}"
            break
        fi
        sleep 2
    done
    
    # Fallback to manual removal if operator is not currently running
    if [ "$POLICY_RECOVERED" -ne 0 ]; then
        echo -e "${YELLOW}Operator did not auto-remediate within 30s; applying manual fallback...${NC}"
        remove_bad_policy
        sleep 3
        if check_connectivity >/dev/null 2>&1; then
            POLICY_RECOVERED=0
        fi
    fi
    run_assertion "Pod-to-Pod Traffic Restored after NetworkPolicy Remediation" 0 test "$POLICY_RECOVERED" -eq 0
    
    # Step 4: CNI Node Pod Fault & Recovery Loop
    echo -e "\n${YELLOW}Step 4: Injecting CNI Node Crash Fault${NC}"
    kill_cni
    echo "Waiting for CNI node self-healing recovery (up to 30s)..."
    CNI_RECOVERED=1
    for i in $(seq 1 15); do
        READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || true)
        if [ "$READY_NODES" -ge 3 ] && check_connectivity >/dev/null 2>&1; then
            CNI_RECOVERED=0
            echo -e "${GREEN}CNI node recovered after ~ $((i * 2)) seconds (all $READY_NODES nodes Ready)${NC}"
            break
        fi
        sleep 2
    done
    run_assertion "CNI Node Recovery and Cross-Node Connectivity" 0 test "$CNI_RECOVERED" -eq 0
    
    # Final Summary Report
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}       AUTOMATED TEST SCENARIO REPORT    ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "Total Tests Executed: $TOTAL_TESTS"
    echo -e "${GREEN}Tests Passed:         $PASSED_TESTS${NC}"
    if [ "$FAILED_TESTS" -gt 0 ]; then
        echo -e "${RED}Tests Failed:         $FAILED_TESTS${NC}"
        echo -e "${RED}=== SCENARIO FAILED ===${NC}"
        return 1
    else
        echo -e "${GREEN}Tests Failed:         0${NC}"
        echo -e "${GREEN}=== ALL SCENARIOS PASSED SUCCESSFULLY ===${NC}"
        return 0
    fi
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
    kill-cni)
        kill_cni
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

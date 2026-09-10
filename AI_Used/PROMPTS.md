# AI Prompts and Iterations

We used AI heavily to generate our codebase based on our parallel development plan. Below is a record of the key prompts we used and how we integrated the results to build the final system.

### Interaction 1: Operator Webhook Foundation

**Prompt (to Google Antigravity):**

> "Write a basic Go HTTP server that acts as a Kubernetes webhook receiver. It needs to listen on port 8080 and accept POST requests."

**Outcome & Integration:** The AI provided the initial Go server boilerplate. We integrated this into our `main.go` file and verified it could receive external requests.

### Interaction 2: Parsing Alertmanager Payloads

**Prompt (to Google Antigravity):**

> "Update the Go HTTP server to parse incoming JSON payloads from Prometheus Alertmanager. Define the necessary Go structs to extract the 'alertname' and 'status' fields."

**Outcome & Integration:** The AI generated the struct definitions. We added them to our code and tested the parsing by sending mock Alertmanager JSON payloads via curl.

### Interaction 3: Fixing RBAC Permissions

**Prompt (to Google Antigravity):**

> "Our Go operator is failing with this error: `namespaces "kube-system" is forbidden: User "system:serviceaccount:default:self-healing-operator" cannot get resource "deployments" in API group "apps"`. Generate the Kubernetes YAML for a ClusterRole to fix this."

**Outcome & Integration:** The AI provided the necessary RBAC YAML files. We deployed them to our cluster and verified the operator had the correct permissions to modify resources.

### Interaction 4: CNI Remediation Logic

**Prompt (to Google Antigravity):**

> "Add a function to the Go operator using `client-go`. If the alert name is `CNIPodCrash`, it should restart the Calico or Flannel daemonset pods in the `kube-system` namespace."

**Outcome & Integration:** The AI generated the Kubernetes API call logic. We integrated this function and tested it by manually deleting a Calico pod.

### Interaction 5: NetworkPolicy Remediation Logic

**Prompt (to Google Antigravity):**

> "Add another function using `client-go` for when the alert `PodConnectivityBlocked` fires. The function should find and delete any recently created NetworkPolicy in the `default` namespace that drops traffic."

**Outcome & Integration:** The AI wrote the deletion logic. We integrated this into the main webhook handler loop to complete the operator's self-healing capabilities.

### Interaction 6: Python Metric Probes

**Prompt (to Google Antigravity):**

> "Write two Python scripts, `dns_probe.py` and `connectivity_probe.py`. They should use `prometheus_client` to expose custom metrics on ports 8000 and 8001 indicating DNS latency and ping success rates."

**Outcome & Integration:** The AI provided the Python scripts. We ran them locally to verify the metrics were correctly exposed on the localhost ports.

### Interaction 7: Containerizing the Probes

**Prompt (to Google Antigravity):**

> "Write a Dockerfile to package the two Python probe scripts along with their `prometheus_client` dependencies. Also generate the Kubernetes `Deployment` manifests to run them."

**Outcome & Integration:** The AI provided the Dockerfile and YAML manifests. We built the image, sideloaded it into our local KIND cluster, and deployed the probes.

### Interaction 8: Configuring ServiceMonitors

**Prompt (to Google Antigravity):**

> "Generate the Kubernetes `ServiceMonitor` YAML custom resources required for Prometheus to continuously scrape the Python probes on ports 8000 and 8001."

**Outcome & Integration:** The AI generated the custom resources. We applied them to the cluster and checked the Prometheus targets UI to verify the probes were being actively scraped.

### Interaction 9: PromQL Alerting Rules

**Prompt (to Google Antigravity):**

> "Write a PromQL rule for our `alerts.yaml` file. It should trigger a `CNIPodCrash` alert if the metric `kube_pod_container_status_restarts_total` for Flannel or Calico pods increases over a 2-minute window."

**Outcome & Integration:** The AI provided the query using the `increase()` function. We added this to our Prometheus configuration and tested it against our simulated traffic.

### Interaction 10: Fault Injection and Dashboards

**Prompt (to Google Antigravity):**

> "Update our `inject_faults.sh` script to include a `kill-cni` command that deletes `calico-node` pods. Then, create a Kubernetes ConfigMap containing a Grafana JSON dashboard that visualizes our probe metrics."

**Outcome & Integration:** The AI provided the bash commands and the dashboard ConfigMap. We deployed the dashboard and used the fault script to validate the operator's end-to-end self-healing cycle.

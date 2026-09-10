# AI Tools Used

Our team used AI tools primarily for generating code and configuration files, allowing us to focus on the deployment and testing aspects of the project.

### 1. Google Antigravity

- **Code Generation:** We used Antigravity as our primary AI coding assistant to write the Go HTTP server, Python probe scripts, and Kubernetes YAML manifests.
- **Debugging:** We provided Antigravity with cluster error logs (like RBAC failures) to get explanations and fixes.
- **PromQL & Refactoring:** We used it to generate our Prometheus alerting rules and refactor our Go code (e.g., adding concurrency controls like `sync.RWMutex`).

### 2. GitHub Copilot

- **IDE Assistance:** We used Copilot in VS Code for autocompleting minor syntax adjustments when modifying the generated scripts locally.

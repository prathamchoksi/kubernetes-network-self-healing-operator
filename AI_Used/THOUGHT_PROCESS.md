# AI Integration and Thought Process

Our team built a Kubernetes Self-Healing Operator for our Computer Networks course. We decided to use AI tools to generate the majority of our code, allowing us to focus on system setup, integration, and testing.

### Our Process

1. **System Setup:** We set up a local KIND cluster and configured the necessary monitoring tools (Prometheus, Alertmanager, Grafana).
2. **Code Generation:** We used AI to generate the Go code for the operator, the Python probes, and the Kubernetes manifests.
3. **Integration and Testing:** Our primary effort went into making these generated components work together. We ran the generated code, checked the logs for errors, and re-prompted the AI to fix issues like RBAC permissions and state management.
4. **Verification:** We manually tested the system by simulating network failures to ensure the operator responded correctly based on the AI-generated logic.

By using AI for code generation, we were able to complete the project requirements while gaining practical experience in deploying and debugging Kubernetes resources.

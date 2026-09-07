package main

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
)

type Alert struct {
	Status      string            `json:"status"`
	Labels      map[string]string `json:"labels"`
	Annotations map[string]string `json:"annotations"`
}

type AlertmanagerWebhook struct {
	Receiver string  `json:"receiver"`
	Status   string  `json:"status"`
	Alerts   []Alert `json:"alerts"`
}

var (
	clientset     *kubernetes.Clientset
	cooldownCache sync.Map
	cooldownTime  = 60 * time.Second
)

func main() {
	log.Println("Starting Self-Healing Operator Webhook Receiver...")

	var err error
	clientset, err = buildClientset()
	if err != nil {
		log.Fatalf("Failed to create clientset: %v", err)
	}

	http.HandleFunc("/webhook", handleWebhook)
	log.Println("Listening on :8080...")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

func buildClientset() (*kubernetes.Clientset, error) {
	config, err := rest.InClusterConfig()
	if err != nil {
		log.Println("Not running in cluster, falling back to local kubeconfig...")
		rules := clientcmd.NewDefaultClientConfigLoadingRules()
		kubeconfig := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(rules, &clientcmd.ConfigOverrides{})
		config, err = kubeconfig.ClientConfig()
		if err != nil {
			return nil, err
		}
	}
	return kubernetes.NewForConfig(config)
}

func handleWebhook(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var webhook AlertmanagerWebhook
	if err := json.NewDecoder(r.Body).Decode(&webhook); err != nil {
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	for _, alert := range webhook.Alerts {
		if alert.Status == "firing" {
			alertName := alert.Labels["alertname"]
			log.Printf("Received firing alert: %s", alertName)
			handleAlert(alertName, alert)
		}
	}

	w.WriteHeader(http.StatusOK)
}

func handleAlert(alertName string, alert Alert) {
	// Check cooldown to prevent flapping
	if lastTrigger, ok := cooldownCache.Load(alertName); ok {
		if time.Since(lastTrigger.(time.Time)) < cooldownTime {
			log.Printf("Alert %s is in cooldown. Skipping remediation.", alertName)
			return
		}
	}

	// Update cooldown cache
	cooldownCache.Store(alertName, time.Now())

	switch alertName {
	case "DNSResolutionFailed", "DNSLatencyHigh":
		remediateDNS()
	case "PodConnectivityBlocked":
		remediateNetworkPolicy()
	case "CNIPodCrash":
		remediateCNI()
	default:
		log.Printf("Unknown alert received: %s", alertName)
	}
}

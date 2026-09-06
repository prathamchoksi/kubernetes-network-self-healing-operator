package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
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

var clientset *kubernetes.Clientset

func main() {
	log.Println("Starting Self-Healing Operator Webhook Receiver...")

	kubeconfig := os.Getenv("KUBECONFIG")
	if kubeconfig == "" {
		kubeconfig = os.Getenv("USERPROFILE") + "\\.kube\\config"
	}
	config, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
	if err != nil {
		log.Fatalf("Failed to build kubeconfig: %v", err)
	}

	clientset, err = kubernetes.NewForConfig(config)
	if err != nil {
		log.Fatalf("Failed to create clientset: %v", err)
	}

	http.HandleFunc("/webhook", handleWebhook)
	log.Println("Listening on :8080...")
	log.Fatal(http.ListenAndServe(":8080", nil))
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

func remediateDNS() {
	log.Println("Remediating DNS: Restarting CoreDNS pods...")
	ctx := context.Background()
	pods, err := clientset.CoreV1().Pods("kube-system").List(ctx, metav1.ListOptions{
		LabelSelector: "k8s-app=kube-dns",
	})
	if err != nil {
		log.Printf("Failed to list CoreDNS pods: %v", err)
		return
	}

	for _, pod := range pods.Items {
		log.Printf("Deleting CoreDNS pod %s", pod.Name)
		err = clientset.CoreV1().Pods("kube-system").Delete(ctx, pod.Name, metav1.DeleteOptions{})
		if err != nil {
			log.Printf("Failed to delete pod %s: %v", pod.Name, err)
		}
	}

	log.Println("Deploying Backup DNS Fallback...")
	deployBackupDNS()
}

func deployBackupDNS() {
	log.Println("Applying fallback DNS configurations (simulated)")
}

func remediateNetworkPolicy() {
	log.Println("Remediating NetworkPolicy: Removing blocking policies...")
	ctx := context.Background()
	
	namespaces := []string{"test-namespace-1", "test-namespace-2"}
	for _, ns := range namespaces {
		policies, err := clientset.NetworkingV1().NetworkPolicies(ns).List(ctx, metav1.ListOptions{})
		if err != nil {
			log.Printf("Failed to list NetworkPolicies in %s: %v", ns, err)
			continue
		}
		
		for _, policy := range policies.Items {
			log.Printf("Deleting NetworkPolicy %s in %s", policy.Name, ns)
			err = clientset.NetworkingV1().NetworkPolicies(ns).Delete(ctx, policy.Name, metav1.DeleteOptions{})
			if err != nil {
				log.Printf("Failed to delete NetworkPolicy %s: %v", policy.Name, err)
			}
		}
	}
}

func remediateCNI() {
	log.Println("Remediating CNI: Restarting CNI node pods (Calico / Flannel)...")
	ctx := context.Background()

	// 1. Check Calico
	calicoPods, err := clientset.CoreV1().Pods("calico-system").List(ctx, metav1.ListOptions{
		LabelSelector: "k8s-app=calico-node",
	})
	if err == nil && len(calicoPods.Items) > 0 {
		for _, pod := range calicoPods.Items {
			log.Printf("Deleting Calico pod %s in calico-system", pod.Name)
			_ = clientset.CoreV1().Pods("calico-system").Delete(ctx, pod.Name, metav1.DeleteOptions{})
		}
		return
	}

	// 2. Check Flannel
	flannelPods, err := clientset.CoreV1().Pods("kube-flannel").List(ctx, metav1.ListOptions{
		LabelSelector: "app=flannel",
	})
	if err == nil && len(flannelPods.Items) > 0 {
		for _, pod := range flannelPods.Items {
			log.Printf("Deleting Flannel pod %s in kube-flannel", pod.Name)
			_ = clientset.CoreV1().Pods("kube-flannel").Delete(ctx, pod.Name, metav1.DeleteOptions{})
		}
		return
	}

	log.Println("No active Calico or Flannel pods found to remediate.")
}

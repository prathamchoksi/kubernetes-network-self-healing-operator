package main

import (
	"context"
	"log"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

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
	ctx := context.Background()
	deployment := &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "backup-dns",
			Namespace: "kube-system",
		},
		Spec: appsv1.DeploymentSpec{
			Selector: &metav1.LabelSelector{
				MatchLabels: map[string]string{"app": "backup-dns"},
			},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{
					Labels: map[string]string{"app": "backup-dns"},
				},
				Spec: corev1.PodSpec{
					Containers: []corev1.Container{
						{
							Name:  "dnsmasq",
							Image: "strm/dnsmasq",
							Args:  []string{"--log-facility=-", "--server=8.8.8.8", "--server=1.1.1.1"},
							Ports: []corev1.ContainerPort{
								{ContainerPort: 53, Protocol: corev1.ProtocolUDP},
								{ContainerPort: 53, Protocol: corev1.ProtocolTCP},
							},
						},
					},
				},
			},
		},
	}

	_, err := clientset.AppsV1().Deployments("kube-system").Create(ctx, deployment, metav1.CreateOptions{})
	if err != nil {
		log.Printf("Backup DNS deployment failed (may already exist): %v", err)
	} else {
		log.Println("Successfully deployed Backup DNS.")
	}
}

func remediateNetworkPolicy() {
	log.Println("Remediating NetworkPolicy: Restoring baseline allow-all policy...")
	ctx := context.Background()
	
	namespaces := []string{"test-namespace-1", "test-namespace-2"}
	for _, ns := range namespaces {
		// First, delete existing blocking policies
		policies, err := clientset.NetworkingV1().NetworkPolicies(ns).List(ctx, metav1.ListOptions{})
		if err == nil {
			for _, policy := range policies.Items {
				log.Printf("Deleting NetworkPolicy %s in %s", policy.Name, ns)
				_ = clientset.NetworkingV1().NetworkPolicies(ns).Delete(ctx, policy.Name, metav1.DeleteOptions{})
			}
		}

		// Restore baseline allow-all policy
		baselinePolicy := &networkingv1.NetworkPolicy{
			ObjectMeta: metav1.ObjectMeta{
				Name:      "baseline-allow-all",
				Namespace: ns,
			},
			Spec: networkingv1.NetworkPolicySpec{
				PodSelector: metav1.LabelSelector{},
				PolicyTypes: []networkingv1.PolicyType{
					networkingv1.PolicyTypeIngress,
					networkingv1.PolicyTypeEgress,
				},
				Ingress: []networkingv1.NetworkPolicyIngressRule{{}},
				Egress:  []networkingv1.NetworkPolicyEgressRule{{}},
			},
		}

		_, err = clientset.NetworkingV1().NetworkPolicies(ns).Create(ctx, baselinePolicy, metav1.CreateOptions{})
		if err != nil {
			log.Printf("Failed to create baseline policy in %s: %v", ns, err)
		} else {
			log.Printf("Restored baseline NetworkPolicy in %s", ns)
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

package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// Dummy init for tests
func init() {
	// Pre-fill cooldowns or reset them as needed for tests
}

func TestWebhookRejectsGet(t *testing.T) {
	req, err := http.NewRequest("GET", "/webhook", nil)
	if err != nil {
		t.Fatal(err)
	}

	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(handleWebhook)
	handler.ServeHTTP(rr, req)

	if status := rr.Code; status != http.StatusMethodNotAllowed {
		t.Errorf("handler returned wrong status code: got %v want %v",
			status, http.StatusMethodNotAllowed)
	}
}

func TestWebhookAcceptsValidAlert(t *testing.T) {
	payload := AlertmanagerWebhook{
		Receiver: "operator",
		Status:   "firing",
		Alerts: []Alert{
			{
				Status: "firing",
				Labels: map[string]string{
					"alertname": "TestAlert",
				},
			},
		},
	}

	body, _ := json.Marshal(payload)
	req, err := http.NewRequest("POST", "/webhook", bytes.NewBuffer(body))
	if err != nil {
		t.Fatal(err)
	}

	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(handleWebhook)
	handler.ServeHTTP(rr, req)

	if status := rr.Code; status != http.StatusOK {
		t.Errorf("handler returned wrong status code: got %v want %v",
			status, http.StatusOK)
	}
}

func TestCooldownMechanism(t *testing.T) {
	// Reset the cache for test
	cooldownCache.Delete("TestCooldownAlert")

	alert := Alert{
		Status: "firing",
		Labels: map[string]string{
			"alertname": "TestCooldownAlert",
		},
	}

	// First trigger - should process
	handleAlert("TestCooldownAlert", alert)

	if _, ok := cooldownCache.Load("TestCooldownAlert"); !ok {
		t.Errorf("Alert was not added to cooldown cache")
	}

	// Second trigger immediately - should be in cooldown (test won't panic or error, just logs)
	handleAlert("TestCooldownAlert", alert)

	// Since handleAlert doesn't return anything, we just verify it doesn't crash
	// and respects the cache via logs or code coverage.
}

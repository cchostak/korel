package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.24.0"
)

// setupMockTracer initializes an in-memory SDK TracerProvider for deterministic unit testing.
func setupMockTracer(t *testing.T) *sdktrace.TracerProvider {
	t.Helper()
	res, err := resource.New(
		context.Background(),
		resource.WithAttributes(
			semconv.ServiceNameKey.String("business-service-test"),
			semconv.ServiceVersionKey.String("1.0.0"),
		),
	)
	if err != nil {
		t.Fatalf("failed to create test resource: %v", err)
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithSampler(sdktrace.AlwaysSample()),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)
	tracer = otel.Tracer("corporate-business-service-test")
	return tp
}

func TestHealthHandler(t *testing.T) {
	orgID := "corp-acme-test"
	env := "test-env"

	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{
			"status":      "healthy",
			"service":     "business-service",
			"org_id":      orgID,
			"environment": env,
		})
	})

	req, err := http.NewRequest(http.MethodGet, "/api/health", nil)
	if err != nil {
		t.Fatalf("failed to create GET /api/health request: %v", err)
	}

	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Errorf("expected status %d, got %d", http.StatusOK, recorder.Code)
	}

	contentType := recorder.Header().Get("Content-Type")
	if contentType != "application/json" {
		t.Errorf("expected Content-Type application/json, got %s", contentType)
	}

	var response map[string]string
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatalf("failed to unmarshal health response: %v", err)
	}

	if response["status"] != "healthy" {
		t.Errorf("expected status 'healthy', got '%s'", response["status"])
	}
	if response["service"] != "business-service" {
		t.Errorf("expected service 'business-service', got '%s'", response["service"])
	}
	if response["org_id"] != orgID {
		t.Errorf("expected org_id '%s', got '%s'", orgID, response["org_id"])
	}
	if response["environment"] != env {
		t.Errorf("expected environment '%s', got '%s'", env, response["environment"])
	}
}

func TestOrderHandler(t *testing.T) {
	tp := setupMockTracer(t)
	defer func() {
		_ = tp.Shutdown(context.Background())
	}()

	orgID := "corp-acme-prod"
	env := "production"

	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		executeOrderWorkflow(ctx, orgID, env)
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]interface{}{
			"status":  "success",
			"message": "Order transaction generated and traced",
		})
	})

	req, err := http.NewRequest(http.MethodPost, "/api/order", nil)
	if err != nil {
		t.Fatalf("failed to create POST /api/order request: %v", err)
	}

	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Errorf("expected status %d, got %d", http.StatusOK, recorder.Code)
	}

	var response map[string]interface{}
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatalf("failed to unmarshal order response: %v", err)
	}

	if response["status"] != "success" {
		t.Errorf("expected status 'success', got '%v'", response["status"])
	}
	if response["message"] != "Order transaction generated and traced" {
		t.Errorf("unexpected message in response: %v", response["message"])
	}
}

func TestCorrelatedLogSerialization(t *testing.T) {
	logEntry := CorrelatedLog{
		Timestamp:    "2026-08-29T10:00:00.000000000Z",
		TraceID:      "4bf92f3577b34da6a3ce929d0e0e4736",
		SpanID:       "00f067aa0ba902b7",
		Level:        "INFO",
		Message:      "User authenticated successfully",
		CostCenter:   "engineering-core",
		ServiceOwner: "sre-team",
		OrgID:        "corp-acme-prod",
		Environment:  "production",
		Component:    "auth-middleware",
	}

	data, err := json.Marshal(logEntry)
	if err != nil {
		t.Fatalf("failed to marshal CorrelatedLog: %v", err)
	}

	var parsed CorrelatedLog
	if err := json.Unmarshal(data, &parsed); err != nil {
		t.Fatalf("failed to unmarshal CorrelatedLog: %v", err)
	}

	if parsed.TraceID != logEntry.TraceID {
		t.Errorf("expected trace_id %s, got %s", logEntry.TraceID, parsed.TraceID)
	}
	if parsed.SpanID != logEntry.SpanID {
		t.Errorf("expected span_id %s, got %s", logEntry.SpanID, parsed.SpanID)
	}
	if parsed.CostCenter != logEntry.CostCenter {
		t.Errorf("expected cost_center %s, got %s", logEntry.CostCenter, parsed.CostCenter)
	}
	if parsed.Component != logEntry.Component {
		t.Errorf("expected component %s, got %s", logEntry.Component, parsed.Component)
	}
}

func TestEmitCorrelatedLog(t *testing.T) {
	tp := setupMockTracer(t)
	defer func() {
		_ = tp.Shutdown(context.Background())
	}()

	ctx := context.Background()
	ctx, span := tracer.Start(ctx, "TestSpan")
	defer span.End()

	// Ensure emitCorrelatedLog runs without panicking
	emitCorrelatedLog(ctx, "INFO", "Test message", "engineering-core", "sre-team", "corp-acme-prod", "production", "test-comp")
}

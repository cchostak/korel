package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/propagation"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.24.0"
	trace "go.opentelemetry.io/otel/trace"
)

var (
	tracer           = otel.Tracer("corporate-business-service")
	meter            = otel.Meter("corporate-business-service")
	orderCounter     metric.Int64Counter
	orderAmountTotal metric.Float64Counter
	workflowDuration metric.Float64Histogram
	httpClient       = &http.Client{Timeout: 3 * time.Second}
	collectorHTTPEnd = "http://otel-collector:4318"
)

type CorrelatedLog struct {
	Timestamp    string `json:"timestamp"`
	TraceID      string `json:"trace_id"`
	SpanID       string `json:"span_id"`
	Level        string `json:"level"`
	Message      string `json:"message"`
	CostCenter   string `json:"cost_center"`
	ServiceOwner string `json:"service_owner"`
	OrgID        string `json:"org_id"`
	Environment  string `json:"environment"`
	Component    string `json:"component"`
}

func initMetrics(ctx context.Context, collectorAddr string, res *resource.Resource) (*sdkmetric.MeterProvider, error) {
	exporter, err := otlpmetricgrpc.New(
		ctx,
		otlpmetricgrpc.WithInsecure(),
		otlpmetricgrpc.WithEndpoint(collectorAddr),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create OTLP metric exporter: %w", err)
	}

	mp := sdkmetric.NewMeterProvider(
		sdkmetric.WithResource(res),
		sdkmetric.WithReader(sdkmetric.NewPeriodicReader(exporter, sdkmetric.WithInterval(5*time.Second))),
	)
	otel.SetMeterProvider(mp)
	meter = mp.Meter("corporate-business-service")

	var mErr error
	orderCounter, mErr = meter.Int64Counter(
		"business.orders.total",
		metric.WithDescription("Cumulative count of business orders executed"),
		metric.WithUnit("orders"),
	)
	if mErr != nil {
		log.Printf("Warning: failed to create orderCounter: %v", mErr)
	}

	orderAmountTotal, mErr = meter.Float64Counter(
		"business.order_amount_usd",
		metric.WithDescription("Total monetary value of business transactions"),
		metric.WithUnit("USD"),
	)
	if mErr != nil {
		log.Printf("Warning: failed to create orderAmountTotal: %v", mErr)
	}

	workflowDuration, mErr = meter.Float64Histogram(
		"business.workflow_duration_seconds",
		metric.WithDescription("Execution latency of business workflows"),
		metric.WithUnit("s"),
		metric.WithExplicitBucketBoundaries(0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5),
	)
	if mErr != nil {
		log.Printf("Warning: failed to create workflowDuration: %v", mErr)
	}

	return mp, nil
}

func emitCorrelatedLog(ctx context.Context, level, message, costCenter, owner, orgID, env, component string) {
	span := trace.SpanFromContext(ctx)
	spanCtx := span.SpanContext()

	traceID := ""
	spanID := ""
	if spanCtx.IsValid() {
		traceID = spanCtx.TraceID().String()
		spanID = spanCtx.SpanID().String()
	}

	entry := CorrelatedLog{
		Timestamp:    time.Now().UTC().Format(time.RFC3339Nano),
		TraceID:      traceID,
		SpanID:       spanID,
		Level:        level,
		Message:      message,
		CostCenter:   costCenter,
		ServiceOwner: owner,
		OrgID:        orgID,
		Environment:  env,
		Component:    component,
	}

	bytesData, _ := json.Marshal(entry)
	fmt.Println(string(bytesData))

	// Push directly via OTLP HTTP to OTel Collector -> Loki stream
	go func(logEntry CorrelatedLog, rawJSON string) {
		otlpPayload := map[string]interface{}{
			"resourceLogs": []map[string]interface{}{
				{
					"resource": map[string]interface{}{
						"attributes": []map[string]interface{}{
							{"key": "service.name", "value": map[string]string{"stringValue": "business-service"}},
							{"key": "job", "value": map[string]string{"stringValue": "business-service"}},
							{"key": "org_id", "value": map[string]string{"stringValue": logEntry.OrgID}},
							{"key": "cost_center", "value": map[string]string{"stringValue": logEntry.CostCenter}},
							{"key": "service_owner", "value": map[string]string{"stringValue": logEntry.ServiceOwner}},
							{"key": "environment", "value": map[string]string{"stringValue": logEntry.Environment}},
						},
					},
					"scopeLogs": []map[string]interface{}{
						{
							"scope": map[string]string{"name": "business-service-logger", "version": "1.0.0"},
							"logRecords": []map[string]interface{}{
								{
									"timeUnixNano": fmt.Sprintf("%d", time.Now().UnixNano()),
									"severityText": logEntry.Level,
									"traceId":      logEntry.TraceID,
									"spanId":       logEntry.SpanID,
									"body":         map[string]string{"stringValue": rawJSON},
									"attributes": []map[string]interface{}{
										{"key": "org_id", "value": map[string]string{"stringValue": logEntry.OrgID}},
										{"key": "cost_center", "value": map[string]string{"stringValue": logEntry.CostCenter}},
										{"key": "service_owner", "value": map[string]string{"stringValue": logEntry.ServiceOwner}},
										{"key": "environment", "value": map[string]string{"stringValue": logEntry.Environment}},
										{"key": "component", "value": map[string]string{"stringValue": logEntry.Component}},
										{"key": "trace_id", "value": map[string]string{"stringValue": logEntry.TraceID}},
										{"key": "span_id", "value": map[string]string{"stringValue": logEntry.SpanID}},
										{"key": "level", "value": map[string]string{"stringValue": logEntry.Level}},
									},
								},
							},
						},
					},
				},
			},
		}

		payloadBytes, err := json.Marshal(otlpPayload)
		if err != nil {
			return
		}

		req, err := http.NewRequestWithContext(context.Background(), "POST", collectorHTTPEnd+"/v1/logs", bytes.NewBuffer(payloadBytes))
		if err != nil {
			return
		}
		req.Header.Set("Content-Type", "application/json")
		resp, err := httpClient.Do(req)
		if err == nil && resp != nil {
			_ = resp.Body.Close()
		}
	}(entry, string(bytesData))
}

func initTracer(collectorAddr, orgID, env string) (*sdktrace.TracerProvider, *resource.Resource, error) {
	ctx := context.Background()

	exporter, err := otlptracegrpc.New(
		ctx,
		otlptracegrpc.WithInsecure(),
		otlptracegrpc.WithEndpoint(collectorAddr),
	)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to create OTLP trace exporter: %w", err)
	}

	res, err := resource.New(
		ctx,
		resource.WithAttributes(
			semconv.ServiceNameKey.String("business-service"),
			semconv.ServiceVersionKey.String("1.0.0"),
			attribute.String("org_id", orgID),
			attribute.String("deployment.environment", env),
			attribute.String("cluster", "corp-central-01"),
		),
	)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to initialize resource: %w", err)
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithSampler(sdktrace.AlwaysSample()),
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
	)

	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(propagation.TraceContext{}, propagation.Baggage{}))

	tracer = tp.Tracer("corporate-business-service")
	return tp, res, nil
}

func executeOrderWorkflow(ctx context.Context, orgID, env string) {
	startTime := time.Now()
	if tracer == nil {
		tracer = otel.Tracer("corporate-business-service")
	}

	costCenters := []struct {
		costCenter string
		owner      string
		teamID     string
	}{
		{"engineering-core", "sre-team", "team-backend-core"},
		{"payments-infra", "checkout-squad", "team-checkout"},
		{"data-platform", "analytics-infra", "team-data-platform"},
	}
	selected := costCenters[rand.Intn(len(costCenters))]
	orderID := fmt.Sprintf("ord-%05d", rand.Intn(99999))
	userID := fmt.Sprintf("usr-%04d", rand.Intn(9999))
	amount := float64(rand.Intn(45000)) / 100.0

	attrs := []attribute.KeyValue{
		attribute.String("org_id", orgID),
		attribute.String("environment", env),
		attribute.String("cost_center", selected.costCenter),
		attribute.String("service_owner", selected.owner),
		attribute.String("team_id", selected.teamID),
		attribute.String("workflow", "order_processing"),
		attribute.String("status", "success"),
	}

	ctx, rootSpan := tracer.Start(ctx, "OrderWorkflow",
		trace.WithSpanKind(trace.SpanKindServer),
		trace.WithAttributes(
			attribute.String("org_id", orgID),
			attribute.String("environment", env),
			attribute.String("cost_center", selected.costCenter),
			attribute.String("service_owner", selected.owner),
			attribute.String("team_id", selected.teamID),
			attribute.String("order_id", orderID),
			attribute.String("user_id", userID),
			attribute.Float64("transaction_value", amount),
		),
	)
	defer rootSpan.End()

	emitCorrelatedLog(ctx, "INFO", fmt.Sprintf("Starting OrderWorkflow for order %s", orderID),
		selected.costCenter, selected.owner, orgID, env, "order-gateway")

	// Step 1: Authenticate User
	func() {
		subCtx, span := tracer.Start(ctx, "AuthenticateUser",
			trace.WithSpanKind(trace.SpanKindInternal),
			trace.WithAttributes(
				attribute.String("user_id", userID),
				attribute.String("auth_mechanism", "oauth2_bearer"),
				attribute.String("cost_center", selected.costCenter),
			),
		)
		defer span.End()
		time.Sleep(time.Duration(15+rand.Intn(25)) * time.Millisecond)
		emitCorrelatedLog(subCtx, "INFO", fmt.Sprintf("User %s authenticated successfully", userID),
			selected.costCenter, selected.owner, orgID, env, "auth-middleware")
	}()

	// Step 2: Validate Inventory
	func() {
		subCtx, span := tracer.Start(ctx, "ValidateInventory",
			trace.WithSpanKind(trace.SpanKindClient),
			trace.WithAttributes(
				attribute.String("sku", fmt.Sprintf("SKU-%d", rand.Intn(100))),
				attribute.String("warehouse_region", "us-east-1"),
				attribute.String("cost_center", selected.costCenter),
			),
		)
		defer span.End()
		time.Sleep(time.Duration(20+rand.Intn(40)) * time.Millisecond)
		emitCorrelatedLog(subCtx, "INFO", "Inventory stock reservation confirmed",
			selected.costCenter, selected.owner, orgID, env, "inventory-service")
	}()

	// Step 3: Process Payment
	func() {
		subCtx, span := tracer.Start(ctx, "ProcessPayment",
			trace.WithSpanKind(trace.SpanKindClient),
			trace.WithAttributes(
				attribute.String("payment_gateway", "stripe_corporate"),
				attribute.Float64("amount_usd", amount),
				attribute.String("currency", "USD"),
				attribute.String("cost_center", selected.costCenter),
			),
		)
		defer span.End()
		time.Sleep(time.Duration(40+rand.Intn(80)) * time.Millisecond)
		emitCorrelatedLog(subCtx, "INFO", fmt.Sprintf("Payment authorized for $%0.2f", amount),
			selected.costCenter, selected.owner, orgID, env, "payments-processor")
	}()

	// Step 4: Emit Audit Event
	func() {
		subCtx, span := tracer.Start(ctx, "EmitAuditEvent",
			trace.WithSpanKind(trace.SpanKindProducer),
			trace.WithAttributes(
				attribute.String("audit_level", "compliance"),
				attribute.String("retention_days", "365"),
				attribute.String("cost_center", selected.costCenter),
			),
		)
		defer span.End()
		time.Sleep(time.Duration(10+rand.Intn(20)) * time.Millisecond)
		emitCorrelatedLog(subCtx, "INFO", fmt.Sprintf("Audit ledger committed for order %s", orderID),
			selected.costCenter, selected.owner, orgID, env, "audit-engine")
	}()

	duration := time.Since(startTime).Seconds()

	// Record Metrics
	if orderCounter != nil {
		orderCounter.Add(ctx, 1, metric.WithAttributes(attrs...))
	}
	if orderAmountTotal != nil {
		orderAmountTotal.Add(ctx, amount, metric.WithAttributes(attrs...))
	}
	if workflowDuration != nil {
		workflowDuration.Record(ctx, duration, metric.WithAttributes(attrs...))
	}

	emitCorrelatedLog(ctx, "INFO", fmt.Sprintf("OrderWorkflow completed successfully for order %s (duration: %.3fs)", orderID, duration),
		selected.costCenter, selected.owner, orgID, env, "order-gateway")
}

func main() {
	collectorAddr := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if collectorAddr == "" {
		collectorAddr = "otel-collector:4317"
	}
	httpEndpoint := os.Getenv("OTEL_EXPORTER_OTLP_HTTP_ENDPOINT")
	if httpEndpoint != "" {
		collectorHTTPEnd = httpEndpoint
	}
	orgID := os.Getenv("ORG_ID")
	if orgID == "" {
		orgID = "corp-acme-prod"
	}
	env := os.Getenv("ENVIRONMENT")
	if env == "" {
		env = "production"
	}
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("==================================================")
	log.Printf(" Corporate Business Service Starting")
	log.Printf(" Collector Endpoint: %s", collectorAddr)
	log.Printf(" Listening Port: %s", port)
	log.Printf(" Org ID: %s | Environment: %s", orgID, env)
	log.Printf("==================================================")

	tp, res, err := initTracer(collectorAddr, orgID, env)
	if err != nil {
		log.Printf("Warning: OTel Tracer initialization retry: %v", err)
	}
	if tp != nil {
		defer func() {
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			_ = tp.Shutdown(ctx)
		}()
	}

	if res != nil {
		mp, mErr := initMetrics(context.Background(), collectorAddr, res)
		if mErr != nil {
			log.Printf("Warning: OTel Meter initialization retry: %v", mErr)
		} else if mp != nil {
			defer func() {
				ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
				defer cancel()
				_ = mp.Shutdown(ctx)
			}()
		}
	}

	// HTTP Handlers
	http.HandleFunc("/api/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{
			"status":      "healthy",
			"service":     "business-service",
			"org_id":      orgID,
			"environment": env,
		})
	})

	http.HandleFunc("/api/order", func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		executeOrderWorkflow(ctx, orgID, env)
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]interface{}{
			"status":  "success",
			"message": "Order transaction generated and traced",
		})
	})

	// Background Traffic Generator to keep traces and metrics flowing for demo/observability
	go func() {
		for {
			ctx := context.Background()
			executeOrderWorkflow(ctx, orgID, env)
			time.Sleep(time.Duration(4+rand.Intn(6)) * time.Second)
		}
	}()

	server := &http.Server{
		Addr:    ":" + port,
		Handler: http.DefaultServeMux,
	}

	go func() {
		log.Printf("HTTP Server listening on :%s", port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("HTTP server error: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop

	log.Println("Shutting down business service...")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = server.Shutdown(ctx)
}

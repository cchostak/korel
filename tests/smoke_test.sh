#!/usr/bin/env bash
# ==============================================================================
# Korel Corporate Telemetry Platform — Integration Smoke Test Suite
# ==============================================================================
# Usage:
#   ./tests/smoke_test.sh [OPTIONS]
#
# Options:
#   --up                        Launch docker compose stack before testing
#   --down                      Tear down docker compose stack after testing
#   --timeout <seconds>         Maximum wait time per service (default: 35)
#   --business-port <port>      Business service API port (default: 8080)
#   --collector-prom-port <port> OTel Collector Prometheus metrics port (default: 8889)
#   --collector-metrics-port <port> OTel Collector internal health port (default: 8888)
#   --prometheus-port <port>    Prometheus UI/API port (default: 9090)
#   --grafana-port <port>       Grafana UI port (default: 3000)
#   --tempo-port <port>         Tempo HTTP port (default: 3200)
#   --loki-port <port>          Loki HTTP port (default: 3100)
#   --help, -h                  Show this help message
# ==============================================================================

set -euo pipefail

# ANSI color escape sequences
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Source .env configuration if present
if [ -f .env ]; then
  set -a
  # shellcheck source=/dev/null
  source .env 2>/dev/null || true
  set +a
fi

# Default parameters
BRING_UP=false
TEAR_DOWN=false
TIMEOUT_SECS=35

BUSINESS_PORT="${BUSINESS_SERVICE_PORT:-8085}"
COLLECTOR_PROM_PORT="${OTEL_COLLECTOR_PROMETHEUS_PORT:-8889}"
COLLECTOR_METRICS_PORT="${OTEL_COLLECTOR_METRICS_PORT:-8888}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"
TEMPO_PORT="${TEMPO_PORT:-3200}"
LOKI_PORT="${LOKI_PORT:-3100}"

# Counter metrics
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Print formatted headers and log messages
log_info()    { echo -e "${BLUE}ℹ [INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}✓ [PASS]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}⚠ [WARN]${NC} $*"; }
log_fail()    { echo -e "${RED}✗ [FAIL]${NC} $*"; }
log_step()    { echo -e "\n${BOLD}${CYAN}==>${NC} ${BOLD}$*${NC}"; }

show_help() {
  cat << 'EOF'
Korel Corporate Telemetry Integration Smoke Test Runner

Usage: ./tests/smoke_test.sh [OPTIONS]

Options:
  --up                        Bring up the docker compose stack before running tests
  --down                      Tear down the docker compose stack upon test completion
  --timeout <seconds>         Max seconds to wait for service readiness (default: 35)
  --business-port <port>      Business Service API port (default: 8080)
  --collector-prom-port <port> OTel Collector Prometheus metrics port (default: 8889)
  --collector-metrics-port <port> OTel Collector internal health port (default: 8888)
  --prometheus-port <port>    Prometheus port (default: 9090)
  --grafana-port <port>       Grafana port (default: 3000)
  --tempo-port <port>         Grafana Tempo port (default: 3200)
  --loki-port <port>          Grafana Loki port (default: 3100)
  --help, -h                  Show this help dialog
EOF
  exit 0
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --up)
      BRING_UP=true
      shift
      ;;
    --down)
      TEAR_DOWN=true
      shift
      ;;
    --timeout)
      TIMEOUT_SECS="$2"
      shift 2
      ;;
    --business-port)
      BUSINESS_PORT="$2"
      shift 2
      ;;
    --collector-prom-port)
      COLLECTOR_PROM_PORT="$2"
      shift 2
      ;;
    --collector-metrics-port)
      COLLECTOR_METRICS_PORT="$2"
      shift 2
      ;;
    --prometheus-port)
      PROMETHEUS_PORT="$2"
      shift 2
      ;;
    --grafana-port)
      GRAFANA_PORT="$2"
      shift 2
      ;;
    --tempo-port)
      TEMPO_PORT="$2"
      shift 2
      ;;
    --loki-port)
      LOKI_PORT="$2"
      shift 2
      ;;
    --help|-h)
      show_help
      ;;
    *)
      log_fail "Unknown argument: $1"
      show_help
      ;;
  esac
done

cleanup() {
  if [ "$TEAR_DOWN" = true ]; then
    log_step "Tearing down Docker Compose test environment..."
    docker compose down -v --remove-orphans || true
  fi
}
trap cleanup EXIT

# Helper to poll endpoint until HTTP 200 or timeout
wait_for_endpoint() {
  local url="$1"
  local description="$2"
  local timeout="${3:-$TIMEOUT_SECS}"
  local start_time
  start_time=$(date +%s)

  log_info "Waiting for ${description} at ${url} (timeout: ${timeout}s)..."

  while true; do
    local current_time
    current_time=$(date +%s)
    local elapsed=$((current_time - start_time))

    if [ "$elapsed" -ge "$timeout" ]; then
      log_fail "Timed out waiting for ${description} at ${url} after ${elapsed}s"
      return 1
    fi

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "$url" || echo "000")

    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ]; then
      log_success "${description} is ready (HTTP ${http_code}) after ${elapsed}s"
      return 0
    fi

    sleep 1
  done
}

assert_status() {
  local test_name="$1"
  local expected_code="$2"
  local actual_code="$3"
  local response_body="${4:-}"

  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if [ "$actual_code" -eq "$expected_code" ]; then
    log_success "${test_name} (HTTP ${actual_code})"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    log_fail "${test_name}: Expected HTTP ${expected_code}, got ${actual_code}"
    if [ -n "$response_body" ]; then
      echo "  Response body: ${response_body}"
    fi
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
}

assert_json_contains() {
  local test_name="$1"
  local substring="$2"
  local response_body="$3"

  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if echo "$response_body" | grep -F -q "$substring"; then
    log_success "${test_name} (Contains '${substring}')"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    log_fail "${test_name}: Expected substring '${substring}' in response"
    echo "  Actual body: ${response_body}"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
}

# ------------------------------------------------------------------------------
# Test Execution
# ------------------------------------------------------------------------------

echo "=================================================================="
echo "  🧪 Korel Corporate Telemetry Smoke & Health Verification Harness"
echo "=================================================================="

# Step 0: Optionally launch stack
if [ "$BRING_UP" = true ]; then
  log_step "Launching Docker Compose stack..."
  if [ ! -f .env ]; then
    cp .env.example .env
  fi
  docker compose up -d --build
fi

# Step 1: Health & Readiness Polling
log_step "Verifying Service Readiness & Health Endpoints..."

wait_for_endpoint "http://localhost:${BUSINESS_PORT}/api/health" "Business Service API" "$TIMEOUT_SECS"
wait_for_endpoint "http://localhost:${GRAFANA_PORT}/api/health" "Grafana Observability UI" "$TIMEOUT_SECS"
wait_for_endpoint "http://localhost:${PROMETHEUS_PORT}/-/healthy" "Prometheus TSDB" "$TIMEOUT_SECS"
wait_for_endpoint "http://localhost:${TEMPO_PORT}/ready" "Grafana Tempo Distributed Tracing" "$TIMEOUT_SECS"
wait_for_endpoint "http://localhost:${LOKI_PORT}/ready" "Grafana Loki Log Storage" "$TIMEOUT_SECS"
wait_for_endpoint "http://localhost:${COLLECTOR_PROM_PORT}/metrics" "OTel Collector Prometheus Exporter" "$TIMEOUT_SECS"

# Step 2: Service Health Verification
log_step "Verifying Individual Service Health Endpoints..."

# 2.1 Business Service Health Check
BIZ_HEALTH=$(curl -s -w "\n%{http_code}" "http://localhost:${BUSINESS_PORT}/api/health")
BIZ_BODY=$(echo "$BIZ_HEALTH" | sed '$d')
BIZ_CODE=$(echo "$BIZ_HEALTH" | tail -n1)
assert_status "Business Service GET /api/health returns 200" 200 "$BIZ_CODE" "$BIZ_BODY"
assert_json_contains "Business Service status field is 'healthy'" '"status":"healthy"' "$BIZ_BODY"
assert_json_contains "Business Service service field is 'business-service'" '"service":"business-service"' "$BIZ_BODY"
assert_json_contains "Business Service org_id is present" '"org_id":' "$BIZ_BODY"

# 2.2 Grafana Health Check
GRAFANA_HEALTH=$(curl -s -w "\n%{http_code}" "http://localhost:${GRAFANA_PORT}/api/health")
GRAFANA_BODY=$(echo "$GRAFANA_HEALTH" | sed '$d')
GRAFANA_CODE=$(echo "$GRAFANA_HEALTH" | tail -n1)
assert_status "Grafana GET /api/health returns 200" 200 "$GRAFANA_CODE" "$GRAFANA_BODY"
assert_json_contains "Grafana database status is ok" '"database": "ok"' "$GRAFANA_BODY"

# 2.3 Prometheus Health & Ready Checks
PROM_HEALTH=$(curl -s -w "\n%{http_code}" "http://localhost:${PROMETHEUS_PORT}/-/healthy")
PROM_CODE=$(echo "$PROM_HEALTH" | tail -n1)
assert_status "Prometheus /-/healthy returns 200" 200 "$PROM_CODE" ""

PROM_READY=$(curl -s -w "\n%{http_code}" "http://localhost:${PROMETHEUS_PORT}/-/ready")
PROM_READY_CODE=$(echo "$PROM_READY" | tail -n1)
assert_status "Prometheus /-/ready returns 200" 200 "$PROM_READY_CODE" ""

# 2.4 Loki Ready Check
LOKI_READY=$(curl -s -w "\n%{http_code}" "http://localhost:${LOKI_PORT}/ready")
LOKI_READY_BODY=$(echo "$LOKI_READY" | sed '$d')
LOKI_READY_CODE=$(echo "$LOKI_READY" | tail -n1)
assert_status "Loki /ready returns 200" 200 "$LOKI_READY_CODE" "$LOKI_READY_BODY"
assert_json_contains "Loki reports ready status" "ready" "$LOKI_READY_BODY"

# 2.5 Tempo Ready Check
TEMPO_READY=$(curl -s -w "\n%{http_code}" "http://localhost:${TEMPO_PORT}/ready")
TEMPO_READY_BODY=$(echo "$TEMPO_READY" | sed '$d')
TEMPO_READY_CODE=$(echo "$TEMPO_READY" | tail -n1)
assert_status "Tempo /ready returns 200" 200 "$TEMPO_READY_CODE" "$TEMPO_READY_BODY"
assert_json_contains "Tempo reports ready status" "ready" "$TEMPO_READY_BODY"

# Step 3: Container Process Status
log_step "Verifying Container Process Health..."

CONTAINERS_RUNNING=$(docker compose ps --services --filter "status=running" 2>/dev/null || true)
EXPECTED_CONTAINERS=(
  "otel-collector"
  "tempo"
  "loki"
  "prometheus"
  "grafana"
  "client-cloud-inventory"
  "client-workplace-analytics"
  "client-business-service"
)

for container in "${EXPECTED_CONTAINERS[@]}"; do
  assert_json_contains "Container service '${container}' is active" "$container" "$CONTAINERS_RUNNING"
done

# Step 4: Functional Ingestion & Transaction Verification
log_step "Testing Telemetry Ingestion & Transaction Pipelines..."

# 4.1 Dispatch order transaction on business-service
ORDER_RESP=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:${BUSINESS_PORT}/api/order")
ORDER_BODY=$(echo "$ORDER_RESP" | sed '$d')
ORDER_CODE=$(echo "$ORDER_RESP" | tail -n1)
assert_status "Business Service POST /api/order returns 200" 200 "$ORDER_CODE" "$ORDER_BODY"
assert_json_contains "Order transaction success status" '"status":"success"' "$ORDER_BODY"
assert_json_contains "Order transaction confirmation message" "Order transaction generated and traced" "$ORDER_BODY"

# 4.2 Verify OTel Collector Prometheus metrics export
COLLECTOR_METRICS=$(curl -s -w "\n%{http_code}" "http://localhost:${COLLECTOR_PROM_PORT}/metrics")
COLLECTOR_METRICS_BODY=$(echo "$COLLECTOR_METRICS" | sed '$d')
COLLECTOR_METRICS_CODE=$(echo "$COLLECTOR_METRICS" | tail -n1)
assert_status "OTel Collector Prometheus exporter GET /metrics returns 200" 200 "$COLLECTOR_METRICS_CODE" ""
assert_json_contains "Prometheus metrics exporter header" "# TYPE" "$COLLECTOR_METRICS_BODY"

# 4.3 Verify Prometheus SLO Recording & Alerting Rules Engine
PROM_RULES=$(curl -s -w "\n%{http_code}" "http://localhost:${PROMETHEUS_PORT}/api/v1/rules")
PROM_RULES_BODY=$(echo "$PROM_RULES" | sed '$d')
PROM_RULES_CODE=$(echo "$PROM_RULES" | tail -n1)
assert_status "Prometheus GET /api/v1/rules returns 200" 200 "$PROM_RULES_CODE" "$PROM_RULES_BODY"
assert_json_contains "Prometheus has corporate_slo_recording_rules" "corporate_slo_recording_rules" "$PROM_RULES_BODY"
assert_json_contains "Prometheus has corporate_alerting_rules" "corporate_alerting_rules" "$PROM_RULES_BODY"
assert_json_contains "Prometheus has Multi-Burn-Rate rule" "BusinessServiceAvailabilityFastBurn" "$PROM_RULES_BODY"

# 4.4 Verify Grafana Alerting Provisioning & SLO Dashboard
GRAFANA_ALERTS=$(curl -s -w "\n%{http_code}" "http://admin:admin@localhost:${GRAFANA_PORT}/api/v1/provisioning/alert-rules")
GRAFANA_ALERTS_BODY=$(echo "$GRAFANA_ALERTS" | sed '$d')
GRAFANA_ALERTS_CODE=$(echo "$GRAFANA_ALERTS" | tail -n1)
assert_status "Grafana GET /api/v1/provisioning/alert-rules returns 200" 200 "$GRAFANA_ALERTS_CODE" "$GRAFANA_ALERTS_BODY"
assert_json_contains "Grafana has provisioned SLO alert rule" "Business Service Error Budget Fast Burn" "$GRAFANA_ALERTS_BODY"

GRAFANA_SEARCH=$(curl -s -w "\n%{http_code}" "http://admin:admin@localhost:${GRAFANA_PORT}/api/search")
GRAFANA_SEARCH_BODY=$(echo "$GRAFANA_SEARCH" | sed '$d')
GRAFANA_SEARCH_CODE=$(echo "$GRAFANA_SEARCH" | tail -n1)
assert_status "Grafana GET /api/search returns 200" 200 "$GRAFANA_SEARCH_CODE" "$GRAFANA_SEARCH_BODY"
assert_json_contains "Grafana has SLO/SLA Error Budgets dashboard" "slo-sla-error-budgets" "$GRAFANA_SEARCH_BODY"

# Step 5: Negative & Boundary Assertions
log_step "Verifying Negative & Boundary Conditions..."

# 5.1 Non-existent endpoint on business-service
NON_EXISTENT_RESP=$(curl -s -w "\n%{http_code}" "http://localhost:${BUSINESS_PORT}/api/nonexistent")
NON_EXISTENT_CODE=$(echo "$NON_EXISTENT_RESP" | tail -n1)
assert_status "GET /api/nonexistent returns 404" 404 "$NON_EXISTENT_CODE" ""

# 5.2 Non-existent endpoint on Prometheus
PROM_404_RESP=$(curl -s -w "\n%{http_code}" "http://localhost:${PROMETHEUS_PORT}/api/v1/invalid_endpoint")
PROM_404_CODE=$(echo "$PROM_404_RESP" | tail -n1)
assert_status "GET Prometheus /api/v1/invalid_endpoint returns 404" 404 "$PROM_404_CODE" ""

# ------------------------------------------------------------------------------
# Test Summary
# ------------------------------------------------------------------------------
echo ""
echo "=================================================================="
echo "                   Smoke Test Suite Summary                       "
echo "=================================================================="
echo -e " Total Assertions : ${BOLD}${TOTAL_TESTS}${NC}"
echo -e " Passed           : ${GREEN}${BOLD}${PASSED_TESTS}${NC}"
echo -e " Failed           : ${RED}${BOLD}${FAILED_TESTS}${NC}"
echo "=================================================================="

if [ "$FAILED_TESTS" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}✓ ALL INTEGRATION SMOKE TESTS PASSED SUCCESSFULLY!${NC}\n"
  exit 0
else
  echo -e "${RED}${BOLD}✗ SOME TESTS FAILED. See details above.${NC}\n"
  exit 1
fi

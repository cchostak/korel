# ==============================================================================
# Korel Corporate Telemetry Platform — Operational & DevEx Makefile
# ==============================================================================

SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

-include .env
export

BUSINESS_SERVICE_PORT ?= 8085
GRAFANA_PORT ?= 3000
PROMETHEUS_PORT ?= 9090
TEMPO_PORT ?= 3200
LOKI_PORT ?= 3100
OTEL_COLLECTOR_METRICS_PORT ?= 8888
OTEL_COLLECTOR_PROMETHEUS_PORT ?= 8889

.PHONY: all init up down restart status logs logs-all observe test-trace clean help \
        check fmt test test-unit test-smoke scan doctor

# ==============================================================================
# Help Menu
# ==============================================================================

all: help

help:
	@echo "========================================================================"
	@echo "           Korel Corporate Telemetry Platform — Command Center          "
	@echo "========================================================================"
	@echo "  Developer Quality & Governance:"
	@echo "    make doctor      - Verify local toolchain, Docker daemon & .env health"
	@echo "    make check       - Run static analysis, vetters & linters (non-modifying)"
	@echo "    make fmt         - Auto-format Go, Python, and manifest files"
	@echo "    make test        - Run complete test suite (unit + smoke tests)"
	@echo "    make test-unit   - Run Go and Python unit test suites"
	@echo "    make test-smoke  - Run integration smoke tests against containers"
	@echo "    make scan        - Run local security scans (Gitleaks & Trivy)"
	@echo ""
	@echo "  Container Lifecycle & Management:"
	@echo "    make init        - Initialize .env configuration from .env.example"
	@echo "    make up          - Build and launch all 8 telemetry containers"
	@echo "    make down        - Stop all containers and purge storage volumes"
	@echo "    make restart     - Restart all telemetry containers"
	@echo "    make status      - Display container health status and port bindings"
	@echo "    make logs        - Stream live logs from OpenTelemetry Collector"
	@echo "    make logs-all    - Stream live logs from all containers"
	@echo "    make clean       - Purge local images, test caches, and .env"
	@echo ""
	@echo "  Observability & Verification:"
	@echo "    make test-trace  - Trigger interactive transaction on business-service"
	@echo "    make observe     - Display URLs, credentials & exploration guide"
	@echo "========================================================================"

# ==============================================================================
# Environment Initialization & Health Checks
# ==============================================================================

init:
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "[✓] Created .env configuration from .env.example"; \
	else \
		echo "[!] .env file already exists. Skipping copy."; \
	fi

doctor: init
	@echo "=================================================================="
	@echo "  🔍 Running Korel Toolchain & Environment Diagnostics            "
	@echo "=================================================================="
	@ERRORS=0; \
	check_cmd() { \
		if command -v "$$1" >/dev/null 2>&1; then \
			echo "  [✓] $$1 is installed ($$(command -v "$$1"))"; \
		else \
			echo "  [✗] $$1 is NOT installed or not in PATH"; \
			ERRORS=$$((ERRORS + 1)); \
		fi; \
	}; \
	echo "--> [1/4] Checking Required CLI Tools:"; \
	check_cmd docker; \
	check_cmd go; \
	check_cmd python3; \
	check_cmd curl; \
	check_cmd jq; \
	check_cmd git; \
	echo ""; \
	echo "--> [2/4] Checking Docker Runtime:"; \
	if docker info >/dev/null 2>&1; then \
		echo "  [✓] Docker daemon is running and accessible"; \
	else \
		echo "  [✗] Docker daemon is unreachable. Please start Docker."; \
		ERRORS=$$((ERRORS + 1)); \
	fi; \
	echo ""; \
	echo "--> [3/4] Checking Configuration (.env):"; \
	if [ -f .env ]; then \
		echo "  [✓] .env file is present"; \
	else \
		echo "  [✗] .env file is missing"; \
		ERRORS=$$((ERRORS + 1)); \
	fi; \
	echo ""; \
	echo "--> [4/4] Checking Port Availability ($(GRAFANA_PORT), $(PROMETHEUS_PORT), $(TEMPO_PORT), $(LOKI_PORT), $(BUSINESS_SERVICE_PORT)):"; \
	for port in $(GRAFANA_PORT) $(PROMETHEUS_PORT) $(TEMPO_PORT) $(LOKI_PORT) $(BUSINESS_SERVICE_PORT); do \
		if command -v nc >/dev/null 2>&1; then \
			if nc -z 127.0.0.1 $$port 2>/dev/null; then \
				echo "  [!] Port $$port is currently in use"; \
			else \
				echo "  [✓] Port $$port is available"; \
			fi; \
		else \
			echo "  [i] nc not available; skipping live port probe for $$port"; \
		fi; \
	done; \
	echo "=================================================================="; \
	if [ $$ERRORS -eq 0 ]; then \
		echo "  ✅ All environment diagnostic checks passed successfully!"; \
	else \
		echo "  ❌ Found $$ERRORS diagnostic issue(s). Please review above."; \
		exit 1; \
	fi

# ==============================================================================
# Linters, Formatters & Static Analysis
# ==============================================================================

check:
	@echo "--> [1/4] Checking Go Formatting & Vetting..."
	@cd clients/business-service && ( \
		UNFORMATTED=$$(gofmt -l .); \
		if [ -n "$$UNFORMATTED" ]; then \
			echo "Unformatted Go files found:"; \
			echo "$$UNFORMATTED"; \
			exit 1; \
		fi; \
		go vet ./...; \
	)
	@echo "[✓] Go code is formatted and passes go vet."
	@echo ""
	@echo "--> [2/4] Checking Python Syntax & Code Integrity..."
	@python3 -m py_compile clients/cloud-inventory/main.py clients/workplace-analytics/main.py tests/unit/*.py
	@if command -v ruff >/dev/null 2>&1; then \
		ruff check clients/ tests/; \
	fi
	@echo "[✓] Python code syntax validated."
	@echo ""
	@echo "--> [3/4] Checking Shell Scripts..."
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck tests/*.sh; \
		echo "[✓] Shell scripts pass ShellCheck."; \
	else \
		echo "[i] shellcheck not installed. Skipping shellcheck."; \
	fi
	@echo ""
	@echo "--> [4/4] Validating Docker Compose Configuration..."
	@docker compose config -q
	@echo "[✓] docker-compose.yml configuration is valid."

fmt:
	@echo "--> Formatting Go source code..."
	@cd clients/business-service && gofmt -w .
	@echo "[✓] Go files formatted."
	@if command -v ruff >/dev/null 2>&1; then \
		echo "--> Formatting Python source code..."; \
		ruff format clients/ tests/; \
		echo "[✓] Python files formatted."; \
	fi

# ==============================================================================
# Testing Suites
# ==============================================================================

test: test-unit test-smoke

test-unit:
	@echo "=================================================================="
	@echo "  🧪 Running Unit Tests                                           "
	@echo "=================================================================="
	@echo "--> Executing Go Unit Tests..."
	@cd clients/business-service && go test -v -race -cover ./...
	@echo ""
	@echo "--> Executing Python Unit Tests..."
	@python3 -m unittest discover -s tests/unit -p "test_*.py" -v
	@echo "=================================================================="
	@echo "  ✅ All Unit Tests Passed Successfully!                          "
	@echo "=================================================================="

test-smoke:
	@chmod +x tests/smoke_test.sh
	@./tests/smoke_test.sh

# ==============================================================================
# Security & Vulnerability Auditing
# ==============================================================================

scan:
	@echo "=================================================================="
	@echo "  🔒 Running Security & Vulnerability Audits                      "
	@echo "=================================================================="
	@if command -v gitleaks >/dev/null 2>&1; then \
		echo "--> Running Gitleaks Secret Audit..."; \
		gitleaks detect --verbose; \
	else \
		echo "--> Running Containerized Gitleaks Secret Audit..."; \
		docker run --rm -v "$$(pwd):/path" zricethezav/gitleaks:latest detect --source="/path" --verbose || true; \
	fi
	@echo ""
	@if command -v trivy >/dev/null 2>&1; then \
		echo "--> Running Trivy Filesystem Scan..."; \
		trivy fs --severity CRITICAL,HIGH .; \
	else \
		echo "--> Running Containerized Trivy Filesystem Scan..."; \
		docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$$(pwd):/root/.cache/" aquasec/trivy:latest fs --severity CRITICAL,HIGH . || true; \
	fi
	@echo "=================================================================="
	@echo "  ✅ Security Scans Completed!                                    "
	@echo "=================================================================="

# ==============================================================================
# Container Lifecycle & Operational Commands
# ==============================================================================

up: init
	@echo "[+] Building and launching Korel Corporate Telemetry Platform..."
	docker compose up -d --build
	@echo "[✓] Stack is running. Run 'make observe' for endpoint links."

down:
	@echo "[-] Stopping Corporate Telemetry Platform & pruning volumes..."
	docker compose down -v --remove-orphans
	@echo "[✓] Telemetry stack stopped."

restart:
	@echo "[*] Restarting Telemetry Platform..."
	docker compose restart

status:
	@docker compose ps

logs:
	docker compose logs -f otel-collector

logs-all:
	docker compose logs -f

test-trace:
	@echo "[+] Triggering manual distributed transaction on Business Service..."
	@curl -s -X POST http://localhost:$(BUSINESS_SERVICE_PORT)/api/order | jq . || curl -s -X POST http://localhost:$(BUSINESS_SERVICE_PORT)/api/order
	@echo ""
	@echo "[✓] Distributed transaction dispatched. Check Grafana Tempo for the new trace!"

observe:
	@echo "========================================================================"
	@echo "              Korel Telemetry Stack — Endpoints & UI                    "
	@echo "========================================================================"
	@echo "  📊 Grafana Dashboards : http://localhost:$(GRAFANA_PORT)"
	@echo "     - User/Password    : admin / admin (or auto-logged in as Admin)"
	@echo "     - Dashboard        : Corporate Telemetry Pivot Dashboard"
	@echo ""
	@echo "  📈 Prometheus UI      : http://localhost:$(PROMETHEUS_PORT)"
	@echo "     - Metrics Target   : http://localhost:$(PROMETHEUS_PORT)/targets"
	@echo ""
	@echo "  🔍 Grafana Tempo (OTLP): http://localhost:$(TEMPO_PORT)"
	@echo "     - Traces Endpoint  : localhost:4317 (gRPC) / localhost:4318 (HTTP)"
	@echo ""
	@echo "  📜 Grafana Loki (Logs): http://localhost:$(LOKI_PORT)"
	@echo "     - Log Push API     : http://localhost:$(LOKI_PORT)/loki/api/v1/push"
	@echo ""
	@echo "  ⚙️  OTel Collector     : http://localhost:$(OTEL_COLLECTOR_METRICS_PORT) (Health & Collector Metrics)"
	@echo "     - Prom Exporter    : http://localhost:$(OTEL_COLLECTOR_PROMETHEUS_PORT)/metrics"
	@echo ""
	@echo "  🏢 Business Service API: http://localhost:$(BUSINESS_SERVICE_PORT)"
	@echo "     - Trigger Order    : curl -X POST http://localhost:$(BUSINESS_SERVICE_PORT)/api/order"
	@echo "     - Health Check     : curl http://localhost:$(BUSINESS_SERVICE_PORT)/api/health"
	@echo "========================================================================"

clean:
	docker compose down -v --rmi local --remove-orphans || true
	rm -f .env coverage.out clients/business-service/coverage.out
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@echo "[✓] Local artifacts and build caches cleaned."

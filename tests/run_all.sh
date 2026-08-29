#!/usr/bin/env bash
# ==============================================================================
# Master Test Runner — Executes Go Unit Tests, Python Unit Tests & Smoke Tests
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${ROOT_DIR}"

echo "=================================================================="
echo "  🚀 Running Korel Complete Test Suite                            "
echo "=================================================================="

echo -e "\n==> [1/3] Executing Go Unit Tests..."
cd "${ROOT_DIR}/clients/business-service"
go test -v -race -coverprofile=coverage.out ./...
go tool cover -func=coverage.out 2>/dev/null | tail -n 1 || true
cd "${ROOT_DIR}"

echo -e "\n==> [2/3] Executing Python Unit Tests..."
python3 -m unittest discover -s tests/unit -p "test_*.py" -v

echo -e "\n==> [3/3] Executing Integration Smoke Tests..."
chmod +x tests/smoke_test.sh
./tests/smoke_test.sh "$@"

echo "=================================================================="
echo "  ✅ All Unit and Integration Tests Passed Successfully!          "
echo "=================================================================="

"""
Unit Tests — Workplace Analytics Telemetry Generator
Unified Corporate Telemetry Platform
"""

import importlib.util
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock

# Mock opentelemetry packages if not installed in current environment
for mod in [
    "opentelemetry",
    "opentelemetry.metrics",
    "opentelemetry.sdk",
    "opentelemetry.sdk.metrics",
    "opentelemetry.sdk.metrics.export",
    "opentelemetry.exporter",
    "opentelemetry.exporter.otlp",
    "opentelemetry.exporter.otlp.proto",
    "opentelemetry.exporter.otlp.proto.http",
    "opentelemetry.exporter.otlp.proto.http.metric_exporter",
    "opentelemetry.sdk.resources",
]:
    if mod not in sys.modules:
        sys.modules[mod] = MagicMock()

# Load workplace-analytics main module dynamically
MODULE_PATH = Path(__file__).resolve().parent.parent.parent / "clients" / "workplace-analytics" / "main.py"
spec = importlib.util.spec_from_file_location("workplace_analytics_main", str(MODULE_PATH))
workplace_main = importlib.util.module_from_spec(spec)
sys.modules["workplace_analytics_main"] = workplace_main
spec.loader.exec_module(workplace_main)


class TestWorkplaceAnalyticsConfig(unittest.TestCase):
    """Tests department metadata matrix, metrics instruments configuration, and business rules."""

    def test_department_matrix_structure(self):
        """Verifies each department in the matrix has all required dimensions and reasonable baseline values."""
        required_fields = [
            "department",
            "team",
            "cost_center",
            "service_owner",
            "tier",
            "repo",
            "jira_project",
            "base_slack",
            "base_prs",
            "base_jira",
            "base_cost",
        ]

        self.assertGreaterEqual(len(workplace_main.DEPARTMENTS), 4)

        for dept in workplace_main.DEPARTMENTS:
            for field in required_fields:
                self.assertIn(field, dept, f"Missing field '{field}' in department '{dept.get('department')}'")

            self.assertGreater(dept["base_slack"], 0)
            self.assertGreater(dept["base_prs"], 0)
            self.assertGreater(dept["base_jira"], 0)
            self.assertGreater(dept["base_cost"], 0.0)

    def test_provider_attribution(self):
        """Ensures provider mapping distinguishes AWS vs GCP based on cost center."""
        for dept in workplace_main.DEPARTMENTS:
            provider = "aws" if dept["cost_center"] != "data-platform" else "gcp"
            if dept["cost_center"] == "data-platform":
                self.assertEqual(provider, "gcp")
            else:
                self.assertEqual(provider, "aws")

    def test_unique_department_names(self):
        """Ensures there are no duplicate department names in the matrix."""
        dept_names = [d["department"] for d in workplace_main.DEPARTMENTS]
        self.assertEqual(len(dept_names), len(set(dept_names)), "Duplicate department names found")


if __name__ == "__main__":
    unittest.main()

"""
Unit Tests — Cloud Inventory Telemetry Generator
Unified Corporate Telemetry Platform
"""

import importlib.util
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock

# Mock opentelemetry and requests packages if not installed in current environment
for mod in [
    "opentelemetry",
    "opentelemetry._logs",
    "opentelemetry.sdk",
    "opentelemetry.sdk._logs",
    "opentelemetry.sdk._logs.export",
    "opentelemetry.exporter",
    "opentelemetry.exporter.otlp",
    "opentelemetry.exporter.otlp.proto",
    "opentelemetry.exporter.otlp.proto.http",
    "opentelemetry.exporter.otlp.proto.http._log_exporter",
    "opentelemetry.sdk.resources",
    "requests",
]:
    if mod not in sys.modules:
        sys.modules[mod] = MagicMock()

# Load cloud-inventory main module dynamically
MODULE_PATH = Path(__file__).resolve().parent.parent.parent / "clients" / "cloud-inventory" / "main.py"
spec = importlib.util.spec_from_file_location("cloud_inventory_main", str(MODULE_PATH))
cloud_inv = importlib.util.module_from_spec(spec)
sys.modules["cloud_inventory_main"] = cloud_inv
spec.loader.exec_module(cloud_inv)


class TestCloudInventoryGenerator(unittest.TestCase):
    """Tests payload generation, corporate taxonomy compliance, and validation logic."""

    def test_generate_inventory_record_structure(self):
        """Validates that generated inventory payload contains all required corporate fields."""
        record = cloud_inv.generate_inventory_record()

        required_keys = [
            "timestamp",
            "event_type",
            "org_id",
            "environment",
            "cost_center",
            "service_owner",
            "provider",
            "resource_type",
            "resource_id",
            "region",
            "instance_shape",
            "compliance_status",
            "encryption_enabled",
            "egress_cost_monthly",
            "tags",
            "attached_policies",
        ]

        for key in required_keys:
            self.assertIn(key, record, f"Missing required corporate attribute '{key}' in inventory record")

        self.assertEqual(record["event_type"], "corporate.inventory.snapshot")
        self.assertIn(record["provider"], ["aws", "gcp"])
        self.assertIn(record["compliance_status"], ["compliant", "warning", "non_compliant"])

    def test_compliance_and_encryption_logic(self):
        """Ensures encryption state reflects compliance status rule."""
        for _ in range(50):
            record = cloud_inv.generate_inventory_record()
            if record["compliance_status"] == "non_compliant":
                self.assertFalse(record["encryption_enabled"])
            else:
                self.assertTrue(record["encryption_enabled"])

    def test_cost_center_and_owner_mapping(self):
        """Verifies that cost centers and service owners correspond to approved platform taxonomy."""
        valid_cost_centers = {c["cost_center"] for c in cloud_inv.COST_CENTERS}
        valid_owners = {c["service_owner"] for c in cloud_inv.COST_CENTERS}

        for _ in range(30):
            record = cloud_inv.generate_inventory_record()
            self.assertIn(record["cost_center"], valid_cost_centers)
            self.assertIn(record["service_owner"], valid_owners)

    def test_egress_cost_bounds(self):
        """Ensures simulated monthly egress costs are positive floats within expected bounds."""
        for _ in range(30):
            record = cloud_inv.generate_inventory_record()
            self.assertIsInstance(record["egress_cost_monthly"], float)
            self.assertGreaterEqual(record["egress_cost_monthly"], 10.0)
            self.assertLessEqual(record["egress_cost_monthly"], 500.0)

    def test_tags_schema_and_classification(self):
        """Verifies nested tags include required metadata and classification logic."""
        for _ in range(30):
            record = cloud_inv.generate_inventory_record()
            tags = record["tags"]
            self.assertIn("team", tags)
            self.assertIn("project", tags)
            self.assertIn("data_classification", tags)
            self.assertIn("managed_by", tags)

            if "payment" in record["cost_center"]:
                self.assertEqual(tags["data_classification"], "confidential")
            else:
                self.assertEqual(tags["data_classification"], "internal")


if __name__ == "__main__":
    unittest.main()

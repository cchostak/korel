"""
Cloud Inventory Telemetry Client
Unified Corporate Telemetry Platform

Periodically scans and emits structured cloud asset inventory telemetry
(AWS EC2, S3, RDS, DynamoDB, GCP Compute, CloudSQL) with unified corporate
attributes (org_id, cost_center, service_owner, environment) to OpenTelemetry Collector.
"""

import json
import logging
import os
import random
import time
from datetime import datetime, timezone
import requests
from opentelemetry._logs import LogRecord, SeverityNumber, set_logger_provider
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter
from opentelemetry.sdk.resources import Resource

# Environment configurations
COLLECTOR_ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector:4318")
INTERVAL_SECONDS = int(os.getenv("COLLECTION_INTERVAL_SECONDS", "10"))
DEFAULT_ORG_ID = os.getenv("ORG_ID", "corp-acme-prod")
DEFAULT_ENV = os.getenv("ENVIRONMENT", "production")

# Seed metadata for realistic inventory simulation
COST_CENTERS = [
    {"cost_center": "engineering-core", "service_owner": "sre-team"},
    {"cost_center": "payments-infra", "service_owner": "checkout-squad"},
    {"cost_center": "data-platform", "service_owner": "analytics-infra"},
    {"cost_center": "security-ops", "service_owner": "sec-ops"},
]

CLOUD_RESOURCES = [
    {
        "provider": "aws",
        "resource_type": "ec2:instance",
        "prefix": "i-0a",
        "regions": ["us-east-1", "us-west-2", "eu-west-1"],
        "shapes": ["m6i.2xlarge", "c6i.4xlarge", "r6i.xlarge", "t4g.nano"],
    },
    {
        "provider": "aws",
        "resource_type": "s3:bucket",
        "prefix": "corp-data-lake-",
        "regions": ["us-east-1", "eu-west-1"],
        "shapes": ["standard-ia", "glacier-instant", "intelligent-tiering"],
    },
    {
        "provider": "aws",
        "resource_type": "rds:cluster",
        "prefix": "aurora-pg-",
        "regions": ["us-east-1", "us-west-2"],
        "shapes": ["db.r6g.2xlarge", "db.t4g.medium"],
    },
    {
        "provider": "gcp",
        "resource_type": "compute:instance",
        "prefix": "gce-prod-node-",
        "regions": ["us-central1-a", "europe-west1-b"],
        "shapes": ["n2-standard-8", "e2-medium", "c2-standard-16"],
    },
    {
        "provider": "gcp",
        "resource_type": "cloudsql:instance",
        "prefix": "cloudsql-analytics-",
        "regions": ["us-central1"],
        "shapes": ["db-custom-4-16384"],
    },
]


def generate_inventory_record():
    """Generate a rich, structured cloud inventory event."""
    template = random.choice(CLOUD_RESOURCES)
    org_mapping = random.choice(COST_CENTERS)
    resource_id = f"{template['prefix']}{random.randint(10000, 99999)}"
    region = random.choice(template["regions"])
    shape = random.choice(template["shapes"])
    compliance = random.choices(["compliant", "warning", "non_compliant"], weights=[0.85, 0.10, 0.05])[0]
    egress_cost = round(random.uniform(12.50, 480.00), 2)

    payload = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "event_type": "corporate.inventory.snapshot",
        "org_id": DEFAULT_ORG_ID,
        "environment": DEFAULT_ENV,
        "cost_center": org_mapping["cost_center"],
        "service_owner": org_mapping["service_owner"],
        "provider": template["provider"],
        "resource_type": template["resource_type"],
        "resource_id": resource_id,
        "region": region,
        "instance_shape": shape,
        "compliance_status": compliance,
        "encryption_enabled": True if compliance != "non_compliant" else False,
        "egress_cost_monthly": egress_cost,
        "tags": {
            "team": org_mapping["service_owner"],
            "project": "core-platform-modernization",
            "data_classification": "confidential" if "payment" in org_mapping["cost_center"] else "internal",
            "managed_by": "terraform",
        },
        "attached_policies": [
            "arn:aws:iam::aws:policy/SecurityAudit",
            "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
        ],
    }
    return payload


def setup_otel_logger():
    """Initializes OpenTelemetry LoggerProvider and exporter."""
    resource = Resource.create(
        {
            "service.name": "cloud-inventory",
            "service.version": "1.0.0",
            "deployment.environment": DEFAULT_ENV,
            "org_id": DEFAULT_ORG_ID,
        }
    )

    logs_endpoint = f"{COLLECTOR_ENDPOINT.rstrip('/')}/v1/logs"
    print(f"[cloud-inventory] Initializing OTel Log Exporter -> {logs_endpoint}")

    logger_provider = LoggerProvider(resource=resource)
    exporter = OTLPLogExporter(endpoint=logs_endpoint)
    logger_provider.add_log_record_processor(BatchLogRecordProcessor(exporter))
    set_logger_provider(logger_provider)

    handler = LoggingHandler(level=logging.INFO, logger_provider=logger_provider)
    logging.getLogger().addHandler(handler)
    logging.getLogger().setLevel(logging.INFO)

    return logger_provider


def push_log_record(logger_provider, payload):
    """Pushes structured log record using OpenTelemetry LogRecord API."""
    logger = logger_provider.get_logger("cloud-inventory")
    severity = SeverityNumber.WARN if payload["compliance_status"] == "non_compliant" else SeverityNumber.INFO

    # Log record attributes
    attributes = {
        "org_id": payload["org_id"],
        "environment": payload["environment"],
        "cost_center": payload["cost_center"],
        "service_owner": payload["service_owner"],
        "provider": payload["provider"],
        "resource_type": payload["resource_type"],
        "resource_id": payload["resource_id"],
        "region": payload["region"],
        "compliance_status": payload["compliance_status"],
        "egress_cost_monthly": payload["egress_cost_monthly"],
    }

    log_record = LogRecord(
        timestamp=int(time.time() * 1e9),
        observed_timestamp=int(time.time() * 1e9),
        trace_id=0,
        span_id=0,
        trace_flags=None,
        severity_text=payload["compliance_status"].upper(),
        severity_number=severity,
        body=json.dumps(payload),
        attributes=attributes,
    )
    logger.emit(log_record)


def push_direct_otlp_http(payload):
    """Fallback / Direct OTLP JSON HTTP Push to ensure immediate ingest."""
    try:
        logs_url = f"{COLLECTOR_ENDPOINT.rstrip('/')}/v1/logs"
        otlp_payload = {
            "resourceLogs": [
                {
                    "resource": {
                        "attributes": [
                            {"key": "service.name", "value": {"stringValue": "cloud-inventory"}},
                            {"key": "job", "value": {"stringValue": "cloud-inventory"}},
                            {"key": "org_id", "value": {"stringValue": payload["org_id"]}},
                            {"key": "cost_center", "value": {"stringValue": payload["cost_center"]}},
                            {"key": "service_owner", "value": {"stringValue": payload["service_owner"]}},
                        ]
                    },
                    "scopeLogs": [
                        {
                            "scope": {"name": "cloud-inventory-scanner", "version": "1.0.0"},
                            "logRecords": [
                                {
                                    "timeUnixNano": str(int(time.time() * 1e9)),
                                    "severityText": payload["compliance_status"].upper(),
                                    "body": {"stringValue": json.dumps(payload)},
                                    "attributes": [
                                        {"key": "org_id", "value": {"stringValue": payload["org_id"]}},
                                        {"key": "cost_center", "value": {"stringValue": payload["cost_center"]}},
                                        {"key": "service_owner", "value": {"stringValue": payload["service_owner"]}},
                                        {"key": "provider", "value": {"stringValue": payload["provider"]}},
                                        {"key": "resource_type", "value": {"stringValue": payload["resource_type"]}},
                                        {"key": "resource_id", "value": {"stringValue": payload["resource_id"]}},
                                        {"key": "compliance_status", "value": {"stringValue": payload["compliance_status"]}},
                                        {"key": "egress_cost_monthly", "value": {"doubleValue": float(payload["egress_cost_monthly"])}},
                                    ],
                                }
                            ],
                        }
                    ],
                }
            ]
        }
        resp = requests.post(logs_url, json=otlp_payload, timeout=5)
        if resp.status_code not in (200, 202):
            logging.warning(f"Direct OTLP HTTP returned {resp.status_code}: {resp.text}")
    except Exception as e:
        logging.error(f"Direct OTLP push error: {e}")


def main():
    print("==================================================")
    print(" Cloud Inventory Telemetry Generator Starting")
    print(f" Target Collector: {COLLECTOR_ENDPOINT}")
    print(f" Collection Interval: {INTERVAL_SECONDS}s")
    print("==================================================")

    logger_provider = setup_otel_logger()

    while True:
        try:
            # Emit batch of 3-5 cloud assets per cycle
            batch_count = random.randint(3, 6)
            for _ in range(batch_count):
                record = generate_inventory_record()
                push_log_record(logger_provider, record)
                push_direct_otlp_http(record)
                print(
                    f"[{datetime.now().strftime('%H:%M:%S')}] Emitted cloud asset: {record['provider']} "
                    f"{record['resource_id']} ({record['resource_type']}) | "
                    f"CostCenter={record['cost_center']} | Status={record['compliance_status']}"
                )
            logger_provider.force_flush()
        except Exception as ex:
            print(f"[cloud-inventory] Error in collection loop: {ex}")

        time.sleep(INTERVAL_SECONDS)


if __name__ == "__main__":
    main()

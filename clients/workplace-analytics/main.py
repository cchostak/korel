"""
Workplace Analytics Telemetry Client
Unified Corporate Telemetry Platform

Periodically measures and emits corporate operational metrics
(Slack active users, GitHub PR throughput, Jira tickets, cloud daily cost)
using the OpenTelemetry Metrics SDK with unified corporate dimensions.
"""

import os
import random
import time
from datetime import datetime
from opentelemetry import metrics
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.resources import Resource

COLLECTOR_ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector:4318")
INTERVAL_SECONDS = int(os.getenv("COLLECTION_INTERVAL_SECONDS", "10"))
DEFAULT_ORG_ID = os.getenv("ORG_ID", "corp-acme-prod")
DEFAULT_ENV = os.getenv("ENVIRONMENT", "production")

# Departmental & Cost Center Matrix
DEPARTMENTS = [
    {
        "department": "core-backend",
        "team": "backend-core",
        "cost_center": "engineering-core",
        "service_owner": "sre-team",
        "tier": "enterprise",
        "repo": "corp/backend-monolith",
        "jira_project": "CORE",
        "base_slack": 145,
        "base_prs": 18,
        "base_jira": 34,
        "base_cost": 1250.0,
    },
    {
        "department": "payments-billing",
        "team": "checkout-squad",
        "cost_center": "payments-infra",
        "service_owner": "checkout-squad",
        "tier": "enterprise",
        "repo": "corp/payments-engine",
        "jira_project": "PAY",
        "base_slack": 62,
        "base_prs": 8,
        "base_jira": 19,
        "base_cost": 840.0,
    },
    {
        "department": "data-analytics",
        "team": "data-platform",
        "cost_center": "data-platform",
        "service_owner": "analytics-infra",
        "tier": "standard",
        "repo": "corp/data-pipelines",
        "jira_project": "DATA",
        "base_slack": 48,
        "base_prs": 12,
        "base_jira": 27,
        "base_cost": 2100.0,
    },
    {
        "department": "security-grc",
        "team": "sec-ops",
        "cost_center": "security-ops",
        "service_owner": "sec-ops",
        "tier": "enterprise",
        "repo": "corp/security-tooling",
        "jira_project": "SEC",
        "base_slack": 25,
        "base_prs": 4,
        "base_jira": 11,
        "base_cost": 420.0,
    },
]


def setup_meter_provider():
    """Configures MeterProvider with OTLP HTTP Metric Exporter."""
    resource = Resource.create(
        {
            "service.name": "workplace-analytics",
            "service.version": "1.0.0",
            "deployment.environment": DEFAULT_ENV,
            "org_id": DEFAULT_ORG_ID,
        }
    )

    metrics_url = f"{COLLECTOR_ENDPOINT.rstrip('/')}/v1/metrics"
    print(f"[workplace-analytics] Initializing OTel Metric Exporter -> {metrics_url}")

    exporter = OTLPMetricExporter(endpoint=metrics_url)
    reader = PeriodicExportingMetricReader(exporter, export_interval_millis=INTERVAL_SECONDS * 1000)
    provider = MeterProvider(resource=resource, metric_readers=[reader])
    metrics.set_meter_provider(provider)

    return provider


def main():
    print("==================================================")
    print(" Workplace Analytics Telemetry Client Starting")
    print(f" Target Collector: {COLLECTOR_ENDPOINT}")
    print(f" Collection Interval: {INTERVAL_SECONDS}s")
    print("==================================================")

    provider = setup_meter_provider()
    meter = metrics.get_meter("workplace-analytics", "1.0.0")

    # Define Metric Instruments
    slack_active_users_gauge = meter.create_gauge(
        name="slack.active_users",
        description="Number of currently active users on corporate Slack workspace",
        unit="users",
    )

    github_open_prs_gauge = meter.create_gauge(
        name="github.open_prs",
        description="Number of currently open pull requests across corporate repositories",
        unit="prs",
    )

    github_pr_merges_counter = meter.create_counter(
        name="github.pr_merges_total",
        description="Cumulative count of merged pull requests",
        unit="merges",
    )

    jira_tickets_open_gauge = meter.create_gauge(
        name="jira.tickets.open",
        description="Number of unresolved Jira tickets by project and priority",
        unit="tickets",
    )

    cloud_cost_daily_gauge = meter.create_gauge(
        name="cloud.estimated_cost_daily",
        description="Estimated daily cloud infrastructure cost",
        unit="USD",
    )

    while True:
        try:
            for dept in DEPARTMENTS:
                # Calculate simulated fluctuations
                slack_count = max(5, dept["base_slack"] + random.randint(-8, 12))
                open_prs = max(1, dept["base_prs"] + random.randint(-2, 3))
                open_jira = max(2, dept["base_jira"] + random.randint(-3, 5))
                daily_cost = round(dept["base_cost"] + random.uniform(-50.0, 75.0), 2)
                merges_increment = random.choice([0, 1, 1, 2])

                common_attributes = {
                    "org_id": DEFAULT_ORG_ID,
                    "environment": DEFAULT_ENV,
                    "cost_center": dept["cost_center"],
                    "service_owner": dept["service_owner"],
                    "department": dept["department"],
                }

                # Record Slack Active Users
                slack_active_users_gauge.set(
                    slack_count,
                    attributes={**common_attributes, "tier": dept["tier"]},
                )

                # Record GitHub Open PRs & Merges
                github_open_prs_gauge.set(
                    open_prs,
                    attributes={
                        **common_attributes,
                        "repository": dept["repo"],
                        "team": dept["team"],
                    },
                )
                if merges_increment > 0:
                    github_pr_merges_counter.add(
                        merges_increment,
                        attributes={
                            **common_attributes,
                            "repository": dept["repo"],
                            "team": dept["team"],
                        },
                    )

                # Record Jira Tickets
                jira_tickets_open_gauge.set(
                    open_jira,
                    attributes={
                        **common_attributes,
                        "project": dept["jira_project"],
                        "priority": random.choice(["high", "medium", "urgent"]),
                    },
                )

                # Record Daily Cloud Spend
                cloud_cost_daily_gauge.set(
                    daily_cost,
                    attributes={
                        **common_attributes,
                        "provider": "aws" if dept["cost_center"] != "data-platform" else "gcp",
                    },
                )

                print(
                    f"[{datetime.now().strftime('%H:%M:%S')}] Metrics Recorded | "
                    f"Dept={dept['department']} | Slack={slack_count} | OpenPRs={open_prs} | "
                    f"Jira={open_jira} | DailyCost=${daily_cost}"
                )

        except Exception as ex:
            print(f"[workplace-analytics] Error in metrics loop: {ex}")

        time.sleep(INTERVAL_SECONDS)


if __name__ == "__main__":
    main()

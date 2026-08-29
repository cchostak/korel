# ADR 0003: Service Level Objectives (SLOs), SLAs, Error Budgets & Alerting Strategy

## Status
**Accepted** (2026-08-29)

## Context
As the Korel platform scales across multi-tenant corporate environments, operational alerting cannot rely on raw threshold alerts on single-point metric spikes (which cause alert fatigue, high false-positive rates, and missed outages).

To guarantee high reliability, predictable error budgeting, and actionable on-call escalations, we need a formalized **Service Level Objective (SLO), Service Level Agreement (SLA), Error Budgeting, and Multi-Window Multi-Burn-Rate Alerting Architecture** following Google SRE principles.

## Decision
We implement a four-pillar reliability and alerting framework:

### 1. Mathematical SLO & Error Budget Formulation
- **Availability Target**: $99.9\%$ successful transaction execution over a rolling 30-day window.
  $$\text{SLO Availability} = \frac{\sum \text{successful orders}}{\sum \text{total orders}} \ge 0.999$$
- **Error Budget**: The allowable failure fraction is $1 - 0.999 = 0.001$ ($0.1\%$).
- **Multi-Window Multi-Burn-Rate Alerting**:
  Instead of static error rate thresholds, we calculate the rate at which the error budget is consumed:
  $$\text{Burn Rate} = \frac{1 - \text{Availability Ratio}}{0.001}$$
  - **Fast Burn (Critical Alert)**: $14.4\times$ burn rate over 1 hour ($2\%$ budget consumed in 1h, exhausting budget in 2 days). Routes immediately to on-call paging with 5-minute wait.
  - **Slow Burn (Warning Alert)**: $6.0\times$ burn rate over 6 hours ($5\%$ budget consumed in 6h, exhausting budget in 5 days). Routes to team channels.

### 2. Service Level Agreements (SLAs) & Targets
| Pillar | Metric / Indicator | SLO Target | SLA Commitment | Escalation Policy |
| :--- | :--- | :--- | :--- | :--- |
| **Availability** | Order Workflow Success Rate | $99.95\%$ (30d) | $99.9\%$ (30d) | PagerDuty / On-Call Webhook |
| **Latency QoS** | Workflow Execution Time | $95\% \le 250\text{ms}$ | $99\% \le 500\text{ms}$ | SRE Team Queue |
| **FinOps Cost** | Daily Infrastructure Spend | $\le \$5,000/\text{day}$ | $\le \$6,500/\text{day}$ Hard Cap | FinOps Slack & Finance Escalation |
| **Pipeline Health** | Collector Dropped Spans/Logs | $0$ dropped | $99.99\%$ Ingestion | Platform Core Squad |
| **Workplace GRC** | Urgent Incident Ticket Backlog | $\le 20$ open | $\le 35$ open | Engineering Leadership Review |

### 3. Unified Prometheus Recording & Alerting Rules
- Recording rules in `config/prometheus-rules.yml` pre-aggregate multi-window availability ratios (`1h`, `6h`, `1d`, `7d`), remaining budget percentages, and percentiles to optimize dashboard render speeds.
- Alerting rules use standardized labels (`severity`, `tier`, `category`, `service`, `team`) and link directly to runbooks.

### 4. Grafana Alerting Provisioning & Notification Routing
- Provisioned in `config/grafana/provisioning/alerting/alerting.yaml` with contact points (`corporate-oncall-pager`, `corporate-finops-alerts`, `corporate-sre-team`).
- Notification policy tree routes critical alerts with 15-minute repeat intervals and finops alerts with cost center grouping.

## Consequences

### Positive
- Prevents alert fatigue by firing only when error budgets are at genuine risk of depletion.
- Standardizes SLA reporting for executive leadership and compliance auditors (SOC 2, ISO 27001).
- Provides a dedicated Grafana dashboard (`slo-sla-error-budgets`) for instant visualization of remaining error budgets and burn rates.

### Negative / Operational Tradeoffs
- Requires Prometheus rule evaluation overhead (minimal, evaluated at 5s/15s intervals).
- Initial tuning of burn rate windows requires consistent synthetic traffic generation in staging environments.

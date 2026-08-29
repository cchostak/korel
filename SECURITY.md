# Security Policy — Korel Corporate Telemetry Platform

The Korel platform handles cross-organizational operational metrics, cloud asset metadata, and distributed transaction logs. Maintaining the confidentiality, integrity, and availability of this telemetry stream is critical.

---

## 1. Supported Versions

Security updates and vulnerability patches are published for active releases:

| Version | Supported | Minimum OpenTelemetry Collector Version |
| :--- | :--- | :--- |
| `1.0.x` | :white_check_mark: Yes | `>= 0.100.0` (Contrib) |
| `< 1.0.0` | :x: No | Deprecated |

---

## 2. Reporting a Vulnerability

If you discover a security vulnerability, **do not open a public issue or discussion**. Please follow our responsible disclosure workflow:

1. **Email Security Team:** Submit details to `security@corp.internal` or via our secure portal.
2. **Include Key Evidence:**
   - Detailed description of the vulnerability.
   - Affected components (e.g., OTel Collector, Business Service, Loki/Tempo storage).
   - Minimal reproduction script or curl commands.
   - Potential impact (e.g., telemetry spoofing, cross-tenant data leakage, denial of service).
3. **PGP Encryption:** For sensitive disclosures, encrypt your email using our Platform Security PGP key (`0x4A8B9C1D`).

---

## 3. Vulnerability Response SLAs

Our Security Response Team commits to the following timelines:

| Stage | Response Target |
| :--- | :--- |
| **Initial Acknowledgement** | Within 24 hours |
| **Severity & Impact Triage** | Within 48 hours |
| **Patch Development & Testing** | Critical: 72 hours · High: 7 days · Moderate: 14 days |
| **Public Advisory Release** | Coordinated with downstream consumers |

---

## 4. Platform Security Architecture

When deploying the Korel platform into enterprise production environments:

- **Egress Firewalling:** OpenTelemetry Collector and storage engines should reside within private VPC subnets with default-deny outbound internet access.
- **Strict Network Segmentation:** Expose collector ingestion ports (`:4317` gRPC and `:4318` HTTP) only to authenticated workload subnets.
- **Secret Isolation:** Do not hardcode credentials in configuration manifests or environment variables. Inject sensitive tokens via cloud secrets managers (AWS Secrets Manager, HashiCorp Vault).
- **Log & Trace Sanitization:** Ensure the OpenTelemetry Collector's `transform` processor sanitizes or drops Personally Identifiable Information (PII) and secret tokens before long-term persistence in Loki/Tempo.
- **RBAC & Authentication:** Enforce OIDC/OAuth2 authentication on Grafana and Prometheus query interfaces in non-local environments.

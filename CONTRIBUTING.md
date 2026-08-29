# Contributing to Korel Corporate Telemetry Platform

Thank you for contributing to the **Korel Corporate Telemetry Platform**! We welcome contributions to improve telemetry pipelines, client generator fidelity, observability dashboards, and developer tooling.

---

## 1. Prerequisites

Ensure your local development environment meets the following requirements:

- **Docker:** Engine 20.10+ & Docker Compose v2.0+
- **Go:** 1.22+ (for `clients/business-service`)
- **Python:** 3.12+ (for `clients/cloud-inventory`, `clients/workplace-analytics`, and test harness)
- **Make:** GNU Make 4.0+
- **CLI Tools:** `curl`, `jq`, `git`

---

## 2. Local Setup & Workflow

1. **Clone the repository:**
   ```bash
   git clone https://github.com/corp/korel.git
   cd korel
   ```

2. **Verify your local toolchain:**
   ```bash
   make doctor
   ```

3. **Initialize configuration:**
   ```bash
   make init
   ```

4. **Install pre-commit hooks:**
   ```bash
   pre-commit install
   ```

5. **Start the local telemetry stack:**
   ```bash
   make up
   ```

6. **Verify platform endpoints:**
   ```bash
   make observe
   ```

---

## 3. Branching & Commit Conventions

### Branch Names
- `feat/<short-description>` — New features or telemetry generators
- `fix/<short-description>` — Bug fixes or pipeline corrections
- `sec/<short-description>` — Security patches or policy enhancements
- `docs/<short-description>` — Documentation or ADR additions
- `chore/<short-description>` — Dependency upgrades or tooling changes

### Conventional Commits
All commit messages must follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```text
<type>(<optional scope>): <description>

[optional body]

[optional footer(s)]
```

**Allowed types:**
- `feat:` A new feature or instrument
- `fix:` A bug fix or pipeline correction
- `docs:` Documentation only changes
- `chore:` Tooling, manifests, or dependency updates
- `ci:` CI/CD pipeline modifications
- `sec:` Security fixes and policy updates
- `test:` Adding or refactoring tests

---

## 4. Testing & Quality Verification

Before submitting a Pull Request, run the local verification suite:

```bash
# 1. Format code across all languages
make fmt

# 2. Run static analysis, linters, and vetters
make check

# 3. Execute unit tests
make test-unit

# 4. Run end-to-end integration smoke tests
make test-smoke

# 5. Run full local security audit
make scan
```

---

## 5. Pull Request Lifecycle

1. Open a PR against the `main` branch.
2. Complete the PR template, referencing any linked issues.
3. Ensure all GitHub Actions status checks pass (`CI Pipeline`, `Security Scan`).
4. Solicit reviews from the appropriate area owners defined in [`CODEOWNERS`](file:///home/chris/Desktop/korel/CODEOWNERS).
5. All commits will be squash-merged once approved.

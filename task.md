Scenario
You've joined a small platform team that operates a payments product. The team runs a Ruby
on Rails monolith and a handful of supporting services on Google Kubernetes Engine (GKE),
backed by Cloud SQL (PostgreSQL) and Redis. Infrastructure is provisioned with Terraform,
and CI/CD runs on GitHub Actions.
Your task is to design and partially implement a small new service — the Idempotency
Service - and the infrastructure and pipelines needed to ship it safely to production.

Task

Build a small HTTP service that provides idempotency guarantees for payment-related API
requests using lastest ruby and ruby on rails. The intent is that any service in the platform 
can put this in front of a sensitive write operation to safely retry without double-processing.

Functional requirements

• Expose POST /idempotency/check accepting an Idempotency-Key header and a JSON
body.

• On first request for a given key: store the request fingerprint and return 200 with a
token the caller uses to commit a result.

• On a retry with the same key and matching fingerprint: return the previously stored
response.

• On a retry with the same key but a dierent fingerprint: return 409 Conflict.

• Expose POST /idempotency/commit so the caller can persist its actual response
body, status code, and a configurable TTL (default 24h).

• Expose GET /health (liveness) and GET /ready (readiness - must verify
dependencies).

Non-functional requirements

• Concurrent retries with the same key must not race - exactly one request gets the
"first request" treatment.

• p99 latency target under 50ms at 200 RPS on modest hardware.

• Graceful shutdown - drain in-flight requests on SIGTERM.

• Structured JSON logs with a request_id propagated from an X-Request-Id header.

• Storage. PostgreSQL, Redis, or both - justify it.

• How you handle the concurrency requirement

Deliverables

Submit a single Git repository (GitHub, GitLab, or a tarball) containing the following four
parts. The repo's top-level README should orient us — what's where, what trade-os you
made, and what you'd do next.
1. The service
   • Working code for the endpoints described above.
   • A Dockerfile that produces a slim production image.
   • docker-compose.yml (or equivalent) that brings the service up locally with its
   dependencies.
   • Tests for the concurrency behavior - this is the hard part of the problem, so we want
   to see how you'd prove it works.
2. Kubernetes manifests
   Provide manifests (raw YAML, Helm chart, or Kustomize overlay — your choice) for deploying
   the service to GKE. We expect to see:
   • Deployment with resource requests/limits, liveness and readiness probes wired to
   your endpoints.
   • Service and an Ingress (or Gateway) appropriate for GKE.
   • HorizontalPodAutoscaler with a sensible target metric.
   • PodDisruptionBudget.
   • A documented strategy for secrets (do not commit secrets — explain how they're
   injected at runtime).
   • ServiceAccount with Workload Identity if your service needs to reach any GCP API.
3. GitHub Actions pipeline
   A workflow (or set of workflows) that:
   • Runs tests and a linter on every PR.
   • Builds and pushes the container image to Artifact Registry on merge to main, tagged
   with the commit SHA.
   • Deploys to a staging environment automatically, and to production with a manual
   approval gate.
   • Uses Workload Identity Federation rather than long-lived service account keys.
   The workflow doesn’t have to actually run successfully against real infrastructure — we'll
   read the YAML.
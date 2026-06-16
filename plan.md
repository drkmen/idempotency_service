Summary plan — Ruby on Rails Idempotency Service (high level + milestones)
Overview (1 line)
•
Rails API app that uses Redis for fast concurrency coordination and PostgreSQL for durable committed responses (TTL), exposing /idempotency/check, /idempotency/commit, /health, /ready.
Architecture decisions (short)
•
Redis: SETNX or Lua script to atomically claim "first request" and store fingerprint for quick comparisons (meets p99 latency).
•
Postgres: durable storage of committed response (body, status, expires_at) with index on idempotency_key.
•
Logging: structured JSON (lograge or semantic_logger), propagate X-Request-Id.
•
Graceful shutdown: Puma + rack shutdown hooks to drain in-flight requests.
Step-by-step milestones
1)
Project scaffold
•
Create Rails API app, gems (redis, pg, active_model_serializers, lograge, rspec), initial README.
2)
Data model + schema
•
Create IdempotencyRecord (key, fingerprint, response_body jsonb, status, expires_at, created_at).
•
Migrations, DB indexes, TTL job (ActiveJob + sidekiq or pg cron).
3)
/idempotency/check
•
Controller: validate header/body, compute fingerprint, run Redis Lua: atomically
◦
If no lock: store fingerprint in Redis and return 200 + token
◦
If lock exists and fingerprint matches → fetch committed response (if any) or return "in-flight" token
◦
If fingerprint differs → 409
4)
/idempotency/commit
•
Verify token, persist response in Postgres, set expires_at, remove Redis lock.
5)
Concurrency handling & tests
•
Implement Redis Lua scripts for atomic compare-and-set.
•
RSpec + concurrency tests (multi-thread/process) to assert exactly-one-winner, responses and 409 cases. Include stress test script (wrk or ruby threads) targeting 200 RPS.
6)
Local infra + containerization
•
Dockerfile (slim), docker-compose (rails + postgres + redis), make targets.
7)
Kubernetes manifests
•
Deployment (resources, probes), Service, Ingress, HPA, PDB, ServiceAccount + docs for secrets via Workload Identity / Kubernetes Secrets + HashiCorp Vault option.
8)
CI/CD
•
GitHub Actions: PR lint/test, build/push image to Artifact Registry (SHA tag) on merge, deploy to staging, manual gate for prod; use Workload Identity Federation for auth.
9)
Observability & readiness
•
/health liveness; /ready checks DB and Redis. Add metrics (Prometheus client) and structured logs.
10)
Documentation & deliverables
•
Top-level README: architecture, trade-offs, runbook, how to run tests, how to deploy, next improvements.
Next step (no question)
•
Start implementing the plan (scaffold app, migrations, controllers). Say “start” if implementation should begin.
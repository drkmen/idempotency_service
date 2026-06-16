Secrets strategy

- Do NOT commit secrets to git.
- Recommended: store secrets in Google Secret Manager and inject into pods using either:
  - Workload Identity + Secret Manager CSI driver (recommended): mounts secrets as files at runtime.
  - External secrets (ExternalSecrets Operator) to sync into Kubernetes Secrets from Secret Manager.
- Alternative: HashiCorp Vault with Kubernetes auth.

Runtime injection example (Secret Manager CSI driver):
- Create secret in Secret Manager
- Configure a SecretProviderClass and mount into pod as a file
- Read values in container at startup and populate env vars/config

For local development use docker-compose with environment variables loaded from a .env file (do not commit .env).

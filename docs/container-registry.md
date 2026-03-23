# Container Registry

For private Git repository access, see [argocd-guide.md](argocd-guide.md#private-git-repositories).

## GHCR support

Set these variables and re-run Stage 2 `terraform apply`:

```bash
export TF_VAR_ghcr_username="your-github-user-or-org"
export TF_VAR_ghcr_token="ghp_xxxxxxxxxxxxxxxxxxxx"
```

## Scope

The kit creates `ghcr-secret` in the `demo` namespace only. Create a namespace-local image pull secret in every namespace that needs one.

## Verification

```bash
kubectl get secret ghcr-secret -n demo
# If demoApp is enabled:
kubectl get deploy -n demo demo-app -o yaml | grep -n imagePullSecrets
```

## Other registries

1. Create a namespace-local image pull secret
2. Reference it from the workload values or manifests
3. Store the source credentials in Terraform bootstrap or your ESO backend

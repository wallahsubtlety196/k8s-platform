# Troubleshooting

## Terraform bootstrap

### OVH OpenStack auth fails

`TF_VAR_openstack_tenant_name` must be the OVH project UUID, not the project
display name.

### Hetzner remote state fails with `400 InvalidArgument`

Keep `encrypt = false` in all three:

- `terraform/clusters/hetzner-starter/cluster/backend.tf`
- `terraform/clusters/hetzner-starter/addons/backend.tf`
- `terraform/clusters/hetzner-starter/addons/providers.tf`

Hetzner has no state locking. Do not run concurrent applies.

### Hetzner addons plan fails before reading remote state

Set all three state variables:

- `TF_VAR_state_bucket`
- `TF_VAR_state_region`
- `TF_VAR_state_endpoint`

`state_endpoint` is required for Hetzner.

## ArgoCD sync

### Root app points at the right branch but old content is still live

```bash
kubectl get application -n argocd root -o jsonpath='{.status.sync.revisions}'
kubectl get application -n argocd root -o jsonpath='{.spec.sources[*].targetRevision}'
```

### Child app keeps retrying

Usually: missing CRD, bad values, missing secret, or AppProject restriction.

## Ingress and DNS

### Browser cannot resolve a hostname

Verify the hostname resolves in public DNS before investigating `external-dns`.

### OVH or Hetzner ingress shows the load balancer IP as the client

Proxy protocol is not configured end to end.

## Secrets and auth

### ESO exists but Secrets do not sync

```bash
kubectl get clustersecretstore
kubectl get externalsecret -A
kubectl logs -n external-secrets deploy/external-secrets
```

Common causes: wrong vault name/UUID, incorrect item title or field name, missing `TF_VAR_onepassword_service_account_token`.

### Prometheus and Alertmanager return `401`

Use `prometheus-<cluster>` / `alertmanager-<cluster>` browser-login items (team-logins vault) or credentials from `monitoring-basic-auth-<cluster>` in the infra vault. With Grafana OAuth or ArgoCD OIDC enabled, browser-login items move to the infra vault.

### Grafana password does not update

Grafana applies the admin password at first startup only. To reset: delete the `grafana-admin` Secret, restart the Grafana pod, then re-run Stage 2.

## Data and backups

### CNPG restore fails with missing WAL

Examine restore pod logs for WAL archival errors. Verify `wals/` segments exist in object storage.

## Longhorn (Hetzner)

Check volume and replica health:

```bash
kubectl -n longhorn-system get volumes
kubectl -n longhorn-system get replicas
kubectl -n longhorn-system get nodes
```

Common issues:

- **PVC stuck Pending**: check `kubectl describe pvc <name>` — usually a missing storage class or no schedulable storage node
- **Degraded volume**: a replica is on a failed/cordoned node. Longhorn rebuilds automatically when a healthy node is available
- **Disk pressure**: `storageMinimalAvailablePercentage` is 15% — Longhorn stops scheduling new replicas below that threshold

---

## Teardown

See the teardown section in your cloud quickstart:

- [OVH teardown](quickstart-ovh.md#teardown)
- [Hetzner teardown](quickstart-hetzner.md#teardown)


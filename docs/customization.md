# Customization

## Where to change things

- `argocd/values.yaml`: shared defaults
- `clusters/<cluster>/values.yaml`: per-cluster overrides
- `clusters/<cluster>/cnpg-values.yaml`: per-cluster CNPG overrides (database name, storage size, replicas, backup schedule, pooler settings)
- `values/<component>/values.yaml`: component-specific Helm values
- `values/<component>/values-<cloud>.yaml`: cloud-specific component overrides
- `terraform/clusters/<cluster>/cluster/terraform.tfvars`: cloud and cluster infrastructure
- `terraform/clusters/<cluster>/addons/terraform.tfvars`: ArgoCD bootstrap inputs

## Component toggles

Current toggles live under `components:` in `argocd/values.yaml`:

- `certManager`
- `externalSecrets`
- `platformSecrets`
- `bootstrapSecrets`
- `traefik`
- `externalDns`
- `monitoring`
- `grafanaOAuth`
- `monitoringMiddleware`
- `argocdIngress`
- `demoApp`
- `cnpg`
- `dragonfly`
- `typesense`
- `nats`
- `platformAlerts`

Example:

```yaml
components:
  demoApp: false
  cnpg: true
```

## Versions

Pinned chart versions also live in `argocd/values.yaml`.

Change a version there, commit, and let ArgoCD reconcile it.

## Common changes

### Change the cluster issuer

```yaml
# clusters/<cluster>/values.yaml
clusterIssuer: "letsencrypt-production"
```

### Enable or disable the demo app

```yaml
components:
  demoApp: true
```

### Enable CNPG

Set `cnpg: true` in `clusters/<cluster>/values.yaml` and `cnpg_enabled = true` in your addons `terraform.tfvars`:

```yaml
# clusters/<cluster>/values.yaml
components:
  cnpg: true
```

```hcl
# terraform/clusters/<cluster>/addons/terraform.tfvars
cnpg_enabled = true
```

CNPG backups require object storage. Set `enable_object_storage = true` in your cluster `terraform.tfvars` if it isn't already. See [backups.md](backups.md) for backup configuration.

### Change Traefik or monitoring values

Edit the component values directly:

- `values/traefik/values.yaml`
- `values/kube-prometheus-stack/values.yaml`
- `values/loki/values.yaml`

Example: Traefik replica count belongs under `deployment.replicas`, not a
top-level `replicas` key.

## Adding an application

### From this repo (monorepo pattern)

1. Create a Helm chart or Kustomize overlay under `values/<your-app>/`
2. Add an ArgoCD Application in `argocd/templates/applications.yaml`:

   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: my-app
     namespace: argocd
     annotations:
       argocd.argoproj.io/sync-wave: "3"
   spec:
     project: apps
     sources:
       - repoURL: {{ "{{ .Values.repoURL }}" }}
         targetRevision: {{ "{{ .Values.targetRevision }}" }}
         path: values/my-app
     destination:
       server: https://kubernetes.default.svc
       namespace: my-app
     syncPolicy:
       automated:
         prune: true
         selfHeal: true
       syncOptions:
         - CreateNamespace=true
   ```

3. Commit and push — ArgoCD syncs automatically.

### From a separate repo (multi-repo pattern)

```yaml
spec:
  project: apps
  source:
    repoURL: https://github.com/your-org/your-app
    targetRevision: main
    path: k8s/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
```

If the repo is private, set `github_token` in the addons stage. See
[argocd-guide.md](argocd-guide.md#private-git-repositories).

- For private images: [container-registry.md](container-registry.md)
- `values/demo-app/` provides ingress, TLS, health checks, and database credential injection patterns

## Changing cluster infrastructure

Edit the cluster-stage `terraform.tfvars`, then apply Stage 1 again:

```bash
terraform -chdir=terraform/clusters/$CLUSTER/cluster apply
```

Typical examples:

- OVH node flavor or autoscaling limits
- Hetzner server type or node counts
- enabling Hetzner storage nodes
- enabling managed PostgreSQL on OVH

## Database contract

The cluster stage exports `database_host`, `database_port`, `database_name`, `database_username`, `database_password`. The addons stage turns those into the bootstrap secret contract consumed by the demo app and related workloads.

## Database options

| Option | Provider | Managed by | Best for |
|--------|----------|------------|----------|
| Managed PostgreSQL | OVH only | OVH | Operational simplicity, built-in HA and backups |
| CNPG | Any cloud | You (via operator) | Full control, lower cost, multi-cloud portability |

**Managed PostgreSQL** — set `database_provider = "managed"` in cluster
`terraform.tfvars`. See [quickstart-ovh.md](quickstart-ovh.md) for setup.

**CNPG** — set `cnpg: true` in `clusters/<cluster>/values.yaml` and configure
backups. See [backups.md](backups.md) for backup/restore/tuning.

## Connection pooling

The CNPG chart deploys a PgBouncer pooler by default in transaction mode (`values/cnpg/cluster/values.yaml`):

```yaml
pooler:
  enabled: true
  type: rw
  instances: 2
  pgbouncer:
    poolMode: transaction
    parameters:
      max_client_conn: "1000"
      default_pool_size: "20"
```

Applications connect through the pooler service instead of the cluster service directly. Find the service name:

```bash
kubectl get svc -n database -l cnpg.io/poolerName
```

PgBouncer maintains a pool of `default_pool_size` backend connections per database/user combination, shared across up to `max_client_conn` application connections.

### When to adjust

- **High connection count**: increase `max_client_conn` and add pooler instances
- **Long transactions or prepared statements**: switch `poolMode` to `session` (disables connection sharing)
- **Read-heavy workloads with replicas**: create a separate Pooler manifest with `type: ro` in `values/cnpg/cluster/templates/` (the current template only renders one pooler)

### Disabling the pooler

```yaml
pooler:
  enabled: false
```

Applications then connect directly to the CNPG cluster service.

## Storage class abstraction

Components use the cluster default storage class. On Hetzner with dedicated nodes, the addons stage can create portable aliases for tiered storage:

| Alias | Backing | Use case |
|-------|---------|----------|
| `fast-rwo` | Longhorn (local NVMe) | PostgreSQL, search indexes |
| `standard-rwo` | Hetzner CSI (network) | Message queues, general workloads |

Enable in `terraform.tfvars`:

```hcl
enable_storage_class_aliases = true
enable_storage_nodes         = true    # Longhorn needs dedicated nodes
longhorn_replica_count       = 2       # Match your storage_node_count for redundancy
```

Then set the storage class in per-cloud value overlays:

```yaml
# values/cnpg/cluster/values-hetzner.yaml
storage:
  storageClass: fast-rwo
```

Aliases work across all clouds. On Hetzner with dedicated storage nodes, `fast-rwo` maps to Longhorn (local NVMe) and `standard-rwo` maps to Hetzner CSI.

## Running CNPG on dedicated storage nodes

When Hetzner storage nodes are enabled, you can pin PostgreSQL to local
NVMe for better I/O performance:

1. Enable storage nodes in `terraform.tfvars`:

   ```hcl
   enable_storage_nodes         = true
   enable_storage_class_aliases = true
   ```

2. Configure CNPG in `values/cnpg/cluster/values-hetzner.yaml`:

   ```yaml
   cluster:
     storage:
       storageClass: fast-rwo
     walStorage:
       storageClass: fast-rwo
     nodeSelector:
       server-usage: storage
     tolerations:
       - key: storage
         operator: Equal
         value: "true"
         effect: NoSchedule
   ```

Both `nodeSelector` and `tolerations` are required — storage nodes are tainted. Omitting either causes CNPG to schedule on regular worker nodes.

The same pattern applies to Typesense and NATS — add matching `nodeSelector` and `tolerations` in their `values-hetzner.yaml` overlays.

## Hetzner firewall rules

Hetzner clusters restrict outbound traffic to DNS (53), HTTP/HTTPS (80, 443), NTP (123), and ICMP. To open additional ports:

```hcl
extra_firewall_rules = [
  {
    direction       = "out"
    port            = "587"
    protocol        = "tcp"
    source_ips      = []
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "Allow outbound SMTP for email services"
  }
]
```

Common ports you may need:

| Port | Protocol | Use case |
|------|----------|----------|
| 587 | TCP | SMTP submission (email sending) |
| 5432 | TCP | PostgreSQL (external database) |
| 6379 | TCP | Redis (external cache) |
| 9093 | TCP | Alertmanager webhook receivers |

## Resource requests and limits

CPU limits are set on high-throughput components (Traefik, Prometheus, Grafana, Loki, Alloy) and omitted on lightweight services (AlertManager, cert-manager, external-dns, external-secrets) to avoid throttling.

Override resources in the component's values file:

```yaml
# values/<component>/values.yaml
resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    memory: 512Mi
```

For CNPG PostgreSQL, resources are in `values/cnpg/cluster/values.yaml` under `cluster.resources`. PostgreSQL parameters are auto-tuned from memory limits — increase `limits.memory` to get larger shared_buffers and effective_cache_size automatically.

### Defaults

| Component | CPU req | Mem req | CPU limit | Mem limit | Values file |
|-----------|---------|---------|-----------|-----------|-------------|
| Traefik | 100m | 128Mi | 500m | 256Mi | `values/traefik/` |
| Prometheus | 200m | 512Mi | 1000m | 2Gi | `values/kube-prometheus-stack/` |
| Grafana | 100m | 256Mi | 500m | 512Mi | `values/kube-prometheus-stack/` |
| AlertManager | 50m | 64Mi | — | 128Mi | `values/kube-prometheus-stack/` |
| Loki (gateway) | 50m | 64Mi | 200m | 128Mi | `values/loki/` |
| Loki (single) | 150m | 384Mi | 750m | 768Mi | `values/loki/` |
| Alloy | 100m | 128Mi | 200m | 256Mi | `values/alloy/` |
| CNPG Operator | 100m | 128Mi | — | 256Mi | `values/cnpg/operator/` |
| CNPG PostgreSQL | 500m | 1Gi | — | 2Gi | `values/cnpg/cluster/` |
| Cert-Manager | 50m | 64Mi | — | 128Mi | `values/cert-manager/` |
| External DNS | 25m | 32Mi | — | 128Mi | `values/external-dns/` |
| External Secrets | 25m | 128Mi | — | 256Mi | `values/external-secrets/` |
| Demo App | 10m | 32Mi | — | 64Mi | `values/demo-app/` |

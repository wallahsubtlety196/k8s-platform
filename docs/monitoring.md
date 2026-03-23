# Monitoring

The kit ships:

- Prometheus
- Grafana
- Alertmanager
- Loki
- Alloy

## Defaults

- Prometheus retention: `15d`
- Prometheus retention size: `40GB`
- Loki retention: `168h` (`7d`)
- Prometheus control-plane scraping disabled for managed cluster components

> Loki requires S3 object storage. Set `enable_object_storage = true` in Stage 1 cluster `terraform.tfvars` before the first apply.
>
> Loki resolves bucket names from `clusters/<cluster>/loki-values.yaml`. On OVH, Terraform populates bucket names into the ArgoCD overlay automatically. On Hetzner, bucket names are written to `clusters/<cluster>/loki-values.yaml` by the object storage module output — verify this file exists and contains your actual bucket names after Stage 1.

## Alerts

The kit ships with `platform-alerts`, a set of PrometheusRule alert rules enabled by default.

### Default alert rules

**Critical:**

| Alert | Fires when | For |
|-------|-----------|-----|
| NodeDown | Node exporter unreachable | 5m |
| DiskSpaceLow | Disk below 10% free | 5m |
| PodCrashLooping | Pod restarts > 5 in 1h | 5m |
| TraefikAllReplicasDown | Zero Traefik pods ready | 1m |
| NodeNetworkUnavailable | Node network not configured | 2m |
| PVCUsageCritical | PVC > 90% full | 5m |
| PostgreSQLDown | CNPG cluster unreachable (when enabled) | 2m |
| PostgreSQLBackupFailure | Last CNPG backup failed (when enabled) | 5m |

**Warning:**

| Alert | Fires when | For |
|-------|-----------|-----|
| TraefikDegraded | Fewer ready replicas than desired | 5m |
| TraefikPodRestarting | > 3 restarts in 1h | 5m |
| TraefikHighMemoryUsage | > 80% of memory limit | 10m |
| TLSCertificateExpiring | Certificate expires in < 14 days | 1h |
| PVCUsageWarning | PVC > 80% full | 15m |
| NodeMemoryPressure | Node condition true | 5m |
| NodeDiskPressure | Node condition true | 5m |
| NodePIDPressure | Node condition true | 5m |
| CPUThrottlingHigh | > 50% throttling | 15m |

Data layer alerts (DragonflyDB, NATS, Typesense) activate when the corresponding service is enabled in `clusters/<cluster>/values.yaml`.

### Tuning thresholds

Edit `values/platform-alerts/values.yaml`:

```yaml
thresholds:
  diskSpaceLowPercent: 10
  pvcUsageWarningPercent: 80
  pvcUsageCriticalPercent: 90
  cpuThrottlingPercent: 50
  podRestartCount: 5
  tlsCertExpiryDays: 14
```

### Adding custom alerts

Create a new PrometheusRule in `values/platform-alerts/templates/`. Use the existing files as a reference for the required labels (`app: kube-prometheus-stack`, `release: prometheus-stack`). Commit and push — ArgoCD syncs the new rules automatically.

### Disabling alerts

```yaml
components:
  platformAlerts: false
```

## Access

Grafana:

- `https://grafana-<cluster>.<domain>`

Prometheus and Alertmanager:

- `https://prometheus-<cluster>.<domain>`
- `https://alertmanager-<cluster>.<domain>`

## Credentials

See [credential-flow.md](credential-flow.md) for the full item lifecycle:

- Grafana: `grafana-admin` Secret (bootstrap), `grafana-admin-<cluster>` 1Password item (browser login)
- Prometheus / Alertmanager: `monitoring-basic-auth` Secret, protected by `monitoringMiddleware`

Break-glass Grafana password:

```bash
terraform -chdir=terraform/clusters/$CLUSTER/addons output -raw grafana_admin_password
```

## Verification

```bash
kubectl get pods -n monitoring
kubectl get ingress -n monitoring
kubectl get secret -n monitoring grafana-admin
kubectl get secret -n monitoring monitoring-basic-auth
```

Auth checks:

```bash
curl -skI https://prometheus-<cluster>.<domain>
curl -skI https://alertmanager-<cluster>.<domain>
curl -sku "<username>:<password>" -I https://prometheus-<cluster>.<domain>
curl -sku "<username>:<password>" -I https://alertmanager-<cluster>.<domain>
```

In Grafana, confirm:

- Prometheus datasource works
- Loki datasource exists
- logs are visible in Explore

## Querying logs

Go to **Grafana → Explore → Loki datasource**.

Example LogQL queries:

```
{namespace="demo"} |= "error"
{namespace="demo", container="demo-app"} | json
{app="traefik"} |= "500"
```

Available stream labels: `namespace`, `pod`, `container`, `app`,
`app_kubernetes_io_name`, `node`, `cluster`.

Log retention: 7 days. Set `retention_period` in `values/loki/values.yaml` to change.

## Routing alerts

AlertManager ships with a `null` receiver — alerts appear in the UI but no notifications are sent. Configure a receiver to route alerts externally.

All receiver secrets follow the same pattern:

1. Create a 1Password item with the credentials
2. Enable the corresponding entry in `clusters/<cluster>/bootstrap-secrets.yaml`
3. Configure the receiver in `values/kube-prometheus-stack/values.yaml`
4. Mount the secret via `alertmanagerSpec.secrets`
5. Commit and let ArgoCD sync

### Slack

1. Create a Slack incoming webhook for your alerts channel.
2. Create a 1Password item named `alertmanager-slack-<cluster>` in your infra vault with a field `webhook_url` containing the Slack webhook URL.
3. Enable the secret in `clusters/<cluster>/bootstrap-secrets.yaml`:

   ```yaml
   alertmanagerSlackWebhook:
     enabled: true
   ```

4. Uncomment the Slack receivers, routes, and `secrets` mount in `values/kube-prometheus-stack/values.yaml`.
5. Commit and push.

The commented config routes `severity=critical` alerts to `#alerts-critical` (4h repeat) and `severity=warning` to `#alerts` (12h repeat). Adjust the channel names and repeat intervals for your team.

### PagerDuty

Create a 1Password item with a `routing_key` field, add it to `bootstrap-secrets`, and configure the receiver:

```yaml
receivers:
  - name: 'pagerduty'
    pagerduty_configs:
      - routing_key_file: /etc/alertmanager/secrets/pagerduty-routing-key/routing_key
        severity: '{{ .CommonLabels.severity }}'
```

Mount the secret:

```yaml
alertmanagerSpec:
  secrets:
    - pagerduty-routing-key
```

### incident.io

Use their AlertManager webhook integration:

```yaml
receivers:
  - name: 'incident-io'
    webhook_configs:
      - url: 'https://api.incident.io/v2/alert_events/alertmanager'
        http_config:
          authorization:
            credentials_file: /etc/alertmanager/secrets/incident-io-api-key/api_key
```

### Other receivers

See the [AlertManager documentation](https://prometheus.io/docs/alerting/latest/configuration/) for Opsgenie, email, Microsoft Teams, and others. The secret pattern is the same — 1Password item, bootstrap-secrets entry, receiver config, secret mount.

## Common issues

- `401` from Prometheus or Alertmanager: ingress auth is working — use the monitoring credentials
- Grafana password changed in 1Password but login fails: Grafana applies the admin password on first startup only
- Loki datasource missing: check `kube-prometheus-stack` and `loki` application sync status

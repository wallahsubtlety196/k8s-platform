# OVH Cloud Quickstart

Deploy a cluster on OVH Cloud using Terraform. Covers local and GitHub Actions CI.

## 1. Prerequisites

Install:

- `terraform` (~> 1.14)
- `kubectl`
- `helm`
- `aws` CLI (for S3-compatible state backend and object-storage checks)
- `op` CLI (optional, for reading 1Password items locally)

Verify:

```bash
terraform version
kubectl version --client
helm version
aws --version
```

**Required accounts:**

- **Cloudflare** -- a domain managed in Cloudflare for DNS automation. [Create an API token](https://dash.cloudflare.com/profile/api-tokens) using the "Edit zone DNS" template, scoped to your domain's zone.
- **1Password** -- a service account with read/write access to an infrastructure vault. Create one in your 1Password admin console under Developer > Service Accounts. You need the vault **name** (e.g. `Starter Kit Infra`) or the vault **UUID** (visible in the URL at Settings > Vaults) — either one works. Also set up a **team logins vault** (can be the same vault or a separate one shared with your team) — Terraform writes browser-login items here for ArgoCD, Grafana, Prometheus, and Alertmanager so your team can log in via 1Password.
- **OVH Cloud** -- a Public Cloud project with API access (credentials covered in step 3).

If you plan to use CI (Option B in step 10), you also need admin access to your GitHub fork to create environments and add secrets.

## 2. Fork and clone

ArgoCD tracks your Git repo during Stage 2, so start from your own fork:

```bash
git clone https://github.com/YOUR-ORG/k8s-platform.git
cd k8s-platform
```

## 3. OVH credentials

OVH uses three separate API systems with separate credentials: OVH API (account/resource management), OpenStack (compute/networking), S3 (object storage).

**OVH API token** (for Terraform to manage your Public Cloud project) -- create at [eu.api.ovh.com/createToken/](https://eu.api.ovh.com/createToken/) (EU) or [ca.api.ovh.com/createToken/](https://ca.api.ovh.com/createToken/) (CA). Grant `GET`, `PUT`, `POST`, `DELETE` on `/cloud/project/*`. This gives you an application key, application secret, and consumer key.

```bash
export TF_VAR_ovh_endpoint="ovh-ca"   # or ovh-eu — must match where you created the token
export TF_VAR_ovh_application_key="<application-key>"
export TF_VAR_ovh_application_secret="<application-secret>"
export TF_VAR_ovh_consumer_key="<consumer-key>"
```

**OpenStack credentials** (for Terraform to provision compute, networking, and load balancers) -- in your OVH Control Panel under Public Cloud > your project > Users & Roles, create or select an OpenStack user. Download the RC File v3 from Horizon (API Access tab). You need four values:

```bash
export TF_VAR_openstack_auth_url="https://auth.cloud.ovh.net/v3"
export TF_VAR_openstack_user_name="user-abcdef1234567890"
export TF_VAR_openstack_password="<openstack-password>"
export TF_VAR_openstack_tenant_name="<project-uuid>"
```

`TF_VAR_openstack_tenant_name` must be the project UUID, not the display name.

**S3 credentials** (for Terraform state backend and Loki/CNPG object storage) -- in your OVH Control Panel under Public Cloud > your project > Object Storage, open the Users tab, select your user, and enable S3 to obtain the access key and secret key. These are separate from the OVH API and OpenStack credentials.

## 4. Configure environment

Build your `.env` from the split example files:

```bash
cp .env.shared.example .env
cat .env.ovh.example >> .env
```

Optionally append OIDC and extras:

```bash
cat .env.oidc.example >> .env       # SSO for kubectl, Grafana, ArgoCD
cat .env.extras.example >> .env     # GHCR, GitHub token for private repos
```

Fill in the values using the credentials from step 3, then export:

```bash
source .env
```

Never commit `.env` to git.

### Config surface

Three files control your deployment:

- **`.env`** -- secrets and values shared across stages. Exported as `TF_VAR_*` environment variables. Not committed.
- **`terraform.tfvars`** -- per-stage choices (cluster size, features, domain). One per stage directory.
- **`backend.tf`** -- S3 state backend config (bucket, endpoint, region). Committed. Not secret.

## 5. Create a Terraform state bucket

1. Go to **OVH Control Panel > Public Cloud > Object Storage > Create container**
2. Choose **S3 API** type, pick a region, and name the bucket (e.g., `k8s-state-{random}`). The starter CI workflow defaults to `gra` for the OVH state backend region and endpoint; if your bucket uses a different endpoint, update the OVH addons workflow env blocks as described in [ci.md](ci.md#backend-config). The console shows `GRA`; use lowercase `gra` in `TF_VAR_state_region`.
3. In the container row, open the `...` menu, click **Add user**, then grant your user **Read and write** access to that container.
4. Add the S3 access key and secret key (from the S3 credentials step above) to `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` in your `.env`
5. Set `TF_VAR_state_bucket`, `TF_VAR_state_region`, and `TF_VAR_state_endpoint` in `.env`

`TF_VAR_state_region` is the **bucket** location code (e.g. `gra`), not the cluster region (e.g. `GRA9`).

Re-source after adding the new values:

```bash
source .env
```

## 6. Backend config

Update the `backend "s3"` block in both
`terraform/clusters/ovh-starter/cluster/backend.tf` and
`terraform/clusters/ovh-starter/addons/backend.tf` with your own bucket name and
endpoint.

If you rename the cluster directory or change `cluster_name`, also update the `key` field in both `backend.tf` files and the remote state `key` in `addons/providers.tf` — these are hardcoded to `ovh-starter`.

## 7. Stage 1 config -- cluster

Create the cluster tfvars:

```bash
cp terraform/clusters/ovh-starter/cluster/terraform.tfvars.example \
  terraform/clusters/ovh-starter/cluster/terraform.tfvars
```

Minimum starting point:

```hcl
cluster_name = "ovh-starter"
domain       = "example.com"
```

OVH defaults `enable_object_storage` to `true`, which provisions Loki and CNPG backup buckets automatically.

## 8. Push to fork

Push config changes before Stage 2 — ArgoCD clones your fork and deploys demo defaults if changes aren't committed.

```bash
git add terraform/clusters/ovh-starter/cluster/backend.tf \
       terraform/clusters/ovh-starter/addons/backend.tf \
       clusters/ovh-starter/values.yaml
git commit -m "Configure cluster for my environment"
git push origin main
```

## 9. Stage 2 config -- addons

Create the addons tfvars:

```bash
cp terraform/clusters/ovh-starter/addons/terraform.tfvars.example \
  terraform/clusters/ovh-starter/addons/terraform.tfvars
```

Minimum starting point:

```hcl
argocd_repo_url        = "https://github.com/YOUR-ORG/k8s-platform.git"
argocd_target_revision = "main"

cloud_provider = "ovh"
cluster_name   = "ovh-starter"
domain         = "example.com"

letsencrypt_email = "ops@your-company.com"
# cnpg_enabled    = true   # Optional — see customization.md to enable the data layer
# github_token    = ""   # Only if argocd_repo_url points at a private repo
```

For private repo access, set `github_token`. See [argocd-guide.md](argocd-guide.md#private-git-repositories).

Required environment variables (from [configuration.md](configuration.md)):
`TF_VAR_state_bucket`, `TF_VAR_state_region`, `TF_VAR_state_endpoint`,
`TF_VAR_onepassword_service_account_token`,
`TF_VAR_onepassword_infra_vault_id` (or `TF_VAR_onepassword_infra_vault` — only one is needed),
`TF_VAR_cloudflare_api_token`, `TF_VAR_domain`, `TF_VAR_letsencrypt_email`.

(`OP_SERVICE_ACCOUNT_TOKEN` is auto-aliased from `TF_VAR_onepassword_service_account_token` in `.env.shared.example`.)

## 10. Deploy

### Option A: Deploy locally

Source your environment and apply both stages in order.

**Stage 1 -- cluster:**

```bash
source .env
terraform -chdir=terraform/clusters/ovh-starter/cluster init
terraform -chdir=terraform/clusters/ovh-starter/cluster apply
```

Export kubeconfig:

```bash
terraform -chdir=terraform/clusters/ovh-starter/cluster output -raw kubeconfig > kubeconfig
export KUBECONFIG=$(pwd)/kubeconfig
kubectl get nodes
```

**Stage 2 -- addons:**

```bash
terraform -chdir=terraform/clusters/ovh-starter/addons init
terraform -chdir=terraform/clusters/ovh-starter/addons apply
```

### Option B: Deploy via CI (GitHub Actions)

The included workflow handles both stages sequentially. You need admin access to your GitHub fork to create environments and add secrets.

**1. Create a `production` environment** in Settings > Environments. Add required reviewers to gate applies.

**2. Add secrets** in Settings > Secrets and variables > Actions > Secrets:

| `.env` variable | GitHub Secret |
|---|---|
| `AWS_ACCESS_KEY_ID` (S3 state) | `OVH_S3_ACCESS_KEY` |
| `AWS_SECRET_ACCESS_KEY` (S3 state) | `OVH_S3_SECRET_KEY` |
| `TF_VAR_ovh_application_key` | `OVH_APPLICATION_KEY` |
| `TF_VAR_ovh_application_secret` | `OVH_APPLICATION_SECRET` |
| `TF_VAR_ovh_consumer_key` | `OVH_CONSUMER_KEY` |
| `TF_VAR_openstack_auth_url` | `OPENSTACK_AUTH_URL` |
| `TF_VAR_openstack_user_name` | `OPENSTACK_USER_NAME` |
| `TF_VAR_openstack_password` | `OPENSTACK_PASSWORD` |
| `TF_VAR_openstack_tenant_name` | `OPENSTACK_TENANT_NAME` |
| `TF_VAR_state_bucket` | `OVH_STATE_BUCKET` |
| `TF_VAR_cloudflare_api_token` | `CLOUDFLARE_API_TOKEN` |
| `TF_VAR_onepassword_service_account_token` | `ONEPASSWORD_SERVICE_ACCOUNT_TOKEN` |
| `TF_VAR_onepassword_infra_vault_id` | `ONEPASSWORD_INFRA_VAULT_ID` |

**3. Add variables** in Settings > Secrets and variables > Actions > Variables:

| `.env` variable | GitHub Variable |
|---|---|
| `TF_VAR_cluster_name` | `OVH_CLUSTER_NAME` |
| `TF_VAR_region` | `OVH_CLUSTER_REGION` |
| `TF_VAR_domain` | `OVH_STARTER_DOMAIN` |
| `TF_VAR_argocd_repo_url` | `ARGOCD_REPO_URL` |
| `TF_VAR_argocd_target_revision` | `ARGOCD_TARGET_REVISION` |
| `TF_VAR_letsencrypt_email` | `LETSENCRYPT_EMAIL` |

Optional: `ARGOCD_GITHUB_TOKEN` (secret, for private repos), `ONEPASSWORD_TEAM_LOGINS_VAULT_ID` (secret), OIDC secrets -- see [ci.md](ci.md) for the full list.

**4. Trigger:** Go to **Actions > Terraform Apply > Run workflow**. Select `ovh-starter` and `plan` for a dry run, then re-run with `apply` to deploy.

## 11. Verify and access

```bash
kubectl get applications -n argocd
kubectl get ingress -A
kubectl get pods -A
```

Primary URLs:

- `https://argocd-ovh-starter.<domain>`
- `https://grafana-ovh-starter.<domain>`
- `https://demo-ovh-starter.<domain>` (when `demoApp` is enabled)

Use 1Password browser-login items for current credentials. Terraform outputs show bootstrap values only and do not reflect in-UI changes. See [credential-flow.md](credential-flow.md) for the full item lifecycle.

Break-glass passwords (local deploy only — CI deploys don't expose Terraform outputs, use the 1Password items instead):

```bash
terraform -chdir=terraform/clusters/ovh-starter/addons output -raw argocd_admin_password
echo
terraform -chdir=terraform/clusters/ovh-starter/addons output -raw grafana_admin_password
echo
```

To enable CNPG, set `cnpg: true` under `components:` in `clusters/ovh-starter/values.yaml` and `cnpg_enabled = true` in addons `terraform.tfvars`. CNPG backups require object storage (set in Stage 1).

For a private demo app image, create an `imagePullSecret` in the `demo` namespace before enabling `demoApp`.

### Networking

Stage 1 creates an OpenStack private network (`192.168.100.0/24` by default, configurable via `subnet_cidr`) and attaches the cluster to it with `private_network_routing_as_default = true` — all node traffic routes through the private network, not the public interface. The Traefik load balancer and the Kubernetes API endpoint are the two public entry points (restrict API access with `api_server_ip_restrictions` in your cluster `terraform.tfvars`). If you enable managed PostgreSQL, the database is provisioned inside the same private subnet with no public endpoint.

No Kubernetes NetworkPolicies are installed. Pod-to-pod traffic is unrestricted within the cluster. Add NetworkPolicies if you need namespace-level isolation.

## Next steps

- [Customization](customization.md) -- enable/disable components, add your apps
- [Monitoring](monitoring.md) -- access Grafana and Prometheus, route alerts
- [Credential flow](credential-flow.md) -- understand how secrets work
- [OIDC](oidc.md) -- add SSO for your team

## Managed PostgreSQL (optional)

Uncomment the database block in your cluster `terraform.tfvars`:

```hcl
database_provider = "managed"
database_plan     = "essential"   # essential (1 node), business (2 nodes), enterprise (2 nodes)
database_flavor   = "db1-4"      # db1-4 (4 GB RAM) is the smallest
```

The database connects to your cluster's private network. Stage 1 provisions the instance and exports credentials; Stage 2 creates the `database-credentials` Secret in the `demo` namespace and writes a `database-{cluster}` item to 1Password.

To wire up the demo app's database connection:

```yaml
# clusters/ovh-starter/demo-app-values.yaml
databaseSecret:
  enabled: true
```

```yaml
# clusters/ovh-starter/bootstrap-secrets.yaml
cnpgBackup:
  enabled: true
```

`database_region` is derived from the cluster region (e.g. GRA9 > GRA). Only override it for cross-region database placement.

## Teardown

Destroy in reverse order -- addons first, then cluster:

```bash
# 1. Destroy addons (ArgoCD, platform components)
terraform -chdir=terraform/clusters/ovh-starter/addons destroy -auto-approve

# 2. Destroy cluster infrastructure
terraform -chdir=terraform/clusters/ovh-starter/cluster destroy -auto-approve
```

Destroy includes intentional pauses (60s for external-secrets cleanup, 180s for ArgoCD) — expect it to take several minutes. If destroy fails with a timeout after the pauses, re-run the same command -- transient API errors are common.

Delete stale `heritage=external-dns` TXT records in your Cloudflare dashboard before redeploying to the same domain.

The CI workflow does not include a destroy action. Run teardown locally.

# CI Workflows

## Pull Request Validation (automatic)

Every PR that touches `terraform/`, `argocd/`, or `values/` runs:

- `terraform init -backend=false && terraform validate` for each cluster and addons directory
- `helm lint` on the ArgoCD root chart, demo-app, and cert-manager issuers
- Results posted as a PR comment with per-component pass/fail


## Terraform Apply (manual dispatch)

Runs from the GitHub Actions UI. Pick a cluster (`ovh-starter`, `hetzner-starter`, or `all`) and an action (`plan` or `apply`). Requires a `production` environment and cloud-specific secrets -- configure only the cloud you use.

> **Hetzner prerequisite:** MicroOS Packer snapshots must exist in your Hetzner project before running the workflow. The CI workflow cannot build them -- run `packer build` locally first. See [quickstart-hetzner.md](quickstart-hetzner.md#4-build-microos-snapshots).

## Credential mapping

### Shared secrets (both clouds)

| GitHub Secret | `.env` source | Description |
|---|---|---|
| `CLOUDFLARE_API_TOKEN` | `TF_VAR_cloudflare_api_token` | Cloudflare API token for external-dns |
| `ONEPASSWORD_SERVICE_ACCOUNT_TOKEN` | `TF_VAR_onepassword_service_account_token` | 1Password service account token |
| `ONEPASSWORD_INFRA_VAULT_ID` | `TF_VAR_onepassword_infra_vault_id` | 1Password infrastructure vault UUID |
| `ONEPASSWORD_TEAM_LOGINS_VAULT_ID` | `TF_VAR_onepassword_team_logins_vault_id` | 1Password team logins vault UUID (optional) |
| `ARGOCD_GITHUB_TOKEN` | `TF_VAR_github_token` | GitHub PAT -- repo access for ArgoCD (only for private repos) |

| GitHub Variable | `.env` source | Example |
|---|---|---|
| `ARGOCD_REPO_URL` | `TF_VAR_argocd_repo_url` | `https://github.com/your-org/k8s-platform.git` |
| `ARGOCD_TARGET_REVISION` | `TF_VAR_argocd_target_revision` | `main` |
| `LETSENCRYPT_EMAIL` | `TF_VAR_letsencrypt_email` | `ops@example.com` |
| `OIDC_ADMINS` | `TF_VAR_oidc_admins` | `["admin@example.com"]` |
| `OIDC_VIEWERS` | `TF_VAR_oidc_viewers` | `["viewer@example.com"]` |

### OVH Cloud

**Secrets:**

| GitHub Secret | `.env` source | Description |
|---|---|---|
| `OVH_S3_ACCESS_KEY` | `AWS_ACCESS_KEY_ID` | S3 access key for Terraform state bucket |
| `OVH_S3_SECRET_KEY` | `AWS_SECRET_ACCESS_KEY` | S3 secret key for Terraform state bucket |
| `OVH_APPLICATION_KEY` | `TF_VAR_ovh_application_key` | OVH API application key |
| `OVH_APPLICATION_SECRET` | `TF_VAR_ovh_application_secret` | OVH API application secret |
| `OVH_CONSUMER_KEY` | `TF_VAR_ovh_consumer_key` | OVH API consumer key |
| `OPENSTACK_AUTH_URL` | `TF_VAR_openstack_auth_url` | OpenStack auth endpoint |
| `OPENSTACK_USER_NAME` | `TF_VAR_openstack_user_name` | OpenStack username |
| `OPENSTACK_PASSWORD` | `TF_VAR_openstack_password` | OpenStack password |
| `OPENSTACK_TENANT_NAME` | `TF_VAR_openstack_tenant_name` | OpenStack project/tenant UUID |
| `OVH_STATE_BUCKET` | `TF_VAR_state_bucket` | Name of the S3 bucket holding Terraform state |
| `OVH_OIDC_CLIENT_ID` | `TF_VAR_oidc_client_id` | Google OAuth client ID for cluster-level OIDC (optional) |
| `OVH_KUBECTL_OIDC_CLIENT_ID` | `TF_VAR_kubectl_oidc_client_id` | kubectl OIDC client ID |
| `OVH_KUBECTL_OIDC_CLIENT_SECRET` | `TF_VAR_kubectl_oidc_client_secret` | kubectl OIDC client secret |
| `OVH_ARGOCD_OIDC_CLIENT_ID` | `TF_VAR_argocd_oidc_client_id` | ArgoCD OIDC client ID |
| `OVH_ARGOCD_OIDC_CLIENT_SECRET` | `TF_VAR_argocd_oidc_client_secret` | ArgoCD OIDC client secret |
| `OVH_GRAFANA_OAUTH_CLIENT_ID` | `TF_VAR_grafana_oauth_client_id` | Grafana OAuth client ID |
| `OVH_GRAFANA_OAUTH_CLIENT_SECRET` | `TF_VAR_grafana_oauth_client_secret` | Grafana OAuth client secret |

**Variables:**

| GitHub Variable | `.env` source | Example |
|---|---|---|
| `OVH_CLUSTER_NAME` | `TF_VAR_cluster_name` | `ovh-starter` |
| `OVH_CLUSTER_REGION` | `TF_VAR_region` | `GRA9` |
| `OVH_STARTER_DOMAIN` | `TF_VAR_domain` | `starter.example.com` |
| `OVH_OIDC_ALLOWED_DOMAINS` | `TF_VAR_oidc_allowed_domains` | `example.com` |

### Hetzner Cloud

> The workflow does not set object storage credentials (`TF_VAR_object_storage_access_key`, `TF_VAR_object_storage_secret_key`). If your cluster enables object storage, add these as secrets and update the workflow's env block.

**Secrets:**

| GitHub Secret | `.env` source | Description |
|---|---|---|
| `HETZNER_S3_ACCESS_KEY` | `AWS_ACCESS_KEY_ID` | S3 access key for Terraform state bucket |
| `HETZNER_S3_SECRET_KEY` | `AWS_SECRET_ACCESS_KEY` | S3 secret key for Terraform state bucket |
| `HCLOUD_TOKEN` | `TF_VAR_hcloud_token` | Hetzner Cloud API token |
| `HETZNER_SSH_PUBLIC_KEY` | `TF_VAR_ssh_public_key` | SSH public key contents |
| `HETZNER_SSH_PRIVATE_KEY` | `TF_VAR_ssh_private_key` | SSH private key contents |
| `HETZNER_SSH_KEY_ID` | `TF_VAR_hcloud_ssh_key_id` | Hetzner SSH key ID (to reuse existing key) |
| `HETZNER_STATE_BUCKET` | `TF_VAR_state_bucket` | Name of the S3 bucket holding Terraform state |
| `HETZNER_STATE_ENDPOINT` | `TF_VAR_state_endpoint` | S3 endpoint (e.g., `https://fsn1.your-objectstorage.com`) |
| `HETZNER_OIDC_CLIENT_ID` | `TF_VAR_oidc_client_id` | Google OAuth client ID for cluster-level OIDC (optional) |
| `HETZNER_KUBECTL_OIDC_CLIENT_ID` | `TF_VAR_kubectl_oidc_client_id` | kubectl OIDC client ID |
| `HETZNER_KUBECTL_OIDC_CLIENT_SECRET` | `TF_VAR_kubectl_oidc_client_secret` | kubectl OIDC client secret |
| `HETZNER_ARGOCD_OIDC_CLIENT_ID` | `TF_VAR_argocd_oidc_client_id` | ArgoCD OIDC client ID |
| `HETZNER_ARGOCD_OIDC_CLIENT_SECRET` | `TF_VAR_argocd_oidc_client_secret` | ArgoCD OIDC client secret |
| `HETZNER_GRAFANA_OAUTH_CLIENT_ID` | `TF_VAR_grafana_oauth_client_id` | Grafana OAuth client ID |
| `HETZNER_GRAFANA_OAUTH_CLIENT_SECRET` | `TF_VAR_grafana_oauth_client_secret` | Grafana OAuth client secret |

**Variables:**

| GitHub Variable | `.env` source | Example |
|---|---|---|
| `HETZNER_CLUSTER_NAME` | `TF_VAR_cluster_name` | `hetzner-starter` |
| `HETZNER_STARTER_DOMAIN` | `TF_VAR_domain` | `starter.example.com` |
| `HETZNER_OIDC_ALLOWED_DOMAINS` | `TF_VAR_oidc_allowed_domains` | `example.com` |

### Environment setup

Create a `production` environment in **Settings > Environments**:

1. Click **New environment**, name it `production`
2. Check **Required reviewers** and add at least one team member
3. The Terraform Apply workflow references this environment -- applies will wait for approval

### Backend config

Backend config is committed in each `backend.tf`. The workflow uses plain `terraform init` with S3 credentials from GitHub secrets. Update the `backend "s3"` blocks to point at your own buckets when forking.

The CI workflow hardcodes some state backend values in `.github/workflows/terraform-apply.yml`:

- **OVH** — both `TF_VAR_state_region` (`gra`) and `TF_VAR_state_endpoint` (`https://s3.gra.io.cloud.ovh.net`) are hardcoded in the workflow. No secrets to configure for these.
- **Hetzner** — `TF_VAR_state_region` (`fsn1`) is hardcoded; `TF_VAR_state_endpoint` is read from the `HETZNER_STATE_ENDPOINT` secret.

If your state bucket is in a different region, update the `TF_VAR_state_region` and `TF_VAR_state_endpoint` values in the workflow's env blocks (they appear in both the Plan and Apply steps for addons).

## Testing the workflows

**Apply workflow** -- go to **Actions > Terraform Apply > Run workflow**, select your cluster, and choose `plan` for a dry run.

## Demo App Image (automatic)

The `demo-app.yml` workflow builds and pushes the demo app image to GHCR when files in `demo-app/` change on the default branch. The build and push steps run on forks. The auto-update of the image tag in `values/demo-app/values.yaml` only runs on the original repo. Forks can reuse the workflow for their own GHCR namespace by updating the image reference in `values/demo-app/values.yaml`.

> To use `ovh-ca`, add `TF_VAR_ovh_endpoint` to the workflow env blocks (default is `ovh-eu`).

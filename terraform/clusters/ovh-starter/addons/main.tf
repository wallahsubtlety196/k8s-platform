# --- Cluster name resolution ---

data "onepassword_vault" "infra" {
  count = var.onepassword_infra_vault == "" && var.onepassword_infra_vault_id != "" ? 1 : 0
  uuid  = var.onepassword_infra_vault_id
}

locals {
  cluster_name = var.cluster_name

  onepassword_infra_vault_name = var.onepassword_infra_vault != "" ? var.onepassword_infra_vault : (
    var.onepassword_infra_vault_id != "" ? data.onepassword_vault.infra[0].name : ""
  )

  enable_grafana_oauth = var.grafana_oauth_client_id != ""
  enable_argocd_oidc   = var.argocd_oidc_client_id != ""
  enable_kubectl_oidc  = var.kubectl_oidc_client_id != ""
  enable_any_oidc      = local.enable_grafana_oauth || local.enable_argocd_oidc
}

# --- Secret Zero: Bootstrap namespace and secret for 1Password SDK ---

resource "kubernetes_namespace_v1" "external_secrets" {
  count = var.enable_onepassword_bootstrap ? 1 : 0

  metadata {
    name = "external-secrets"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform-bootstrap"
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

# ExternalSecret resources in other namespaces are still subject to the
# external-secrets validating webhook during destroy. Keep the operator
# namespace alive until those namespaces have been deleted so teardown does not
# wedge on a missing webhook service.
resource "time_sleep" "external_secrets_destroy_grace_period" {
  count = var.enable_onepassword_bootstrap ? 1 : 0

  depends_on = [kubernetes_namespace_v1.external_secrets]

  destroy_duration = "60s"
}

resource "kubernetes_secret_v1" "onepassword_token" {
  count = var.enable_onepassword_bootstrap ? 1 : 0

  metadata {
    name      = "onepassword-token"
    namespace = "external-secrets"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform-bootstrap"
    }
  }

  data = {
    token = var.onepassword_service_account_token
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations, metadata[0].labels]
  }

  depends_on = [kubernetes_namespace_v1.external_secrets]
}

# --- Bootstrap Secrets: Monitoring ---

resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform-bootstrap"
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }

  depends_on = [time_sleep.external_secrets_destroy_grace_period]
}

resource "kubernetes_namespace_v1" "argocd" {
  count = local.enable_argocd_oidc ? 1 : 0

  metadata {
    name = "argocd"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform-bootstrap"
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }

  depends_on = [time_sleep.external_secrets_destroy_grace_period]
}

resource "random_password" "grafana_admin" {
  count   = var.grafana_admin_password == "" ? 1 : 0
  length  = 24
  special = true
}

locals {
  grafana_password = var.grafana_admin_password != "" ? var.grafana_admin_password : random_password.grafana_admin[0].result
}

resource "kubernetes_secret_v1" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = "monitoring"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform-bootstrap"
    }
  }

  data = {
    username = "admin"
    password = local.grafana_password
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations, metadata[0].labels]
  }

  depends_on = [kubernetes_namespace_v1.monitoring]
}

resource "kubernetes_secret_v1" "grafana_oauth" {
  count = local.enable_grafana_oauth ? 1 : 0

  metadata {
    name      = "grafana-oauth"
    namespace = "monitoring"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform-bootstrap"
    }
  }

  data = {
    GF_AUTH_GENERIC_OAUTH_CLIENT_ID     = var.grafana_oauth_client_id
    GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET = var.grafana_oauth_client_secret
  }

  lifecycle {
    # Terraform creates at bootstrap; ESO keeps in sync after via 1Password
    ignore_changes = [metadata[0].annotations, metadata[0].labels, data]
  }

  depends_on = [kubernetes_namespace_v1.monitoring]
}

resource "kubernetes_secret_v1" "argocd_oidc_secret" {
  count = local.enable_argocd_oidc ? 1 : 0

  metadata {
    name      = "argocd-oidc-secret"
    namespace = "argocd"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform-bootstrap"
      "app.kubernetes.io/part-of"    = "argocd" # Required for ArgoCD $secret:key lookups
    }
  }

  data = {
    clientSecret = var.argocd_oidc_client_secret
  }

  lifecycle {
    # Terraform creates at bootstrap; ESO keeps in sync after via 1Password
    # NOTE: labels NOT in ignore_changes — ArgoCD requires part-of label
    ignore_changes = [metadata[0].annotations, data]
  }

  depends_on = [kubernetes_namespace_v1.argocd]
}

# --- Bootstrap Secrets: Monitoring basicAuth ---

resource "random_password" "monitoring_basic_auth" {
  count   = var.monitoring_basic_auth_password == "" ? 1 : 0
  length  = 32
  special = false # htpasswd-safe characters only
}

resource "random_password" "cnpg_app" {
  count   = var.cnpg_enabled ? 1 : 0
  length  = 32
  special = false
}

locals {
  monitoring_username = var.monitoring_basic_auth_username
  monitoring_password = var.monitoring_basic_auth_password != "" ? var.monitoring_basic_auth_password : random_password.monitoring_basic_auth[0].result
  monitoring_htpasswd = "${local.monitoring_username}:${bcrypt(local.monitoring_password)}"
}

# --- Database contract: managed PostgreSQL or CNPG ---

locals {
  # Managed PostgreSQL (from cluster stage outputs)
  managed_db_host     = lookup(data.terraform_remote_state.cluster.outputs, "database_host", null)
  managed_db_port     = lookup(data.terraform_remote_state.cluster.outputs, "database_port", null)
  managed_db_name     = lookup(data.terraform_remote_state.cluster.outputs, "database_name", null)
  managed_db_username = lookup(data.terraform_remote_state.cluster.outputs, "database_username", null)
  managed_db_password = lookup(data.terraform_remote_state.cluster.outputs, "database_password", null)
  managed_db_enabled = (
    local.managed_db_host != null && local.managed_db_host != "" &&
    local.managed_db_port != null && tostring(local.managed_db_port) != "" &&
    local.managed_db_name != null && local.managed_db_name != "" &&
    local.managed_db_username != null && local.managed_db_username != "" &&
    local.managed_db_password != null && local.managed_db_password != ""
  )
}

locals {
  database_contract_enabled = local.managed_db_enabled || var.cnpg_enabled

  # CNPG creates 4 Services per cluster: -rw (primary), -ro (replicas only),
  # -r (all instances), -any (all incl. not-ready). Pooler resources add
  # {cluster}-pooler-rw and {cluster}-pooler-ro (ro only when instances > 1).
  #
  # Read endpoint logic (mirrors masena-infra):
  #   instances > 1 + pooler → pooler-ro (pooled reads to replicas)
  #   instances > 1 no pooler → -ro (direct reads to replicas)
  #   instances = 1           → -r (all-instances service; -ro has zero endpoints)
  cnpg_rw_host = var.cnpg_enabled ? format("%s.%s.svc.cluster.local",
    var.cnpg_pooler_enabled ? "${var.cnpg_cluster_name}-pooler-rw" : "${var.cnpg_cluster_name}-rw",
    var.cnpg_namespace
  ) : null
  cnpg_ro_host = var.cnpg_enabled ? format("%s.%s.svc.cluster.local",
    var.cnpg_instances > 1
    ? (var.cnpg_pooler_enabled ? "${var.cnpg_cluster_name}-pooler-ro" : "${var.cnpg_cluster_name}-ro")
    : "${var.cnpg_cluster_name}-r",
    var.cnpg_namespace
  ) : null

  # Managed DB takes priority when available (both paths won't be active simultaneously).
  # For managed DB without read replicas, read host = write host.
  db_host      = local.managed_db_enabled ? local.managed_db_host : local.cnpg_rw_host
  db_read_host = local.managed_db_enabled ? local.managed_db_host : local.cnpg_ro_host
  db_port      = local.managed_db_enabled ? local.managed_db_port : (var.cnpg_enabled ? 5432 : null)
  db_name      = local.managed_db_enabled ? local.managed_db_name : (var.cnpg_enabled ? var.cnpg_database_name : null)
  db_username  = local.managed_db_enabled ? local.managed_db_username : (var.cnpg_enabled ? var.cnpg_database_user : null)
  db_password  = local.managed_db_enabled ? local.managed_db_password : (var.cnpg_enabled ? random_password.cnpg_app[0].result : null)

  db_write_uri = local.database_contract_enabled ? format(
    "postgresql://%s:%s@%s:%s/%s?sslmode=require",
    local.db_username, local.db_password, local.db_host, local.db_port, local.db_name
  ) : ""

  db_read_uri = local.database_contract_enabled ? format(
    "postgresql://%s:%s@%s:%s/%s?sslmode=require",
    local.db_username, local.db_password, local.db_read_host, local.db_port, local.db_name
  ) : ""
}

locals {
  kubectl_oidc_exec_args = concat(
    [
      "oidc-login",
      "get-token",
      "--oidc-issuer-url=${var.oidc_issuer_url}",
      "--oidc-client-id=${var.kubectl_oidc_client_id}",
      "--oidc-extra-scope=email",
      "--oidc-extra-scope=profile",
    ],
    var.kubectl_oidc_client_secret != "" ? ["--oidc-client-secret=${var.kubectl_oidc_client_secret}"] : []
  )

  oidc_kubeconfig = yamlencode({
    apiVersion = "v1"
    kind       = "Config"
    clusters = [{
      name = local.cluster_name
      cluster = {
        server                       = local.cluster.server
        "certificate-authority-data" = local.cluster["certificate-authority-data"]
      }
    }]
    contexts = [{
      name = "${local.cluster_name}-oidc"
      context = {
        cluster = local.cluster_name
        user    = "${local.cluster_name}-oidc-user"
      }
    }]
    "current-context" = "${local.cluster_name}-oidc"
    users = [{
      name = "${local.cluster_name}-oidc-user"
      user = {
        exec = {
          apiVersion      = "client.authentication.k8s.io/v1"
          command         = "kubectl"
          args            = local.kubectl_oidc_exec_args
          interactiveMode = "IfAvailable"
        }
      }
    }]
  })
}

# --- Bootstrap Secrets: External DNS ---

resource "kubernetes_namespace_v1" "external_dns" {
  metadata {
    name = "external-dns"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform-bootstrap"
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }

  depends_on = [time_sleep.external_secrets_destroy_grace_period]
}

resource "kubernetes_secret_v1" "cloudflare_api_token" {
  metadata {
    name      = "cloudflare-api-token"
    namespace = "external-dns"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform-bootstrap"
    }
  }

  data = {
    cloudflare_api_token = var.cloudflare_api_token
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations, metadata[0].labels]
  }

  depends_on = [kubernetes_namespace_v1.external_dns]
}

# --- Bootstrap Secrets: Container Registry (private images) ---

resource "kubectl_manifest" "database_namespace" {
  count = var.cnpg_enabled ? 1 : 0

  # Server-side apply keeps bootstrap idempotent if ArgoCD/CNPG already created
  # the namespace, while still allowing Terraform destroy to remove it.
  server_side_apply = true
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = var.cnpg_namespace
      labels = {
        "app.kubernetes.io/managed-by" = "terraform-bootstrap"
      }
    }
  })

  depends_on = [time_sleep.external_secrets_destroy_grace_period]
}

resource "kubernetes_namespace_v1" "demo" {
  # Keep the demo namespace managed from the first addons apply so later feature
  # toggles (GHCR auth, database contract) do not change namespace ownership.
  count = 1

  metadata {
    name = "demo"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform-bootstrap"
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }

  depends_on = [time_sleep.external_secrets_destroy_grace_period]
}

resource "kubernetes_secret_v1" "cnpg_bootstrap_credentials" {
  count = var.cnpg_enabled ? 1 : 0

  metadata {
    name      = "postgres-app-bootstrap"
    namespace = var.cnpg_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform-bootstrap"
      "app.kubernetes.io/component"  = "database"
    }
  }

  type = "kubernetes.io/basic-auth"

  data = {
    username = var.cnpg_database_user
    password = random_password.cnpg_app[0].result
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations, metadata[0].labels]
  }

  depends_on = [kubectl_manifest.database_namespace]
}

resource "kubernetes_secret_v1" "database_credentials" {
  count = local.database_contract_enabled ? 1 : 0

  metadata {
    name      = "database-credentials"
    namespace = "demo"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform-bootstrap"
    }
  }

  data = {
    DB_HOST            = local.db_host
    DB_PORT            = tostring(local.db_port)
    DB_NAME            = local.db_name
    DB_USER            = local.db_username
    DB_PASSWORD        = local.db_password
    DATABASE_WRITE_URL = local.db_write_uri
    DATABASE_READ_URL  = local.db_read_uri
  }

  lifecycle {
    # Terraform seeds the initial secret; ESO can own ongoing sync from 1Password later.
    ignore_changes = [metadata[0].annotations, metadata[0].labels, data]
  }

  depends_on = [kubernetes_namespace_v1.demo]
}

resource "kubernetes_secret_v1" "ghcr_pull_secret" {
  count = var.ghcr_username != "" ? 1 : 0

  metadata {
    name      = "ghcr-secret"
    namespace = "demo"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform-bootstrap"
    }
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          username = var.ghcr_username
          password = coalesce(var.ghcr_token, var.github_token)
          auth     = base64encode("${var.ghcr_username}:${coalesce(var.ghcr_token, var.github_token)}")
        }
      }
    })
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations, metadata[0].labels]
  }

  depends_on = [kubernetes_namespace_v1.demo]
}

# --- ArgoCD Bootstrap ---

module "argocd" {
  source = "../../../modules/argocd-bootstrap"

  argocd_chart_version                  = var.argocd_chart_version
  repo_url                              = var.argocd_repo_url
  target_revision                       = var.argocd_target_revision
  github_token                          = var.github_token
  letsencrypt_email                     = var.letsencrypt_email
  cloud_provider                        = var.cloud_provider
  cluster_name                          = local.cluster_name
  onepassword_vault_id                  = local.onepassword_infra_vault_name
  onepassword_grafana_item_uuid         = try(onepassword_item.grafana_k8s_secret[0].uuid, "")
  onepassword_grafana_oauth_item_uuid   = try(onepassword_item.grafana_oauth[0].uuid, "")
  onepassword_cloudflare_item_uuid      = try(onepassword_item.cloudflare_dns[0].uuid, "")
  onepassword_argocd_oidc_item_uuid     = try(onepassword_item.argocd_oidc[0].uuid, "")
  onepassword_monitoring_auth_item_uuid = try(onepassword_item.monitoring_basic_auth[0].uuid, "")
  domain                                = var.domain
  loki_bucket_chunks                    = try(data.terraform_remote_state.cluster.outputs.object_storage_bucket_names["loki-chunks"], "")
  loki_bucket_ruler                     = try(data.terraform_remote_state.cluster.outputs.object_storage_bucket_names["loki-ruler"], "")
  object_storage_endpoint               = try(data.terraform_remote_state.cluster.outputs.object_storage_endpoint, "")
  object_storage_region                 = try(data.terraform_remote_state.cluster.outputs.object_storage_region, "")
  cnpg_backup_bucket_name               = try(data.terraform_remote_state.cluster.outputs.object_storage_bucket_names["cnpg-backups"], "")
  enable_argocd_oidc                    = local.enable_argocd_oidc
  argocd_oidc_client_id                 = var.argocd_oidc_client_id
  argocd_oidc_client_secret             = var.argocd_oidc_client_secret
  oidc_issuer_url                       = var.oidc_issuer_url
  enable_grafana_oauth                  = local.enable_grafana_oauth
  oidc_allowed_domains                  = var.oidc_allowed_domains
  grafana_oauth_auth_url                = var.grafana_oauth_auth_url
  grafana_oauth_token_url               = var.grafana_oauth_token_url
  grafana_oauth_api_url                 = var.grafana_oauth_api_url
  grafana_oauth_scopes                  = var.grafana_oauth_scopes
  cnpg_enabled                          = var.cnpg_enabled

  depends_on = [
    kubernetes_namespace_v1.demo,
    kubernetes_secret_v1.onepassword_token,
    kubernetes_secret_v1.grafana_admin,
    kubernetes_secret_v1.grafana_oauth,
    kubernetes_secret_v1.argocd_oidc_secret,
    kubernetes_secret_v1.cloudflare_api_token,
    kubernetes_secret_v1.cnpg_bootstrap_credentials,
    kubernetes_secret_v1.database_credentials,
    onepassword_item.grafana_k8s_secret,
    onepassword_item.grafana_oauth,
    onepassword_item.cloudflare_dns,
    onepassword_item.argocd_oidc,
    onepassword_item.loki_s3_credentials,
    onepassword_item.monitoring_basic_auth,
    onepassword_item.database_credentials,
  ]
}

# --- 1Password: Infrastructure Secrets (for ESO sync) ---

resource "onepassword_item" "grafana_k8s_secret" {
  count = var.onepassword_infra_vault_id != "" ? 1 : 0

  vault    = var.onepassword_infra_vault_id
  title    = "grafana-${local.cluster_name}"
  category = "secure_note"

  section {
    label = "Credentials"
    field {
      label = "username"
      type  = "STRING"
      value = "admin"
    }
    field {
      label = "password"
      type  = "CONCEALED"
      value = local.grafana_password
    }
  }

  tags = ["terraform-managed", "monitoring", "k8s-secret", local.cluster_name]
}

resource "onepassword_item" "cloudflare_dns" {
  count = var.onepassword_infra_vault_id != "" ? 1 : 0

  vault    = var.onepassword_infra_vault_id
  title    = "cloudflare-dns-${local.cluster_name}"
  category = "secure_note"

  section {
    label = "Credentials"
    field {
      label = "credential"
      type  = "CONCEALED"
      value = var.cloudflare_api_token
    }
  }

  tags = ["terraform-managed", "dns", "k8s-secret", local.cluster_name]
}

resource "onepassword_item" "grafana_oauth" {
  count = var.onepassword_infra_vault_id != "" && local.enable_grafana_oauth ? 1 : 0

  vault    = var.onepassword_infra_vault_id
  title    = "grafana-oidc-${local.cluster_name}"
  category = "secure_note"

  section {
    label = "Credentials"
    field {
      label = "client_id"
      type  = "STRING"
      value = var.grafana_oauth_client_id
    }
    field {
      label = "client_secret"
      type  = "CONCEALED"
      value = var.grafana_oauth_client_secret
    }
  }

  tags = ["terraform-managed", "monitoring", "oidc", "k8s-secret", local.cluster_name]
}

resource "onepassword_item" "argocd_oidc" {
  count = var.onepassword_infra_vault_id != "" && local.enable_argocd_oidc ? 1 : 0

  vault    = var.onepassword_infra_vault_id
  title    = "argocd-oidc-${local.cluster_name}"
  category = "secure_note"

  section {
    label = "Credentials"
    field {
      label = "client_id"
      type  = "STRING"
      value = var.argocd_oidc_client_id
    }
    field {
      label = "client_secret"
      type  = "CONCEALED"
      value = var.argocd_oidc_client_secret
    }
  }

  tags = ["terraform-managed", "argocd", "oidc", "k8s-secret", local.cluster_name]
}

resource "onepassword_item" "loki_s3_credentials" {
  count = (
    var.onepassword_infra_vault_id != "" &&
    try(data.terraform_remote_state.cluster.outputs.object_storage_access_key, "") != "" &&
    try(data.terraform_remote_state.cluster.outputs.object_storage_secret_key, "") != ""
  ) ? 1 : 0

  vault    = var.onepassword_infra_vault_id
  title    = "loki-s3-${local.cluster_name}"
  category = "secure_note"

  section {
    label = "Credentials"
    field {
      label = "AWS_REGION"
      type  = "STRING"
      value = data.terraform_remote_state.cluster.outputs.object_storage_region
    }
    field {
      label = "AWS_ACCESS_KEY_ID"
      type  = "CONCEALED"
      value = data.terraform_remote_state.cluster.outputs.object_storage_access_key
    }
    field {
      label = "AWS_SECRET_ACCESS_KEY"
      type  = "CONCEALED"
      value = data.terraform_remote_state.cluster.outputs.object_storage_secret_key
    }
  }

  tags = ["terraform-managed", "loki", "s3", "k8s-secret", local.cluster_name]
}

resource "onepassword_item" "cnpg_backup_credentials" {
  count = (
    var.onepassword_infra_vault_id != "" &&
    var.cnpg_enabled &&
    try(data.terraform_remote_state.cluster.outputs.object_storage_access_key, "") != "" &&
    try(data.terraform_remote_state.cluster.outputs.object_storage_secret_key, "") != ""
  ) ? 1 : 0

  vault    = var.onepassword_infra_vault_id
  title    = "cnpg-backup-${local.cluster_name}"
  category = "secure_note"

  section {
    label = "Credentials"
    field {
      label = "AWS_REGION"
      type  = "STRING"
      value = data.terraform_remote_state.cluster.outputs.object_storage_region
    }
    field {
      label = "AWS_ACCESS_KEY_ID"
      type  = "CONCEALED"
      value = data.terraform_remote_state.cluster.outputs.object_storage_access_key
    }
    field {
      label = "AWS_SECRET_ACCESS_KEY"
      type  = "CONCEALED"
      value = data.terraform_remote_state.cluster.outputs.object_storage_secret_key
    }
  }

  tags = ["terraform-managed", "cnpg", "backup", "s3", "k8s-secret", local.cluster_name]
}

resource "onepassword_item" "database_credentials" {
  count = var.onepassword_infra_vault_id != "" && local.database_contract_enabled ? 1 : 0

  vault    = var.onepassword_infra_vault_id
  title    = "database-${local.cluster_name}"
  category = "secure_note"

  section {
    label = "Database"
    field {
      label = "DATABASE_WRITE_URL"
      type  = "CONCEALED"
      value = local.db_write_uri
    }
    field {
      label = "DATABASE_READ_URL"
      type  = "CONCEALED"
      value = local.db_read_uri
    }
    field {
      label = "host"
      type  = "STRING"
      value = local.db_host
    }
    field {
      label = "port"
      type  = "STRING"
      value = tostring(local.db_port)
    }
    field {
      label = "database"
      type  = "STRING"
      value = local.db_name
    }
    field {
      label = "username"
      type  = "STRING"
      value = local.db_username
    }
    field {
      label = "password"
      type  = "CONCEALED"
      value = local.db_password
    }
  }

  tags = ["terraform-managed", "database", "k8s-secret", local.cluster_name]
}

# --- 1Password: Team Browser Logins ---

# When OIDC is enabled, admin logins move to infra vault (break-glass only).
# When OIDC is off, they stay in team logins (admin password is the only way in).
resource "onepassword_item" "argocd_browser_login" {
  count = var.onepassword_team_logins_vault_id != "" ? 1 : 0

  vault    = local.enable_argocd_oidc && var.onepassword_infra_vault_id != "" ? var.onepassword_infra_vault_id : var.onepassword_team_logins_vault_id
  title    = "argocd-${local.cluster_name}"
  category = "login"
  username = "admin"
  password = module.argocd.argocd_admin_password
  url      = "https://argocd-${local.cluster_name}.${var.domain}"

  tags = ["terraform-managed", "argocd", "browser-login", local.cluster_name]
}

resource "onepassword_item" "grafana_browser_login" {
  count = var.onepassword_team_logins_vault_id != "" ? 1 : 0

  vault    = local.enable_grafana_oauth && var.onepassword_infra_vault_id != "" ? var.onepassword_infra_vault_id : var.onepassword_team_logins_vault_id
  title    = "grafana-admin-${local.cluster_name}"
  category = "login"
  username = "admin"
  password = local.grafana_password
  url      = "https://grafana-${local.cluster_name}.${var.domain}"

  tags = ["terraform-managed", "grafana", "browser-login", local.cluster_name]
}

resource "onepassword_item" "oidc_kubeconfig" {
  count = var.onepassword_team_logins_vault_id != "" && local.enable_kubectl_oidc ? 1 : 0

  vault      = var.onepassword_team_logins_vault_id
  title      = "kubeconfig-oidc-${local.cluster_name}"
  category   = "secure_note"
  note_value = local.oidc_kubeconfig

  tags = ["terraform-managed", "kubectl", "oidc", "kubeconfig", local.cluster_name]
}

# --- 1Password: Monitoring basicAuth (for ESO sync) ---

resource "onepassword_item" "monitoring_basic_auth" {
  count = var.onepassword_infra_vault_id != "" ? 1 : 0

  vault    = var.onepassword_infra_vault_id
  title    = "monitoring-basic-auth-${local.cluster_name}"
  category = "secure_note"

  section {
    label = "Credentials"
    field {
      label = "users"
      type  = "CONCEALED"
      value = local.monitoring_htpasswd
    }
  }

  tags = ["terraform-managed", "monitoring", "k8s-secret", local.cluster_name]

  lifecycle {
    ignore_changes = [section] # bcrypt produces different hashes each run
  }
}

# --- 1Password: Prometheus & AlertManager Browser Logins ---

# When any OIDC is enabled, Prometheus/AlertManager logins move to infra vault
# (devs view metrics in Grafana via SSO; direct Prometheus access is ops-only).
resource "onepassword_item" "prometheus_browser_login" {
  count = var.onepassword_team_logins_vault_id != "" ? 1 : 0

  vault    = local.enable_any_oidc && var.onepassword_infra_vault_id != "" ? var.onepassword_infra_vault_id : var.onepassword_team_logins_vault_id
  title    = "prometheus-${local.cluster_name}"
  category = "login"
  username = local.monitoring_username
  password = local.monitoring_password
  url      = "https://prometheus-${local.cluster_name}.${var.domain}"

  tags = ["terraform-managed", "monitoring", "browser-login", local.cluster_name]
}

resource "onepassword_item" "alertmanager_browser_login" {
  count = var.onepassword_team_logins_vault_id != "" ? 1 : 0

  vault    = local.enable_any_oidc && var.onepassword_infra_vault_id != "" ? var.onepassword_infra_vault_id : var.onepassword_team_logins_vault_id
  title    = "alertmanager-${local.cluster_name}"
  category = "login"
  username = local.monitoring_username
  password = local.monitoring_password
  url      = "https://alertmanager-${local.cluster_name}.${var.domain}"

  tags = ["terraform-managed", "monitoring", "browser-login", local.cluster_name]
}

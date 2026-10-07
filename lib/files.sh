# shellcheck shell=bash
# The NovaTech platform repository: file contents and canonical starting states.

D0="2026-09-01T09:00:00"   # base date for canonical history

write_readme() {
cat > README.md <<'EOF'
# NovaTech Cloud Engineering Lab

Platform team repository for NovaTech Financial Group's Azure landing zone tooling.

## Scripts

| Script | Purpose |
| --- | --- |
| `scripts/check-disk.sh` | Alerts when disk usage passes the threshold |
| `scripts/backup-logs.sh` | Archives application logs to the backup share |
| `scripts/health-check.sh` | Calls the platform health endpoint |

## Terraform

`terraform/` holds the core resource group and storage. Region: UK South.
Environment values live in `terraform/environments/`.

## Contributing

Read `CONTRIBUTING.md` before you change anything.

Last reviewed: 2026-09-01
EOF
}

write_contributing() {
cat > CONTRIBUTING.md <<'EOF'
# Contributing

## Branches

- Never work directly on `main`. Other engineers deploy from it.
- Feature work: `feature/PLAT-<ticket>-<short-description>`  e.g. `feature/PLAT-012-cpu-check`
- Urgent production fixes: `hotfix/PLAT-<ticket>-<short-description>`
- Undoing a change: `revert/PLAT-<ticket>-<short-description>`
- Lower case, words separated by hyphens.

## Commit messages

- Start with the ticket id on ticket work: `PLAT-012: Add CPU usage check script`
- Imperative mood ("Add", "Fix", "Remove"), at least four words.
- One logical change per commit. "update", "wip" and "changes" are not messages.

## History

- `main` is shared. Never rewrite it (no reset, no force push).
- A bad change on `main` is undone with a revert, through a pull request.

## Pull requests

- Every change reaches `main` through a pull request (once branch protection is on).
- Fill in every section of the pull request template.
- Address review comments by pushing to the same branch, and reply to say what you changed.

## Never commit

- Secrets of any kind, including `*.auto.tfvars` files
- Terraform state (`*.tfstate`) or the `.terraform/` provider cache
- Editor and OS files (`.DS_Store`, `Thumbs.db`)
EOF
}

write_scripts() {
mkdir -p scripts
cat > scripts/check-disk.sh <<'EOF'
#!/usr/bin/env bash
# Alert when disk usage on / passes THRESHOLD percent.
set -euo pipefail

THRESHOLD=80

USAGE=$(df -P / | awk 'NR==2 {gsub("%",""); print $5}')
if [ "$USAGE" -gt "$THRESHOLD" ]; then
  echo "ALERT: disk usage ${USAGE}% is above ${THRESHOLD}%"
  exit 1
fi
echo "OK: disk usage ${USAGE}%"
EOF
cat > scripts/backup-logs.sh <<'EOF'
#!/usr/bin/env bash
# Archive application logs to the backup share and prune old archives.
set -euo pipefail

LOG_DIR="/var/log/novatech"
BACKUP_DIR="/mnt/backup/logs"
RETENTION_DAYS=14

STAMP=$(date +%Y%m%d)
tar -czf "${BACKUP_DIR}/logs-${STAMP}.tar.gz" -C "$LOG_DIR" .
find "$BACKUP_DIR" -name 'logs-*.tar.gz' -mtime +"$RETENTION_DAYS" -delete
echo "Backup complete: logs-${STAMP}.tar.gz"
EOF
cat > scripts/health-check.sh <<'EOF'
#!/usr/bin/env bash
# Call the platform health endpoint and fail if it does not answer 200.
set -euo pipefail

HEALTH_URL="https://status.novatech.example/healthz"
TIMEOUT=10

CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$TIMEOUT" "$HEALTH_URL")
if [ "$CODE" != "200" ]; then
  echo "UNHEALTHY: $HEALTH_URL returned $CODE"
  exit 1
fi
echo "HEALTHY: $HEALTH_URL"
EOF
chmod +x scripts/*.sh
}

write_terraform() {
mkdir -p terraform/environments terraform/modules/storage-account
cat > terraform/main.tf <<'EOF'
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "platform" {
  name     = "rg-platform-${var.environment}"
  location = var.location
  tags     = var.default_tags
}

module "logs_storage" {
  source              = "./modules/storage-account"
  name                = "stnovatechlogs${var.environment}"
  resource_group_name = azurerm_resource_group.platform.name
  location            = var.location
  tags                = var.default_tags
}
EOF
cat > terraform/variables.tf <<'EOF'
variable "environment" {
  type        = string
  description = "Environment name: dev, test or prod"
}

variable "location" {
  type    = string
  default = "uksouth"
}

variable "vm_size" {
  type    = string
  default = "Standard_B2s"
}

variable "default_tags" {
  type = map(string)
  default = {
    environment = "dev"
    owner       = "cloud-team"
  }
}
EOF
cat > terraform/outputs.tf <<'EOF'
output "resource_group_name" {
  value = azurerm_resource_group.platform.name
}
EOF
cat > terraform/environments/dev.tfvars <<'EOF'
environment = "dev"
vm_size     = "Standard_B2s"
EOF
cat > terraform/environments/prod.tfvars <<'EOF'
environment = "prod"
vm_size     = "Standard_B2s"
EOF
cat > terraform/modules/storage-account/main.tf <<'EOF'
resource "azurerm_storage_account" "this" {
  name                     = var.name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = var.tags
}
EOF
cat > terraform/modules/storage-account/variables.tf <<'EOF'
variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
EOF
cat > terraform/modules/storage-account/outputs.tf <<'EOF'
output "id" {
  value = azurerm_storage_account.this.id
}
EOF
}

write_docs() {
mkdir -p docs/runbooks config
cat > docs/architecture.md <<'EOF'
# Platform architecture

## Overview

One resource group per environment holds the shared platform services.
Logs are archived to a storage account created by `modules/storage-account`.

## Regions

Primary region: UK South.
No secondary region yet.

## Environments

| Environment | Subscription | Purpose |
| --- | --- | --- |
| dev | novatech-platform-dev | Engineering changes land here first |
| prod | novatech-platform-prod | Customer-facing platform services |
EOF
cat > docs/runbooks/disk-space.md <<'EOF'
# Runbook: disk space alert

1. Confirm the alert with `df -h /`.
2. Find large files: `du -xh / --max-depth=2 | sort -h | tail`.
3. Old log archives can be removed from `/mnt/backup/logs` after 14 days.
4. If usage is still above the threshold, escalate to the on-call engineer.
EOF
cat > config/app-settings.json <<'EOF'
{
  "service": "novatech-platform",
  "logLevel": "info",
  "healthCheckIntervalSeconds": 60,
  "region": "uksouth"
}
EOF
}

write_github() {
  mkdir -p .github/workflows .github/ks-lab
  cp "$KS_APP/github/pull_request_template.md" .github/
  cp "$KS_APP/github/workflows/ks-lab-check.yml" .github/workflows/
  cp "$KS_APP/github/workflows/review-bot.yml"   .github/workflows/
  cp "$KS_APP/github/ks-lab/check.js"           .github/ks-lab/
  cp "$KS_APP/github/ks-lab/review-bot.js"      .github/ks-lab/
}

write_all() { write_readme; write_contributing; write_scripts; write_terraform; write_docs; write_github; }

# ---------- canonical states ----------
# Stage A: the end of L01 — the folder under version control in three commits.
build_stage_A() {
  new_repo "$KS_REPO"
  write_all
  git add scripts && kc_me "$D0" "Add operational scripts for disk, backup and health checks"
  git add terraform && kc_me "2026-09-01T09:05:00" "Add Terraform for core resource group and storage"
  git add -A && kc_me "2026-09-01T09:10:00" "Add README, docs and repository standards"
}

# Stage B: end of L02 — disk threshold raised.
build_stage_B() {
  build_stage_A
  sed_replace scripts/check-disk.sh 'THRESHOLD=80' 'THRESHOLD=90'
  git add -A && kc_me "2026-09-02T10:00:00" "PLAT-008: Raise disk usage alert threshold to 90%"
}

# Stage C: end of L05 — CPU check, log retention and Priya's hotfix on main.
build_stage_C() {
  build_stage_B
  write_cpu_script
  add_readme_row 'scripts/check-cpu.sh' 'Alerts when CPU load passes the threshold'
  git add -A && kc_me "2026-09-03T11:00:00" "PLAT-012: Add CPU usage check script"
  sed_replace scripts/health-check.sh 'TIMEOUT=10' 'TIMEOUT=20'
  git add -A && kc "$PRIYA_N" "$PRIYA_E" "2026-09-03T14:00:00" "HOTFIX: Raise health check timeout to 20 seconds"
  sed_replace scripts/backup-logs.sh 'RETENTION_DAYS=14' 'RETENTION_DAYS=30'
  git add -A && kc_me "2026-09-03T15:00:00" "PLAT-015: Keep log archives for 30 days"
}

# Stage D: end of C1 — tags resolved, rotate-logs added, docs updated.
build_stage_D() {
  build_stage_C
  write_tags_resolved
  git add -A && kc_me "2026-09-05T10:00:00" "PLAT-021: Add data classification tag and new owner"
  write_rotate_script
  add_readme_row 'scripts/rotate-logs.sh' 'Rotates application logs daily'
  git add -A && kc_me "2026-09-06T10:00:00" "PLAT-030: Add log rotation script"
  sed_replace docs/architecture.md 'No secondary region yet.' 'Secondary region: UK West (disaster recovery).'
  sed_replace README.md 'Last reviewed: 2026-09-01' 'Last reviewed: 2026-09-06'
  git add -A && kc_me "2026-09-06T11:00:00" "PLAT-031: Document UK West as secondary region"
}

# ---------- reusable edits ----------
# sed_replace <file> <literal-old> <literal-new>  (portable, no sed -i)
sed_replace() {
  local f="$1" old="$2" new="$3" tmp
  tmp="$f.ks-tmp"
  awk -v o="$old" -v n="$new" '{ i = index($0, o); if (i) { $0 = substr($0, 1, i-1) n substr($0, i+length(o)) } print }' "$f" > "$tmp" && cat "$tmp" > "$f" && rm -f "$tmp"
}

add_readme_row() {   # add_readme_row <script> <purpose>  -> appends to the scripts table
  awk -v row="| \`$1\` | $2 |" '
    { lines[NR] = $0 }
    /^\| `scripts\// { last = NR }
    END { for (i = 1; i <= NR; i++) { print lines[i]; if (i == last) print row } }
  ' README.md > README.md.ks-tmp && cat README.md.ks-tmp > README.md && rm -f README.md.ks-tmp
}

write_cpu_script() {
cat > scripts/check-cpu.sh <<'EOF'
#!/usr/bin/env bash
# Alert when the 1-minute load average per CPU passes THRESHOLD percent.
THRESHOLD=85

CPUS=$(getconf _NPROCESSORS_ONLN)
LOAD=$(awk '{print $1}' /proc/loadavg)
PCT=$(awk -v l="$LOAD" -v c="$CPUS" 'BEGIN { printf "%d", (l / c) * 100 }')
if [ "$PCT" -gt "$THRESHOLD" ]; then
  echo "ALERT: CPU load ${PCT}% is above ${THRESHOLD}%"
  exit 1
fi
echo "OK: CPU load ${PCT}%"
EOF
chmod +x scripts/check-cpu.sh
}

write_rotate_script() {
cat > scripts/rotate-logs.sh <<'EOF'
#!/usr/bin/env bash
# Rotate application logs daily, keeping seven compressed copies.
set -euo pipefail
LOG_DIR="/var/log/novatech"
for f in "$LOG_DIR"/*.log; do
  [ -e "$f" ] || continue
  for i in 6 5 4 3 2 1; do
    [ -f "$f.$i.gz" ] && mv "$f.$i.gz" "$f.$((i + 1)).gz"
  done
  gzip -c "$f" > "$f.1.gz" && : > "$f"
done
echo "Logs rotated in $LOG_DIR"
EOF
chmod +x scripts/rotate-logs.sh
}

write_tags_resolved() {
awk '
  /^variable "default_tags"/ { skip = 1 }
  !skip { print }
  skip && /^}/ { skip = 0 }
' terraform/variables.tf > terraform/variables.tf.ks-tmp
cat terraform/variables.tf.ks-tmp > terraform/variables.tf && rm -f terraform/variables.tf.ks-tmp
cat >> terraform/variables.tf <<'EOF'
variable "default_tags" {
  type = map(string)
  default = {
    environment         = "dev"
    owner               = "platform-team"
    cost_centre         = "CC-4410"
    data_classification = "confidential"
  }
}
EOF
}

# Prints "key=value" for each entry inside the default_tags default map.
tag_pairs() {
  awk '
    /^variable "default_tags"/ { inv = 1 }
    inv && /default *= *\{/ { inm = 1; next }
    inm && /^ *\}/ { inm = 0; inv = 0 }
    inm { gsub(/"/, ""); gsub(/ /, ""); if (index($0, "=")) print }
  ' "${1:-terraform/variables.tf}"
}

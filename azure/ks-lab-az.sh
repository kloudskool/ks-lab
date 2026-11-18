#!/usr/bin/env bash
# KloudSkool ks-lab: Azure troubleshooting incidents
# Runs in Azure Cloud Shell (Bash). Creates small, deliberately broken
# environments in the student's own subscription, checks the fix, cleans up.
#
# Usage:  ks-lab az <break|check|clean|status> <lab>
#         ks-lab az list
# Labs:   storage-403 | lock-scopelocked | policy-tag-deny | kv-reference
#
# Every resource is tagged kloudskool-lab=<lab> so it can always be found and removed.

set -uo pipefail

KS_REGION="${KS_REGION:-uksouth}"
# Labs that deploy VMs use their own region: VM capacity in UK South is often
# unavailable on free and student subscriptions, so these default to East US.
KS_VM_REGION="${KS_VM_REGION:-eastus}"
KS_STATE_DIR="${HOME}/.kslab/az"
mkdir -p "$KS_STATE_DIR"

# ---------- output helpers (text labels, never colour alone) ----------
if [ -t 1 ]; then B=$'\e[1m'; D=$'\e[2m'; R=$'\e[0m'; else B=""; D=""; R=""; fi
say()  { printf '%s\n' "$*"; }
step() { printf '%s==>%s %s\n' "$B" "$R" "$*"; }
pass() { printf '  [PASS] %s\n' "$*"; KS_PASSED=$((KS_PASSED+1)); }
fail() { printf '  [FAIL] %s\n' "$*"; KS_FAILED=$((KS_FAILED+1)); }
note() { printf '  [NOTE] %s\n' "$*"; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

# ---------- common ----------
require_login() {
  az account show >/dev/null 2>&1 || die "You're not signed in to Azure. Run this from Azure Cloud Shell, or run 'az login' first."
  KS_SUB_ID=$(az account show --query id -o tsv)
  KS_SUB_NAME=$(az account show --query name -o tsv)
}

me_oid() {
  az ad signed-in-user show --query id -o tsv 2>/dev/null
}

state_file() { printf '%s/%s.env' "$KS_STATE_DIR" "$1"; }

save_state() {  # lab key=value...
  local f kv; f=$(state_file "$1"); shift
  : > "$f"
  for kv in "$@"; do printf '%s\n' "$kv" >> "$f"; done
}

load_state() {
  # Names are derived from the subscription, so check/clean still work in a
  # new (or ephemeral) Cloud Shell session. A saved file, if present, wins.
  local f s; f=$(state_file "$1"); s=$(suffix)
  case "$1" in
    storage-403)      RG="rg-nova-reports-uks-001";  SA="stnovarpt$s" ;;
    lock-scopelocked) RG="rg-nova-test-uks-001";     SA="stnovatest$s" ;;
    policy-tag-deny)  RG="rg-nova-statements-uks-001" ;;
    kv-reference)     RG="rg-nova-portal-uks-001";   KV="kv-nova-portal-$s"; APP="app-nova-portal-$s" ;;
    nsg-unreachable)
      RG="rg-nova-intranet-eus-001"; PIP="pip-nova-intranet-eus-001"; NIC="nic-nova-intranet-eus-001"; VNET="vnet-nova-intranet-eus-001"
      # Environment built before the move to East US (older UK South names)?
      if [ ! -f "$f" ] && ! az group show -n "$RG" -o none 2>/dev/null && az group show -n rg-nova-intranet-uks-001 -o none 2>/dev/null; then
        RG="rg-nova-intranet-uks-001"; PIP="pip-nova-intranet-uks-001"; NIC="nic-nova-intranet-uks-001"; VNET="vnet-nova-intranet-uks-001"
      fi ;;
  esac
  # shellcheck disable=SC1090
  [ -f "$f" ] && . "$f"
}

suffix() {  # stable per subscription, so names are unique but repeatable
  printf '%s' "$KS_SUB_ID" | sha256sum | cut -c1-6
}

tags() { printf 'kloudskool-lab=%s' "$1"; }

completion_code() {  # deterministic per subscription + lab
  local h; h=$(printf 'kloudskool:%s:%s' "$1" "$KS_SUB_ID" | sha256sum | cut -c1-8 | tr 'a-f' 'A-F')
  printf 'KS-AZ-%s-%s' "$(printf '%s' "$1" | tr 'a-z' 'A-Z')" "$h"
}

check_summary() {
  local lab="$1"
  say ""
  if [ "$KS_FAILED" -eq 0 ]; then
    say "${B}All checks passed.${R} Completion code: ${B}$(completion_code "$lab")${R}"
    say "Now clean up so it doesn't cost you anything: ks-lab az clean $lab"
  else
    say "${B}$KS_PASSED passed, $KS_FAILED still failing.${R} Fix the items marked [FAIL] and run the check again."
  fi
}

delete_rg() {
  local rg="$1"
  if [ "$(az group exists -n "$rg")" = "true" ]; then
    # remove any locks first so clean-up never gets stuck
    local ids; ids=$(az lock list -g "$rg" --query "[].id" -o tsv 2>/dev/null)
    for id in $ids; do az lock delete --ids "$id" >/dev/null 2>&1; done
    az group delete -n "$rg" --yes --no-wait && step "Deleting $rg (runs in the background, takes a few minutes)."
  else
    step "$rg is already gone."
  fi
}

wait_for() {  # wait_for <seconds> <description> <command...>
  local limit="$1" desc="$2"; shift 2
  local waited=0
  until "$@" >/dev/null 2>&1; do
    [ "$waited" -ge "$limit" ] && return 1
    printf '   waiting for %s (%ss)...\r' "$desc" "$waited"
    sleep 15; waited=$((waited+15))
  done
  printf '%*s\r' 60 ''
  return 0
}

# =====================================================================
# Lab: storage-403  (network rule + missing data-plane role)
# =====================================================================
storage_403_break() {
  local lab=storage-403 rg=rg-nova-reports-uks-001 sa region="$KS_REGION"
  sa="stnovarpt$(suffix)"
  # The check reads the container from Cloud Shell through a temporary IP rule.
  # IP rules don't apply to same-region traffic, so keep the account out of
  # the region Cloud Shell runs in.
  local cs; cs=$(printf '%s' "${ACC_LOCATION:-}" | tr 'A-Z' 'a-z')
  if [ -n "$cs" ] && [ "$cs" = "$region" ]; then
    [ "$region" = "northeurope" ] && region=westeurope || region=northeurope
  fi
  step "Creating $rg in $region"
  az group create -n "$rg" -l "$region" --tags "$(tags $lab)" -o none || die "Couldn't create the resource group."
  step "Creating storage account $sa"
  az storage account create -n "$sa" -g "$rg" -l "$region" --sku Standard_LRS --kind StorageV2 \
    --min-tls-version TLS1_2 --allow-blob-public-access false --allow-shared-key-access false \
    --default-action Deny --tags "$(tags $lab)" -o none || die "Couldn't create the storage account."
  step "Creating container 'reports'"
  az storage container-rm create --storage-account "$sa" -g "$rg" -n reports -o none || die "Couldn't create the container."
  save_state "$lab" "RG=$rg" "SA=$sa"
  say ""
  say "${B}Environment ready.${R} Storage account: ${B}$sa${R}"
  say "See the problem in the portal: Storage accounts > $sa > Storage browser > Blob containers > reports, then try to upload any file."
}

storage_403_check() {
  local lab=storage-403; load_state "$lab"
  local said; said=$(az storage account show -n "$SA" -g "$RG" --query id -o tsv 2>/dev/null) || die "Storage account $SA not found. Did you delete it? Run the break step again."

  # 1. network
  local action ips shared
  action=$(az storage account show -n "$SA" -g "$RG" --query networkRuleSet.defaultAction -o tsv)
  ips=$(az storage account show -n "$SA" -g "$RG" --query "length(networkRuleSet.ipRules)" -o tsv)
  if [ "$action" = "Allow" ]; then
    fail "Network: the account is now open to every network. Put it back to selected networks and allow only your IP"
  elif [ "${ips:-0}" -gt 0 ]; then
    pass "Network: still restricted to selected networks, with an IP rule added"
  else
    fail "Network: the account only allows selected networks and no rule lets you in (look at the Networking blade)"
  fi

  # 2. no workaround with keys
  shared=$(az storage account show -n "$SA" -g "$RG" --query allowSharedKeyAccess -o tsv)
  if [ "$shared" = "true" ]; then
    fail "Access keys have been switched back on. That's a workaround, not a fix: turn 'Allow storage account key access' off again"
  else
    pass "Access keys are still disabled"
  fi

  # 3. data-plane role at the right scope
  local oid; oid=$(me_oid)
  if [ -z "$oid" ]; then
    note "Couldn't read your user ID, so the role check is skipped."
  else
    local roles; roles=$(az role assignment list --assignee "$oid" --all \
      --query "[?starts_with(roleDefinitionName,'Storage Blob Data')].scope" -o tsv 2>/dev/null)
    local narrow=0 broad=0 sc
    while IFS= read -r sc; do
      [ -z "$sc" ] && continue
      if [[ "${sc,,}" == "${said,,}"* ]]; then narrow=1; else broad=1; fi
    done <<< "$roles"
    if [ "$narrow" -eq 1 ] && [ "$broad" -eq 0 ]; then
      pass "Access: you hold a Storage Blob Data role on the storage account or container"
    elif [ "$broad" -eq 1 ]; then
      fail "Access: you have a Storage Blob Data role at a broad scope (resource group or subscription). Remove it and assign the role on the storage account or container"
    else
      fail "Access: you have no Storage Blob Data role. Owner manages the account but can't read or write the data inside it"
    fi
  fi

  # 4. outcome: a file is in 'reports'. Cloud Shell isn't on the allow list, so
  # open a temporary rule for its IP, look, then remove it again.
  local csip added=0 count=""
  csip=$(curl -s --max-time 10 https://api.ipify.org)
  if [ "$action" != "Allow" ] && [ -n "$csip" ]; then
    if ! az storage account show -n "$SA" -g "$RG" --query "networkRuleSet.ipRules[].ipAddressOrRange" -o tsv | grep -qx "$csip"; then
      az storage account network-rule add -g "$RG" --account-name "$SA" --ip-address "$csip" -o none 2>/dev/null && added=1
    fi
  fi
  for _ in 1 2 3 4 5 6; do
    count=$(az storage blob list --account-name "$SA" -c reports --auth-mode login --num-results 5 --query "length(@)" -o tsv 2>/dev/null) && break
    [ "$added" -eq 1 ] || break
    sleep 10
  done
  [ "$added" -eq 1 ] && az storage account network-rule remove -g "$RG" --account-name "$SA" --ip-address "$csip" -o none 2>/dev/null
  if [ "${count:-0}" -gt 0 ] 2>/dev/null; then
    pass "Outcome: there's a file in 'reports'"
  else
    fail "Outcome: no file in 'reports' yet. Upload one through Storage browser (new role assignments can take up to 10 minutes to apply)"
  fi
  check_summary "$lab"
}

storage_403_clean() { load_state storage-403; delete_rg "$RG"; rm -f "$(state_file storage-403)"; }

# =====================================================================
# Lab: lock-scopelocked  (CanNotDelete lock blocks RG delete)
# =====================================================================
lock_break() {
  local lab=lock-scopelocked rg=rg-nova-test-uks-001 sa
  sa="stnovatest$(suffix)"
  step "Creating $rg in $KS_REGION"
  az group create -n "$rg" -l "$KS_REGION" --tags "$(tags $lab)" env=test -o none || die "Couldn't create the resource group."
  step "Creating storage account $sa"
  az storage account create -n "$sa" -g "$rg" -l "$KS_REGION" --sku Standard_LRS --kind StorageV2 \
    --min-tls-version TLS1_2 --allow-blob-public-access false --tags "$(tags $lab)" -o none || die "Couldn't create the storage account."
  step "Adding the test environment's 'protection'"
  az lock create --name temp-loadtest-protect --lock-type CanNotDelete -g "$rg" \
    --resource "$sa" --resource-type Microsoft.Storage/storageAccounts \
    --notes "Added by J. Patel during load testing so results weren't lost. Temporary." -o none || die "Couldn't create the lock."
  save_state "$lab" "RG=$rg" "SA=$sa"
  say ""
  say "${B}Environment ready.${R}"
  say "See the problem in the portal: Resource groups > $rg > Delete resource group."
}

lock_check() {
  local lab=lock-scopelocked; load_state "$lab"
  if [ "$(az group exists -n "$RG")" = "true" ]; then
    local state; state=$(az group show -n "$RG" --query properties.provisioningState -o tsv 2>/dev/null)
    if [ "$state" = "Deleting" ]; then
      fail "$RG is being deleted. Give it a few minutes, then run the check again"
    else
      local n; n=$(az lock list -g "$RG" --query "length(@)" -o tsv 2>/dev/null)
      [ "${n:-0}" -gt 0 ] && fail "A lock is still in place inside $RG" || pass "No locks left inside $RG"
      fail "$RG still exists. The ticket is closed when the test environment is gone"
    fi
  else
    pass "The lock was removed and $RG has been deleted"
  fi
  check_summary "$lab"
}

lock_clean() { load_state lock-scopelocked; delete_rg "$RG"; rm -f "$(state_file lock-scopelocked)"; }

# =====================================================================
# Lab: policy-tag-deny  (Deny policy requires cost-centre tag)
# =====================================================================
POLICY_REQUIRE_TAG=871b6d14-10aa-478d-b590-94f262ecfa99   # built-in "Require a tag on resources"
POLICY_NAME=require-cost-centre

probe_denied() {  # succeeds only once the policy is enforcing
  local rg="$1" out
  out=$(az network nsg create -g "$rg" -n nsg-ks-probe -l "$KS_REGION" -o none 2>&1)
  if printf '%s' "$out" | grep -q RequestDisallowedByPolicy; then return 0; fi
  az network nsg delete -g "$rg" -n nsg-ks-probe >/dev/null 2>&1
  return 1
}

policy_break() {
  local lab=policy-tag-deny rg=rg-nova-statements-uks-001
  step "Creating $rg in $KS_REGION"
  az group create -n "$rg" -l "$KS_REGION" --tags "$(tags $lab)" -o none || die "Couldn't create the resource group."
  local rgid; rgid=$(az group show -n "$rg" --query id -o tsv)
  step "Assigning the governance team's tagging policy"
  az policy assignment create --name "$POLICY_NAME" --display-name "NovaTech: require cost-centre tag" \
    --policy "$POLICY_REQUIRE_TAG" --scope "$rgid" \
    --params '{"tagName":{"value":"cost-centre"}}' -o none || die "Couldn't assign the policy. You need Owner or Resource Policy Contributor."
  save_state "$lab" "RG=$rg"
  step "Waiting for the policy to start enforcing (new assignments can take several minutes)"
  if wait_for 1200 "policy enforcement" probe_denied "$rg"; then
    say "   policy is enforcing."
  else
    note "The policy isn't enforcing yet. Wait a few minutes before you start, or your first attempt may succeed."
  fi
  say ""
  say "${B}Environment ready.${R}"
  say "See the problem in the portal: Storage accounts > Create, resource group $rg, any name and settings, then Review + create."
}

policy_check() {
  local lab=policy-tag-deny; load_state "$lab"
  local rgid; rgid=$(az group show -n "$RG" --query id -o tsv 2>/dev/null) || die "$RG not found. Run the break step again."

  local tagged; tagged=$(az storage account list -g "$RG" --query "[?tags.\"cost-centre\"!=null] | length(@)" -o tsv)
  local total; total=$(az storage account list -g "$RG" --query "length(@)" -o tsv)
  if [ "${tagged:-0}" -gt 0 ]; then
    pass "A storage account exists in $RG with a cost-centre tag"
  elif [ "${total:-0}" -gt 0 ]; then
    fail "There's a storage account in $RG but it has no cost-centre tag"
  else
    fail "No storage account in $RG yet. The feature still needs its storage"
  fi

  local mode; mode=$(az policy assignment show --name "$POLICY_NAME" --scope "$rgid" --query enforcementMode -o tsv 2>/dev/null)
  if [ -z "$mode" ]; then
    fail "The tagging policy assignment has been deleted. Fix the request, not the guardrail: re-run 'ks-lab az break $lab' to restore it"
  elif [ "$mode" != "Default" ]; then
    fail "The policy is set to DoNotEnforce. That switches the guardrail off for everyone"
  else
    pass "The tagging policy is still assigned and enforcing"
  fi

  local ex; ex=$(az policy exemption list --scope "$rgid" --query "length(@)" -o tsv 2>/dev/null)
  [ "${ex:-0}" -gt 0 ] && fail "There's a policy exemption on $RG. Remove it and tag the resource instead" || pass "No policy exemptions were added"
  check_summary "$lab"
}

policy_clean() {
  load_state policy-tag-deny
  local rgid; rgid=$(az group show -n "$RG" --query id -o tsv 2>/dev/null)
  [ -n "$rgid" ] && az policy assignment delete --name "$POLICY_NAME" --scope "$rgid" >/dev/null 2>&1
  delete_rg "$RG"; rm -f "$(state_file policy-tag-deny)"
}

# =====================================================================
# Lab: kv-reference  (managed identity has no role on the vault)
# =====================================================================
kv_break() {
  local lab=kv-reference rg=rg-nova-portal-uks-001 s kv plan app sku=F1
  s=$(suffix); kv="kv-nova-portal-$s"; plan=asp-nova-portal-uks-001; app="app-nova-portal-$s"
  local oid; oid=$(me_oid) || true
  [ -n "$oid" ] || die "Couldn't read your user ID. This lab needs a normal user sign-in (Cloud Shell)."

  step "Creating $rg in $KS_REGION"
  az group create -n "$rg" -l "$KS_REGION" --tags "$(tags $lab)" -o none || die "Couldn't create the resource group."
  step "Creating Key Vault $kv (RBAC mode)"
  az keyvault create -n "$kv" -g "$rg" -l "$KS_REGION" --enable-rbac-authorization true \
    --retention-days 7 --tags "$(tags $lab)" -o none || die "Couldn't create the Key Vault."
  local kvid; kvid=$(az keyvault show -n "$kv" --query id -o tsv)
  step "Giving you permission to write secrets"
  az role assignment create --assignee-object-id "$oid" --assignee-principal-type User \
    --role "Key Vault Secrets Officer" --scope "$kvid" -o none 2>/dev/null || true
  step "Storing MyDbConnection (waiting for your role to apply)"
  wait_for 600 "secret write access" az keyvault secret set --vault-name "$kv" -n MyDbConnection \
    --value "Server=tcp:sql-nova-prod-uks-001.database.windows.net,1433;Database=novaportal;Authentication=Active Directory Default;" \
    || die "Couldn't write the secret after 10 minutes. Run the break step again."

  step "Creating App Service plan ($sku) and web app $app"
  if ! az appservice plan create -n "$plan" -g "$rg" -l "$KS_REGION" --is-linux --sku "$sku" --tags "$(tags $lab)" -o none 2>/dev/null; then
    sku=B1
    note "The Free tier isn't available to you here (often because you already have a Free Linux plan in this region). Using B1, which costs a few pence an hour: clean up when you're done."
    az appservice plan create -n "$plan" -g "$rg" -l "$KS_REGION" --is-linux --sku B1 --tags "$(tags $lab)" -o none || die "Couldn't create the App Service plan."
  fi
  az webapp create -n "$app" -g "$rg" -p "$plan" --runtime "NODE:22-lts" --tags "$(tags $lab)" -o none || die "Couldn't create the web app."
  step "Turning on the app's managed identity"
  az webapp identity assign -n "$app" -g "$rg" -o none || die "Couldn't enable the managed identity."
  step "Pointing MyDbConnection at Key Vault"
  az webapp config appsettings set -n "$app" -g "$rg" -o none \
    --settings "MyDbConnection=@Microsoft.KeyVault(SecretUri=https://${kv}.vault.azure.net/secrets/MyDbConnection/)" || die "Couldn't set the app setting."
  save_state "$lab" "RG=$rg" "KV=$kv" "APP=$app" "SKU=$sku"
  say ""
  say "${B}Environment ready.${R} Web app: ${B}$app${R}  Key Vault: ${B}$kv${R}"
  say "See the problem: Portal > $app > Settings > Environment variables > MyDbConnection (look at the Key Vault reference status)"
}

kv_check() {
  local lab=kv-reference; load_state "$lab"
  local kvid appid pid
  kvid=$(az keyvault show -n "$KV" --query id -o tsv 2>/dev/null) || die "Key Vault $KV not found. Run the break step again."
  appid=$(az webapp show -n "$APP" -g "$RG" --query id -o tsv 2>/dev/null) || die "Web app $APP not found. Run the break step again."
  pid=$(az webapp identity show -n "$APP" -g "$RG" --query principalId -o tsv 2>/dev/null)

  if [ -z "$pid" ]; then
    fail "The app's managed identity is off. The fix is a role for the identity, not removing it"
  else
    pass "The app's managed identity is on"
    local rows; rows=$(az role assignment list --assignee "$pid" --all --query "[].[roleDefinitionName,scope]" -o tsv 2>/dev/null)
    local good=0 broad=0
    while IFS=$'\t' read -r role scope; do
      [ -z "$role" ] && continue
      case "$role" in
        "Key Vault Secrets User")
          if [[ "$scope" == "$kvid"* ]]; then good=1; else broad=1; fi ;;
        "Key Vault Administrator"|"Key Vault Secrets Officer"|"Owner"|"Contributor"|"Key Vault Contributor")
          broad=1 ;;
      esac
    done <<< "$rows"
    [ "$good" -eq 1 ] && pass "The identity has Key Vault Secrets User on the vault (or the secret)" \
                      || fail "The identity doesn't have Key Vault Secrets User on $KV"
    [ "$broad" -eq 1 ] && fail "The identity also has a broader role or scope than it needs. Remove it: read-only access to this vault is enough" \
                       || pass "No over-broad roles"
  fi

  local status; status=$(az rest --method get \
    --url "https://management.azure.com${appid}/config/configreferences/appsettings/MyDbConnection?api-version=2022-03-01" \
    --query properties.status -o tsv 2>/dev/null)
  if [ "$status" = "Resolved" ]; then
    pass "MyDbConnection resolves from Key Vault"
  else
    fail "MyDbConnection doesn't resolve yet (status: ${status:-unknown}). After fixing access, restart the app in the portal ($APP > Overview > Restart) so it fetches the reference again"
  fi
  check_summary "$lab"
}

kv_clean() {
  load_state kv-reference
  delete_rg "$RG"
  note "Key Vault $KV stays soft-deleted for 7 days. To remove it fully once the delete finishes: az keyvault purge -n $KV"
  rm -f "$(state_file kv-reference)"
}

# =====================================================================
# Lab: nsg-unreachable  (NIC NSG deny at higher priority than its allow)
# =====================================================================
NSG_SUBNET=nsg-nova-web-subnet
NSG_NIC=nsg-nova-intranet-nic

nsg_break() {
  local lab=nsg-unreachable rg=rg-nova-intranet-eus-001 vnet=vnet-nova-intranet-eus-001
  local pip=pip-nova-intranet-eus-001 nic=nic-nova-intranet-eus-001 vm=vm-nova-intranet-eus-001
  step "Creating $rg in $KS_VM_REGION"
  az group create -n "$rg" -l "$KS_VM_REGION" --tags "$(tags $lab)" -o none || die "Couldn't create the resource group."
  step "Creating the subnet NSG (allows HTTP from the internet)"
  az network nsg create -g "$rg" -n "$NSG_SUBNET" -l "$KS_VM_REGION" --tags "$(tags $lab)" -o none || die "Couldn't create the subnet NSG."
  az network nsg rule create -g "$rg" --nsg-name "$NSG_SUBNET" -n Allow-HTTP-Internet --priority 200 --direction Inbound \
    --access Allow --protocol Tcp --source-address-prefixes Internet --destination-port-ranges 80 -o none
  step "Creating the network"
  az network vnet create -g "$rg" -n "$vnet" -l "$KS_VM_REGION" --address-prefixes 10.40.0.0/16 \
    --subnet-name snet-web --subnet-prefixes 10.40.1.0/24 --network-security-group "$NSG_SUBNET" --tags "$(tags $lab)" -o none || die "Couldn't create the VNet."
  step "Creating the network interface NSG"
  az network nsg create -g "$rg" -n "$NSG_NIC" -l "$KS_VM_REGION" --tags "$(tags $lab)" -o none || die "Couldn't create the NIC NSG."
  az network nsg rule create -g "$rg" --nsg-name "$NSG_NIC" -n Allow-HTTP --priority 300 --direction Inbound \
    --access Allow --protocol Tcp --source-address-prefixes Internet --destination-port-ranges 80 -o none
  az network nsg rule create -g "$rg" --nsg-name "$NSG_NIC" -n Deny-HTTP-PenTest --priority 100 --direction Inbound \
    --access Deny --protocol Tcp --source-address-prefixes '*' --destination-port-ranges 80 \
    --description "Temporary: block web traffic during the pen test. Remove afterwards. J. Patel" -o none
  step "Creating the public IP and network interface"
  az network public-ip create -g "$rg" -n "$pip" -l "$KS_VM_REGION" --sku Standard --allocation-method Static --tags "$(tags $lab)" -o none || die "Couldn't create the public IP."
  az network nic create -g "$rg" -n "$nic" -l "$KS_VM_REGION" --vnet-name "$vnet" --subnet snet-web \
    --network-security-group "$NSG_NIC" --public-ip-address "$pip" --tags "$(tags $lab)" -o none || die "Couldn't create the network interface."
  local ci; ci=$(mktemp)
  cat > "$ci" <<'CLOUD'
#cloud-config
package_update: true
packages: [nginx]
write_files:
  - path: /var/www/html/index.html
    content: |
      <html><body style="font-family:sans-serif"><h1>NovaTech staff intranet</h1><p>If you can read this, the incident is fixed.</p></body></html>
runcmd:
  - systemctl enable --now nginx
CLOUD
  step "Creating the web server VM (a few minutes)"
  local size ok=0
  for size in Standard_B1s Standard_B2ats_v2 Standard_B1ms; do
    if az vm create -g "$rg" -n "$vm" -l "$KS_VM_REGION" --nics "$nic" --image Ubuntu2204 --size "$size" \
        --admin-username novaadmin --generate-ssh-keys --custom-data "$ci" --tags "$(tags $lab)" -o none 2>/dev/null; then
      ok=1; break
    fi
    note "Size $size isn't available to you in $KS_VM_REGION. Trying the next one."
  done
  rm -f "$ci"
  [ "$ok" -eq 1 ] || die "Couldn't create the VM in $KS_VM_REGION. Try another region: KS_VM_REGION=eastus2 ks-lab az break $lab"
  az vm auto-shutdown -g "$rg" -n "$vm" --time 1900 -o none 2>/dev/null || note "Couldn't set auto-shutdown. Remember to clean up."
  step "Waiting for the web server to finish installing"
  az vm run-command invoke -g "$rg" -n "$vm" --command-id RunShellScript --scripts "cloud-init status --wait >/dev/null; systemctl is-active nginx" -o none 2>/dev/null \
    || note "Couldn't confirm the web server is ready. Give it two minutes before testing."
  save_state "$lab" "RG=$rg" "VM=$vm" "PIP=$pip" "NIC=$nic" "VNET=$vnet"
  say ""
  say "${B}Environment ready.${R} VM: ${B}$vm${R}  Public IP: ${B}$(az network public-ip show -g "$rg" -n "$pip" --query ipAddress -o tsv)${R}"
  say "See the problem in the portal: Virtual machines > $vm > Overview. Open http://<public IP> in a new tab."
}

port_covers() {  # port_covers <range-list> <port>  e.g. "80,443-445" 22
  local item lo hi
  IFS=',' read -ra parts <<< "$1"
  for item in "${parts[@]}"; do
    item="${item// /}"
    [ -z "$item" ] && continue
    [ "$item" = "*" ] && return 0
    if [[ "$item" == *-* ]]; then lo=${item%-*}; hi=${item#*-}; [ "$2" -ge "$lo" ] && [ "$2" -le "$hi" ] && return 0
    elif [ "$item" = "$2" ]; then return 0; fi
  done
  return 1
}

nsg_open_rules() {  # prints the port ranges of inbound Allow rules open to the internet
  az network nsg rule list -g "$RG" --nsg-name "$1" -o tsv --query \
   "[?access=='Allow' && direction=='Inbound' && (sourceAddressPrefix=='*' || sourceAddressPrefix=='Internet' || sourceAddressPrefix=='0.0.0.0/0' || contains(sourceAddressPrefixes || \`[]\`, '*') || contains(sourceAddressPrefixes || \`[]\`, 'Internet') || contains(sourceAddressPrefixes || \`[]\`, '0.0.0.0/0'))].join(',', [destinationPortRange || '', join(',', destinationPortRanges || \`[]\`)])" 2>/dev/null
}

nsg_check() {
  local lab=nsg-unreachable; load_state "$lab"
  az group show -n "$RG" -o none 2>/dev/null || die "$RG not found. Run the break step again."
  local ip; ip=$(az network public-ip show -g "$RG" -n "$PIP" --query ipAddress -o tsv 2>/dev/null)

  # 1. both NSGs still attached
  local snsg nnsg
  snsg=$(az network vnet subnet show -g "$RG" --vnet-name "${VNET:-${RG/rg-/vnet-}}" -n snet-web --query networkSecurityGroup.id -o tsv 2>/dev/null)
  nnsg=$(az network nic show -g "$RG" -n "$NIC" --query networkSecurityGroup.id -o tsv 2>/dev/null)
  [[ "${snsg,,}" == *"/${NSG_SUBNET,,}" ]] && pass "The subnet NSG is still attached" || fail "The subnet NSG ($NSG_SUBNET) is no longer attached to snet-web. Put it back"
  [[ "${nnsg,,}" == *"/${NSG_NIC,,}" ]] && pass "The network interface NSG is still attached" || fail "The network interface NSG ($NSG_NIC) is no longer attached. The fix is a rule change, not removing the NSG"

  # 2. nothing over-open
  local wide=0 mgmt=0 r n
  for n in "$NSG_SUBNET" "$NSG_NIC"; do
    while IFS= read -r r; do
      [ -z "$r" ] && continue
      port_covers "$r" 1 && port_covers "$r" 65535 && wide=1
      { port_covers "$r" 22 || port_covers "$r" 3389; } && mgmt=1
    done < <(nsg_open_rules "$n")
  done
  [ "$wide" -eq 0 ] && pass "No rule allows every port from the internet" || fail "A rule allows every port from the internet. Allow only port 80"
  [ "$mgmt" -eq 0 ] && pass "SSH and RDP are not open to the internet" || fail "SSH (22) or RDP (3389) is open to the internet. Remove that rule"

  # 3. outcome
  if [ -n "$ip" ] && curl -s --max-time 10 "http://$ip" | grep -q "NovaTech staff intranet"; then
    pass "Outcome: the intranet page loads on http://$ip"
  else
    fail "Outcome: the intranet page doesn't load on http://${ip:-<no IP>} yet (NSG changes can take a minute to apply)"
  fi
  check_summary "$lab"
}

nsg_clean() { load_state nsg-unreachable; delete_rg "$RG"; rm -f "$(state_file nsg-unreachable)"; }

# =====================================================================
# Dispatcher
# =====================================================================
labs_list() {
  cat <<EOF
Azure troubleshooting incidents:
  storage-403        Upload fails with 403
  lock-scopelocked   Resource group won't delete
  policy-tag-deny    Deployment rejected by policy
  kv-reference       App can't read its database secret
  nsg-unreachable    Web server unreachable on port 80
Usage: ks-lab az <break|check|clean|status> <lab>
EOF
}

status() {
  require_login
  say "Subscription: $KS_SUB_NAME"
  say "KloudSkool lab resource groups still in your subscription:"
  az group list --query "[?tags.\"kloudskool-lab\"!=null].{name:name, lab:tags.\"kloudskool-lab\", state:properties.provisioningState}" -o table
}

install_cmd() {
  # Makes 'ks-lab az ...' work in Cloud Shell, in both Bash and PowerShell,
  # by adding a ks-lab function to each shell's profile (no PATH changes).
  local home_dir="$HOME/.kslab"
  mkdir -p "$home_dir"
  local src; src=$(readlink -f "${BASH_SOURCE[0]}")
  [ "$src" = "$home_dir/ks-lab-az.sh" ] || cp "$src" "$home_dir/ks-lab-az.sh"
  touch "$HOME/.bashrc"
  sed -i '/# kslab-path$/d; /# kslab-fn$/d' "$HOME/.bashrc"
  printf '%s\n' 'ks-lab() { if [ "${1:-}" = az ]; then shift; bash "$HOME/.kslab/ks-lab-az.sh" "$@"; else echo "Usage: ks-lab az <break|check|clean|status|list> [lab]"; fi; }  # kslab-fn' >> "$HOME/.bashrc"
  local ps_dir="$HOME/.config/powershell"
  mkdir -p "$ps_dir"
  local ps_profile="$ps_dir/Microsoft.PowerShell_profile.ps1"
  touch "$ps_profile"
  sed -i '/# kslab-fn$/d' "$ps_profile"
  printf '%s\n' 'function ks-lab { if ($args.Count -gt 0 -and $args[0] -eq "az") { bash "$HOME/.kslab/ks-lab-az.sh" @($args | Select-Object -Skip 1) } else { "Usage: ks-lab az <break|check|clean|status|list> [lab]" } }  # kslab-fn' >> "$ps_profile"
  say "${B}Installed.${R} Load it into this session, then use: ks-lab az list"
  say "  Bash:       source ~/.bashrc"
  say "  PowerShell: . \$PROFILE"
  say "In an ephemeral Cloud Shell session this lasts until the session ends. Next time, upload the file and run install again."
}

print_task() {
  say ""
  say "${B}Your task${R} (fix it in the Azure portal, not here)"
  case "$1" in
    storage-403)
      say "  Upload a file to the 'reports' container through the portal's Storage browser, signed in as yourself."
      say "  Done means: a file is in 'reports', the account is still restricted to selected networks,"
      say "  access keys are still off, and your data role is on the account or container (not wider)."
      say "  Rules: don't switch access keys back on; don't open the account to every network; don't recreate it." ;;
    lock-scopelocked)
      say "  Find what's stopping the test environment being deleted, deal with it properly, finish the teardown."
      say "  Done means: rg-nova-test-uks-001 no longer exists."
      say "  Rules: read the error first; don't remove anything until you know why it was added." ;;
    policy-tag-deny)
      say "  Create the storage account for the statements feature without weakening governance."
      say "  Done means: a storage account in rg-nova-statements-uks-001 tagged cost-centre=finance,"
      say "  and the policy still assigned and enforcing, with no exemptions."
      say "  Rules: don't delete, disable or exempt the policy; don't use another resource group." ;;
    nsg-unreachable)
      say "  Make the intranet page load on http://<the VM's public IP>, without weakening security."
      say "  Done means: the page loads on port 80, both NSGs are still attached, no rule allows every"
      say "  port from the internet, and SSH/RDP aren't open to the internet."
      say "  Rules: don't delete or detach either NSG; no allow-all rules; don't open SSH or RDP."
      say "  This lab runs a small VM. Clean up as soon as you finish." ;;
    kv-reference)
      say "  Make the portal app read MyDbConnection from Key Vault."
      say "  Done means: the reference shows as resolved, and the app's identity can read secrets in this vault and nothing more."
      say "  Rules: don't paste the value into app settings; don't turn off the identity; no admin or subscription-wide roles." ;;
  esac
  say "When you think it's fixed, come back here and run: ks-lab az check $1"
}

main() {
  local verb="${1:-}" lab="${2:-}"
  case "$verb" in
    list|"") labs_list; return ;;
    install) install_cmd; return ;;
    status)  status; return ;;
    break|check|clean) ;;
    *) labs_list; exit 1 ;;
  esac
  [ -n "$lab" ] || { labs_list; exit 1; }
  require_login
  KS_PASSED=0; KS_FAILED=0
  local fn
  case "$lab" in
    storage-403)      fn=storage_403 ;;
    lock-scopelocked) fn=lock ;;
    policy-tag-deny)  fn=policy ;;
    kv-reference)     fn=kv ;;
    nsg-unreachable)  fn=nsg ;;
    *) die "Unknown lab '$lab'. Run: ks-lab az list" ;;
  esac
  [ "$verb" = "break" ] && { r=$KS_REGION; [ "$lab" = "nsg-unreachable" ] && r=$KS_VM_REGION; say "${D}Subscription: $KS_SUB_NAME  Region: $r${R}"; }
  "${fn}_${verb}"
  [ "$verb" = "break" ] && print_task "$lab"
  return 0
}

main "$@"

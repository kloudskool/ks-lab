# ks-lab: Azure troubleshooting incidents

Small, deliberately broken Azure environments for KloudSkool's Azure ClickOps module. Students set up, check and clean up from **Azure Cloud Shell**, and fix every problem **in the Azure portal**.

Everything is created in the student's own subscription, tagged `kloudskool-lab=<lab>`, and removed by `clean`.

## Set up (once per Cloud Shell session)

Cloud Shell sessions can be ephemeral, so run this at the start of each session:

```bash
curl -sLo ks-lab-az.sh https://raw.githubusercontent.com/kloudskool/ks-lab/main/azure/ks-lab-az.sh
bash ks-lab-az.sh install
source ~/.bashrc        # PowerShell: . $PROFILE
```

## Use

```bash
ks-lab az list                 # labs available
ks-lab az break <lab>          # create the broken environment
ks-lab az check <lab>          # check the fix (completion code on a full pass)
ks-lab az clean <lab>          # delete everything the lab created
ks-lab az status               # any lab resource groups still in the subscription
```

`check` and `clean` work out resource names from the subscription, so they still work in a new session.

## Labs

| Lab | Placement | Fault | Creates | Cost |
|---|---|---|---|---|
| `policy-tag-deny` | After 409 | Deny policy requires a `cost-centre` tag | Resource group, policy assignment | Free |
| `nsg-unreachable` | After 414 | NIC NSG deny (priority 100) beats its allow (300) | VNet, 2 NSGs, public IP, Ubuntu B1s VM with nginx, auto-shutdown 19:00 UTC | Pence per hour |
| `storage-403` | After 415 | Storage firewall plus no data-plane role, keys disabled | Storage account, container | Pennies |
| `lock-scopelocked` | After 421 | CanNotDelete lock blocks resource group delete | Storage account, lock | Pennies |
| `kv-reference` | After 431 | App's managed identity has no role on the vault | Key Vault, Free (or B1) App Service | Pennies |

## Notes

- `KS_REGION` overrides the default region (`uksouth`), for example `KS_REGION=ukwest ks-lab az break nsg-unreachable`.
- `storage-403` creates its account outside Cloud Shell's region, because storage IP rules don't apply to same-region traffic. Its check briefly adds Cloud Shell's IP to read the container, then removes it.
- `policy-tag-deny` waits (up to 20 minutes) until the policy is enforcing before handing over.
- Completion codes are deterministic per subscription and lab: `KS-AZ-<LAB>-<8 hex>`.

# shellcheck shell=bash
# GitHub labs: 08-14 and the final assessment.

need_github_repo() {
  in_repo "$KS_REPO"
  origin_is_github || die "your cloud-engineering-lab repo isn't on GitHub yet. Finish lab 08 first."
}
sync_main() {   # fresh, clean local main that matches GitHub
  clean_tree || die "you have uncommitted changes in $KS_REPO. Commit, stash or restore them first."
  git fetch -q --prune origin || die "couldn't reach GitHub. Check your connection and that you can push to the repo."
  git switch -q main || die "couldn't switch to main"
  git merge -q --ff-only origin/main 2>/dev/null || die "your local main has commits GitHub doesn't have. Push or reset them first (ask in Discord if unsure)."
}
remote_branch() { git for-each-ref --format='%(refname:short)' refs/remotes/origin | grep -E "$1" | head -1; }
gh_owner_repo() { git remote get-url origin | sed -E 's#^.*github\.com[:/]##; s#\.git$##'; }

# =====================================================================
# L08 — Publish the repo without leaking anything
# =====================================================================
lab_08_start() {
  build_stage_D
  mkdir -p terraform
  cat > terraform/terraform.tfstate <<'EOF'
{
  "version": 4,
  "terraform_version": "1.9.5",
  "serial": 12,
  "lineage": "6f1c2d1e-3b7a-4c55-9d3e-2a6b8f0c1d22",
  "outputs": {},
  "resources": []
}
EOF
  git add -A; kc "$DAN_N" "$DAN_E" "2026-09-06T17:30:00" "Add current Terraform state for reference"
  mkdir -p terraform/.terraform/providers/registry.terraform.io/hashicorp/azurerm
  printf 'provider binary placeholder\n' > terraform/.terraform/providers/registry.terraform.io/hashicorp/azurerm/terraform-provider-azurerm
  printf 'client_id     = "00000000-0000-0000-0000-000000000000"\nclient_secret = "ks-FAKE-0000-not-a-real-secret"\n' > config/secrets.auto.tfvars
  printf 'junk' > .DS_Store; printf 'junk' > Thumbs.db
  # Terraform rewrites state on every plan: simulate that so the tracked file shows as modified
  sed_replace terraform/terraform.tfstate '"serial": 12' '"serial": 13'
  ticket PLAT-050.md <<'EOF'
# PLAT-050  Move the platform repo to GitHub

Create an empty PUBLIC repository on GitHub called cloud-engineering-lab (no README,
no .gitignore, no licence: your local repo already has history) and publish main to it.

Before anything goes up, make sure none of these can ever be committed:
  - Terraform state (*.tfstate)       - the .terraform/ provider cache
  - *.auto.tfvars (they hold secrets) - .DS_Store and Thumbs.db

Note from Dan: "I committed the state file a while back so people could see it. Sorry."
EOF
  next_steps "$KS_REPO"
}
lab_08_check() {
  check_begin 08
  in_repo "$KS_REPO"
  checkn ".gitignore is committed" "create it, then commit it" tracked .gitignore
  checkn "Terraform state is ignored" "add a pattern for *.tfstate" git check-ignore -q --no-index terraform/terraform.tfstate
  checkn "The .terraform/ cache is ignored" "add a pattern for the folder" git check-ignore -q --no-index terraform/.terraform/providers/x
  checkn "*.auto.tfvars files are ignored" "add a pattern for them" git check-ignore -q --no-index config/secrets.auto.tfvars
  checkn ".DS_Store and Thumbs.db are ignored" "add both" sh -c "git check-ignore -q --no-index .DS_Store && git check-ignore -q --no-index Thumbs.db"
  checkn "The state file is no longer tracked" ".gitignore only affects untracked files. Stop tracking it without deleting it" sh -c "! git ls-files --error-unmatch terraform/terraform.tfstate"
  checkn "The state file still exists on your disk" "deleting it locally would make Terraform think nothing exists. Restore it from history" test -f terraform/terraform.tfstate
  checkn "The secrets file was never committed" "it's in history. Start again: ks-lab start 08" never_committed config/secrets.auto.tfvars
  checkn "Working tree is clean" "commit your changes" clean_tree
  local url; url=$(git remote get-url origin 2>/dev/null)
  checkn "origin points to your GitHub repo cloud-engineering-lab" "git remote add origin <the URL GitHub shows you>" \
    sh -c "printf '%s' '$url' | grep -qiE 'github\.com[:/][^/]+/cloud-engineering-lab(\.git)?/?$'"
  checkn "main tracks origin/main (upstream set)" "push with -u once, so plain git push and git pull work" test "$(git config branch.main.remote)" = "origin"
  local remote_main; remote_main=$(git ls-remote origin refs/heads/main 2>/dev/null | cut -f1)
  checkn "GitHub has your latest main" "git push" test "$remote_main" = "$(git rev-parse main)"
  if [ -z "$(github_user)" ] && [ -n "$url" ]; then
    state_set github_user "$(printf '%s' "$url" | sed -E 's#^.*github\.com[:/]([^/]+)/.*#\1#')"
  fi
  check_end 08
}
lab_08_hints() {
cat <<'EOF'
.gitignore only affects files Git isn't already tracking. Run git status after creating it: what's still showing?
You need to tell Git to stop tracking a file, without deleting it from your disk. Look at the options of git rm.
git rm --cached terraform/terraform.tfstate. Then, as in lesson 329: git remote add origin <url> and git push -u origin main. Your token needs the repo AND workflow scopes.
EOF
}
lab_08_solution() {
cat <<'EOF'

  cat > .gitignore <<'END'
  .terraform/
  *.tfstate
  *.tfstate.*
  *.auto.tfvars
  .DS_Store
  Thumbs.db
  END
  git status                                  # the state file still shows: it's tracked
  git rm --cached terraform/terraform.tfstate
  git add .gitignore
  git commit -m "Ignore Terraform state, provider cache, secrets and OS files"
  git remote add origin https://github.com/<you>/cloud-engineering-lab.git
  git push -u origin main

  Deleted the state file by mistake?  git restore --source=HEAD~1 terraform/terraform.tfstate

  The state file is still in history. Here it holds nothing sensitive. Real state
  often does, and then untracking it is not enough: Break Room scenario 5.

EOF
}

# =====================================================================
# L09 — Day one in an unfamiliar repo
# =====================================================================
lab_09_start() {
  say ""
  say "  Clone this repository into a folder called landing-zone inside $KS_LABS:"
  say ""
  say "      https://github.com/$KS_ORG/novatech-landing-zone"
  say ""
  say "  Then answer the questions on the lab page and check out release/1.2 locally."
  say ""
}
lab_09_check() {
  check_begin 09
  local d="$KS_LABS/landing-zone"
  checkn "landing-zone is cloned in $KS_LABS" "cd $KS_LABS, then git clone <url> landing-zone" test -d "$d/.git"
  if [ -d "$d/.git" ]; then
    cd "$d" || return
    checkn "Its origin is $KS_ORG/novatech-landing-zone" "clone the repo from the lab page" \
      sh -c "git remote get-url origin | grep -qi '$KS_ORG/novatech-landing-zone'"
    checkn "release/1.2 exists locally and tracks origin/release/1.2" "git switch release/1.2 creates a tracking branch" \
      sh -c "test \"\$(git config branch.release/1.2.merge)\" = refs/heads/release/1.2"
  fi
  check_end 09
}
lab_09_hints() {
cat <<'EOF'
Local and remote branches are listed separately. git branch shows only local ones.
git branch -r, git tag, git log -1 <ref>. The README and .github/CODEOWNERS answer two of the questions.
git shortlog -sn counts commits per person. git switch release/1.2 creates a tracking branch when origin/release/1.2 exists.
EOF
}
lab_09_solution() {
cat <<'EOF'

  cd ~/kloudskool-labs
  git clone https://github.com/kloudskool/novatech-landing-zone.git landing-zone
  cd landing-zone
  git remote show origin                    # Q1: HEAD branch
  git branch -r                             # Q2: remote branches
  git for-each-ref --sort=-committerdate refs/remotes --format='%(refname:short) %(subject)'   # Q3
  git tag --sort=-v:refname | head -1       # Q4: then git rev-list -n1 --abbrev-commit <tag>
  cat .github/CODEOWNERS                    # Q5
  cat README.md                             # Q6
  git grep -n address_space                 # Q7
  git shortlog -sn                          # Q8
  git switch release/1.2

EOF
}

# =====================================================================
# L10 — Main moved while you were working
# =====================================================================
edit_l10_scaffold() {
cat > terraform/backup.tf <<'EOF'
resource "azurerm_recovery_services_vault" "platform" {
  name                = "rsv-platform-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.platform.name
  sku                 = "Standard"
  tags                = var.default_tags
}
EOF
}
edit_l10a() { printf '6. Post a summary in #platform-alerts when the incident is closed.\n' >> docs/runbooks/disk-space.md; }
edit_l10b() {
cat >> terraform/backup.tf <<'EOF'

resource "azurerm_backup_policy_vm" "daily" {
  name                = "daily-vm-backup"
  resource_group_name = azurerm_resource_group.platform.name
  recovery_vault_name = azurerm_recovery_services_vault.platform.name

  backup {
    frequency = "Daily"
    time      = "23:00"
  }
}
EOF
}
lab_10_start() {
  need_github_repo; sync_main
  if [ -z "$(git ls-remote origin refs/heads/feature/PLAT-040-backup-policy)" ]; then
    teammate_push feature/PLAT-040-backup-policy origin/main "$PRIYA_N" "$PRIYA_E" "2026-09-08T09:00:00" \
      "PLAT-040: Scaffold recovery services vault" edit_l10_scaffold >/dev/null
  fi
  git fetch -q origin
  git config --unset ks.e10a 2>/dev/null; git config --unset ks.e10b 2>/dev/null
  ticket PLAT-040.md <<'EOF'
# PLAT-040  Backup policy   (pairing: you + Priya)

Priya has started the branch feature/PLAT-040-backup-policy on GitHub.
Your part: add this variable to terraform/variables.tf on that branch.

variable "backup_retention_days" {
  type    = number
  default = 30
}
EOF
  say "  Priya pushed feature/PLAT-040-backup-policy to your GitHub repo."
  next_steps "$KS_REPO"
}
event_10a() {
  need_github_repo
  local s; s=$(teammate_push main "" "$PRIYA_N" "$PRIYA_E" "2026-09-08T10:30:00" "Add incident summary step to disk space runbook" edit_l10a)
  [ -n "$s" ] || die "Priya's push to main failed. If you've already protected main, turn protection off for this lab."
  git config ks.e10a "$s"
  say ""; say "  Priya just pushed a commit to main on GitHub. Your local repo doesn't know yet."; say ""
}
event_10b() {
  need_github_repo
  local s; s=$(teammate_push feature/PLAT-040-backup-policy "" "$PRIYA_N" "$PRIYA_E" "2026-09-08T11:15:00" "PLAT-040: Add daily VM backup policy" edit_l10b)
  [ -n "$s" ] || die "Priya's push failed"
  git config ks.e10b "$s"
  say ""; say "  Priya just pushed to feature/PLAT-040-backup-policy. Now try to push your commit."; say ""
}
lab_10_check() {
  check_begin 10
  need_github_repo
  git fetch -q --prune origin
  local a b me rb; a=$(ks_get e10a); b=$(ks_get e10b); me=$(git config user.email); rb=origin/feature/PLAT-040-backup-policy
  checkn "You ran both events (10a and 10b)" "the lab page says when" sh -c "test -n '$a' && test -n '$b'"
  checkn "Priya's main commit is in your local main" "bring your local main up to date" is_ancestor "${a:-x}" main
  checkn "Local main matches GitHub" "git status on main should say up to date" test "$(git rev-parse main)" = "$(git rev-parse origin/main)"
  checkn "Priya's branch commit is still on GitHub (no force push)" "never --force a shared branch. Restart: ks-lab start 10" is_ancestor "${b:-x}" "$rb"
  checkn "Your variable is on the branch on GitHub" "commit it on the branch and push" blob_has "$rb" terraform/variables.tf 'backup_retention_days'
  checkn "The change is your commit" "commit it under your own identity" \
    sh -c "test -n \"\$(git log --author='$me' --format=%H origin/main..$rb -- terraform/variables.tf)\""
  checkn "Your local branch matches GitHub" "push, or pull, until they match" \
    test "$(git rev-parse -q --verify feature/PLAT-040-backup-policy)" = "$(git rev-parse "$rb")"
  check_end 10
}
lab_10_hints() {
cat <<'EOF'
git fetch downloads what's new on GitHub without touching your files. Then compare: git log main..origin/main
"Updates were rejected" means GitHub has commits you don't. Bring them in, then push again.
git pull (merges Priya's commit with yours), then git push. Never --force a branch someone else pushes to.
EOF
}
lab_10_solution() {
cat <<'EOF'

  # Part A
  ks-lab event 10a
  git fetch
  git log --stat main..origin/main         # what changed, and who
  git pull                                 # on main
  # Part B
  git switch feature/PLAT-040-backup-policy
  # add the variable to terraform/variables.tf
  git commit -am "PLAT-040: Add backup retention variable"
  ks-lab event 10b
  git push                                 # rejected (fetch first)
  git pull                                 # merges Priya's commit; save the message
  git push

EOF
}

# =====================================================================
# L11 — The urgent hotfix
# =====================================================================
lab_11_start() {
  need_github_repo; sync_main
  git branch -D feature/PLAT-045-alerts >/dev/null 2>&1
  git switch -q -c feature/PLAT-045-alerts
  sed_replace scripts/check-cpu.sh 'THRESHOLD=85' 'THRESHOLD=85   # WIP PLAT-045: move to alert-config.json'
  printf '{\n  "cpuThresholdPercent": 85,\n  "notify": "platform-alerts@novatech.example"\n}\n' > scripts/alert-config.json
  ticket PLAT-045.md <<'EOF'
# PLAT-045  CPU alerting   (yours, in progress)

Add scripts/alert-config.json and move the CPU threshold into it.
EOF
  ticket PLAT-046.md <<'EOF'
# PLAT-046  URGENT: production health check calls the retired endpoint

scripts/health-check.sh still calls https://status.novatech.example/healthz
It must call    https://status.novatech.example/api/v2/health
Branch from main. Change only that URL. Push the branch so it can be reviewed.
EOF
  say "  You're half-way through PLAT-045 on feature/PLAT-045-alerts: one file edited,"
  say "  one new file, nothing committed. Then the on-call engineer pings you (PLAT-046)."
  next_steps "$KS_REPO"
}
lab_11_check() {
  check_begin 11
  need_github_repo
  git fetch -q --prune origin
  local hb; hb=$(remote_branch '^origin/hotfix/PLAT-046-[a-z0-9-]+$')
  checkn "hotfix/PLAT-046-... is on GitHub" "name it per CONTRIBUTING.md and push it" test -n "$hb"
  if [ -n "$hb" ]; then
    checkn "The hotfix branch has exactly one commit on top of main" "branch it from main, one commit" test "$(git rev-list --count "origin/main..$hb")" = "1"
    checkn "That commit changes only scripts/health-check.sh" "your WIP came along. Stash it first, including new files" \
      test "$(git diff --name-only "origin/main...$hb")" = "scripts/health-check.sh"
    checkn "It points at /api/v2/health" "check the URL in the ticket" blob_has "$hb" scripts/health-check.sh 'api/v2/health'
    checkn "alert-config.json isn't on the hotfix branch" "untracked files need an extra option to be stashed" sh -c "! git cat-file -e $hb:scripts/alert-config.json"
  fi
  checkn "You're back on feature/PLAT-045-alerts" "git switch feature/PLAT-045-alerts" on_branch feature/PLAT-045-alerts
  checkn "Your WIP edit to check-cpu.sh is back" "git stash pop" file_has scripts/check-cpu.sh 'WIP PLAT-045'
  checkn "alert-config.json is back" "git stash pop" test -f scripts/alert-config.json
  checkn "Nothing left in the stash" "a forgotten stash is forgotten work" test -z "$(git stash list)"
  check_end 11
}
lab_11_hints() {
cat <<'EOF'
Which changes does a plain stash take? Stash, then look at Source Control or git status: is the new file still there?
New (untracked) files need the Include Untracked option: in VS Code it's Stash > Stash (Include Untracked).
Stash (Include Untracked), or git stash push -u. Then switch to main and create hotfix/PLAT-046-health-url. Afterwards Pop Stash (lesson 330), or git stash pop.
EOF
}
lab_11_solution() {
cat <<'EOF'

  git stash push -u -m "PLAT-045 WIP"
  git status                                   # clean
  git switch main && git pull
  git switch -c hotfix/PLAT-046-health-url
  # change HEALTH_URL in scripts/health-check.sh
  git commit -am "PLAT-046: Point health check at api/v2/health"
  git push -u origin hotfix/PLAT-046-health-url
  git switch feature/PLAT-045-alerts
  git stash pop

EOF
}

# =====================================================================
# L12 — First PR, and the review that follows
# =====================================================================
lab_12_start() {
  need_github_repo
  git fetch -q --prune origin
  ticket PLAT-045-finish.md <<'EOF'
# PLAT-045  CPU alerting: finish and put up for review

Finish your work on feature/PLAT-045-alerts:
  - commit scripts/alert-config.json
  - tidy the WIP comment in scripts/check-cpu.sh
Open a pull request into main and fill in every section of the template.
A reviewer will comment within a minute or two.
EOF
  say ""
  say "  Before you start: protect main on GitHub (the lab page shows how)."
  say "  Then: PR for PLAT-046, then finish PLAT-045 and open its PR."
  say ""
}
lab_12_check() {
  check_begin 12
  need_github_repo
  git fetch -q --prune origin
  checkn "The hotfix is in main on GitHub" "merge the PLAT-046 pull request" blob_has origin/main scripts/health-check.sh 'api/v2/health'
  checkn "check-cpu.sh in main uses set -euo pipefail" "review point 2" blob_has origin/main scripts/check-cpu.sh 'set -euo pipefail'
  checkn "check-cpu.sh in main reads CPU_THRESHOLD" "review point 1" blob_has origin/main scripts/check-cpu.sh 'CPU_THRESHOLD:-'
  checkn "Merged branches are gone from GitHub" "delete them after merging" test -z "$(remote_branch '^origin/(feature/PLAT-045|hotfix/PLAT-046)')"
  checkn "Merged branches are gone locally" "git branch -d ..." test -z "$(find_branch '^(feature/PLAT-045|hotfix/PLAT-046)')"
  checkn "Local main matches GitHub" "git switch main && git pull" test "$(git rev-parse main)" = "$(git rev-parse origin/main)"
  check_end 12 "Now run the GitHub check: Actions tab > KloudSkool lab check > Run workflow > lab 12. Your completion code is in its summary."
}
lab_12_hints() {
cat <<'EOF'
A pull request shows whatever is on its branch. New commits pushed to that branch appear in it automatically.
Fix the code, commit, git push. Then reply on the pull request saying what you changed. Edit the description for the ticket id.
Merge on GitHub, delete the branch there, then locally: git switch main, git pull, git branch -d <branch>, git fetch --prune.
EOF
}
lab_12_solution() {
cat <<'EOF'

  # P5: Settings > Rules > Rulesets > New branch ruleset: target the default branch,
  #     tick "Require a pull request before merging" (0 approvals), Enforcement: Active
  # 1. Open a PR from hotfix/PLAT-046-health-url into main on GitHub, merge it
  # 2.
  git switch feature/PLAT-045-alerts
  git add -A && git commit -m "PLAT-045: Add CPU alert configuration"
  git push -u origin feature/PLAT-045-alerts        # open the PR, fill the template
  # 3. after the review:
  #    check-cpu.sh: add  set -euo pipefail  and  THRESHOLD="${CPU_THRESHOLD:-85}"
  git commit -am "PLAT-045: Read CPU threshold from environment"
  git push                                          # PR updates; add PLAT-045 to the description; reply
  # 4. merge on GitHub, delete the branch, then:
  git switch main && git pull
  git branch -d feature/PLAT-045-alerts hotfix/PLAT-046-health-url
  git fetch --prune

EOF
}

# =====================================================================
# L13 — Contribute to a repo you don't own
# =====================================================================
lab_13_start() {
  say ""
  say "  Upstream repo: https://github.com/$KS_ORG/cloud-runbooks"
  say "  Clone YOUR fork into $KS_LABS/cloud-runbooks. Instructions are on the lab page."
  say ""
}
lab_13_check() {
  check_begin 13
  local d="$KS_LABS/cloud-runbooks"
  checkn "Your fork is cloned into $KS_LABS/cloud-runbooks" "clone your fork, not the original" test -d "$d/.git"
  if [ -d "$d/.git" ]; then
    cd "$d" || return
    checkn "origin is your fork" "origin should point at github.com/<you>/cloud-runbooks" \
      sh -c "git remote get-url origin | grep -qiE 'github\.com[:/][^/]+/cloud-runbooks' && ! git remote get-url origin | grep -qi '$KS_ORG/'"
    checkn "upstream points at $KS_ORG/cloud-runbooks" "git remote add upstream <original repo URL>" \
      sh -c "git remote get-url upstream | grep -qi '$KS_ORG/cloud-runbooks'"
  fi
  check_end 13 "Now run the GitHub check in your cloud-engineering-lab repo: Actions > KloudSkool lab check > Run workflow > lab 13."
}
lab_13_hints() {
cat <<'EOF'
Your fork doesn't update itself, and by default it only copied the main branch. CONTRIBUTING.md says where pull requests go.
Add the original repo as a second remote, usually called upstream, and fetch it.
git fetch upstream, then branch from upstream/develop (or merge it into your branch), fill in the new template headings, push, and open the PR into develop.
EOF
}
lab_13_solution() {
cat <<'EOF'

  # fork kloudskool/cloud-runbooks on GitHub, then:
  cd ~/kloudskool-labs
  git clone https://github.com/<you>/cloud-runbooks.git
  cd cloud-runbooks
  git remote add upstream https://github.com/kloudskool/cloud-runbooks.git
  git fetch upstream
  git switch -c runbook/vm-wont-start upstream/develop
  cp runbooks/TEMPLATE.md runbooks/<you>-vm-wont-start.md     # fill it in
  git add runbooks/ && git commit -m "Add runbook: Azure VM won't start"
  git push -u origin runbook/vm-wont-start
  # open a PR: base repository kloudskool/cloud-runbooks, base: develop

  Already opened it from a branch based on main? Don't open a second PR:
  git fetch upstream && git merge upstream/develop, add the new headings, push.

EOF
}

# =====================================================================
# L14 — Release v1.0.0 of the storage module
# =====================================================================
edit_l14_tls() {
  sed_replace terraform/modules/storage-account/main.tf '  account_replication_type = "LRS"' '  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"'
}
lab_14_start() {
  need_github_repo; sync_main
  if [ -z "$(git ls-remote origin refs/heads/fix/PLAT-055-storage-tls)" ]; then
    teammate_push fix/PLAT-055-storage-tls origin/main "$(me_name)" "$(me_email)" "2026-09-10T09:00:00" \
      "PLAT-055: Enforce TLS 1.2 minimum on storage accounts" edit_l14_tls >/dev/null
  fi
  git fetch -q origin
  ticket PLAT-054.md <<'EOF'
# PLAT-054  Release the storage module

The app team wants to use terraform/modules/storage-account but won't point at main.
1. Release the current main as v1.0.0: annotated tag, plus a GitHub Release with short notes.
2. Your fix fix/PLAT-055-storage-tls is on GitHub. Get it into main through a pull request,
   then release v1.0.1 the same way.
3. In docs/architecture.md, add the module source line the app team should use to pin v1.0.1:
   source = "git::https://github.com/<you>/cloud-engineering-lab.git//terraform/modules/storage-account?ref=v1.0.1"
EOF
  next_steps "$KS_REPO"
}
tag_annotated() { [ "$(git cat-file -t "$1" 2>/dev/null)" = "tag" ]; }
tag_on_remote() { [ -n "$(git ls-remote origin "refs/tags/$1^{}")" ]; }
release_has_notes() {
  local body; body=$(curl -s "https://api.github.com/repos/$(gh_owner_repo)/releases/tags/$1" 2>/dev/null)
  printf '%s' "$body" | grep -q '"tag_name"' && printf '%s' "$body" | grep -qE '"body": *"[^"]'
}
lab_14_check() {
  check_begin 14
  need_github_repo
  git fetch -q --prune --tags --force origin
  checkn "v1.0.0 is an annotated tag" "git tag -a creates annotated tags" tag_annotated v1.0.0
  checkn "v1.0.0 is on GitHub" "tags are pushed separately" tag_on_remote v1.0.0
  checkn "v1.0.0 is the release before the TLS fix" "tag main before the PLAT-055 merge" \
    sh -c "git cat-file -e v1.0.0^{commit} && ! git show v1.0.0:terraform/modules/storage-account/main.tf | grep -q TLS1_2"
  checkn "v1.0.1 is an annotated tag" "git tag -a" tag_annotated v1.0.1
  checkn "v1.0.1 is on GitHub" "git push origin v1.0.1" tag_on_remote v1.0.1
  checkn "v1.0.1 includes the TLS fix" "pull main after merging, then tag" blob_has v1.0.1 terraform/modules/storage-account/main.tf 'TLS1_2'
  checkn "Both tags are on main's history" "tag commits on main, not on the fix branch" sh -c "git merge-base --is-ancestor v1.0.0 origin/main && git merge-base --is-ancestor v1.0.1 origin/main"
  checkn "The docs pin ?ref=v1.0.1" "PLAT-054 step 3" blob_has origin/main docs/architecture.md 'ref=v1\.0\.1'
  checkn "GitHub Release v1.0.1 exists with notes" "Releases > Draft a new release > choose v1.0.1, write notes" release_has_notes v1.0.1
  check_end 14
}
lab_14_hints() {
cat <<'EOF'
Lesson 333: an annotated tag (-a) stores a message, author and date. A bug fix bumps the last number.
git pull main first, then git tag -a v1.0.0 -m "...". Tags don't go up with a plain git push.
git push origin v1.0.0. On GitHub: Releases > Draft a new release > choose the tag.
EOF
}
lab_14_solution() {
cat <<'EOF'

  git switch main && git pull
  git tag -a v1.0.0 -m "storage-account module: first release"
  git push origin v1.0.0                     # then Releases > Draft a new release > v1.0.0
  # PR fix/PLAT-055-storage-tls -> main on GitHub, merge, delete branch
  git pull
  git tag -a v1.0.1 -m "Enforce TLS 1.2 minimum"
  git push origin v1.0.1                     # and a Release for v1.0.1 with notes
  git switch -c feature/PLAT-054-pin-docs
  # add the source line to docs/architecture.md, commit, push, PR, merge

EOF
}

# =====================================================================
# FINAL — Your first week at NovaTech
# =====================================================================
FINAL_DIR="$KS_LABS/novatech-platform"
FINAL_KEY="ks-FAKE-predecessor-7731-not-real"
ks_seed() {  # 0, 1 or 2, from the GitHub username
  local d; d=$(printf 'kloudskool:seed:%s' "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" | git hash-object --stdin | cut -c1)
  printf '%s' $(( 16#$d % 3 ))
}
final_version() { case "$1" in 0) printf 'v2.3.0';; 1) printf 'v2.4.0';; *) printf 'v3.1.0';; esac; }
edit_final_priya1() {
cat > scripts/tag-audit.sh <<'EOF'
#!/usr/bin/env bash
# List Azure resources missing a required tag.
set -euo pipefail
TAG="${1:-cost_centre}"
az resource list --query "[?tags.${TAG}==null].{name:name, type:type}" -o table
EOF
  chmod +x scripts/tag-audit.sh
  add_readme_row 'scripts/tag-audit.sh' 'Lists resources missing a required tag'
}
edit_final_priya2() {
cat >> terraform/variables.tf <<'EOF'

variable "required_tags" {
  type    = list(string)
  default = ["environment", "owner", "cost_centre"]
}
EOF
}
lab_final_start() {
  need_github_user
  local u url seed ver
  u=$(github_user); url="${KS_FINAL_URL:-https://github.com/$u/novatech-platform.git}"
  say "  Your assessment repo: $url"
  if ! git ls-remote "$url" >/dev/null 2>&1; then
    die "I can't reach $url. Create an EMPTY public repo called novatech-platform on GitHub first (no README)."
  fi
  [ -z "$(git ls-remote "$url")" ] || die "$url isn't empty. Delete it and create it again, empty, then re-run."
  seed=$(ks_seed "$u"); ver=$(final_version "$seed")
  new_repo "$FINAL_DIR"
  write_all
  git add scripts && kc "$SAM_N" "$SAM_E" "2026-07-01T09:00:00" "Add operational scripts"
  git add terraform && kc "$SAM_N" "$SAM_E" "2026-07-01T09:20:00" "Add core Terraform"
  git add -A && kc "$DAN_N" "$DAN_E" "2026-07-02T10:00:00" "Add docs, standards and workflows"
  printf '.terraform/\n*.tfstate\n*.tfstate.*\n*.auto.tfvars\n.DS_Store\nThumbs.db\n' > .gitignore
  git add -A && kc "$LEA_N" "$LEA_E" "2026-07-03T11:00:00" "Ignore state, secrets and OS files"
  write_cpu_script; add_readme_row 'scripts/check-cpu.sh' 'Alerts when CPU load passes the threshold'
  git add -A && kc "$PRIYA_N" "$PRIYA_E" "2026-07-08T09:30:00" "PLAT-012: Add CPU usage check script"
  sed_replace scripts/backup-logs.sh 'RETENTION_DAYS=14' 'RETENTION_DAYS=30'
  git add -A && kc "$LEA_N" "$LEA_E" "2026-07-14T15:00:00" "PLAT-015: Keep log archives for 30 days"
  write_tags_resolved
  git add -A && kc "$SAM_N" "$SAM_E" "2026-07-21T10:00:00" "PLAT-021: Add data classification and cost centre tags"
  write_rotate_script; add_readme_row 'scripts/rotate-logs.sh' 'Rotates application logs daily'
  git add -A && kc "$DAN_N" "$DAN_E" "2026-07-28T16:00:00" "PLAT-030: Add log rotation script"
  sed_replace docs/architecture.md 'No secondary region yet.' 'Secondary region: UK West (disaster recovery).'
  git add -A && kc "$LEA_N" "$LEA_E" "2026-08-04T09:45:00" "PLAT-031: Document UK West as secondary region"
  # the bad commit lands at a position that depends on the student
  local i
  for i in 0 1 2 3; do
    if [ "$i" = "$seed" ]; then
      sed_replace terraform/environments/prod.tfvars 'Standard_B2s' 'Standard_D64s_v5'
      git add -A && kc "$DAN_N" "$DAN_E" "2026-09-2${i}T17:40:00" "Tidy formatting in prod tfvars"
    fi
    case "$i" in
      0) sed_replace scripts/health-check.sh 'TIMEOUT=10' 'TIMEOUT=20'
         git add -A && kc "$PRIYA_N" "$PRIYA_E" "2026-09-2${i}T10:00:00" "PLAT-090: Raise health check timeout to 20 seconds" ;;
      1) printf '5. Record what you removed in the incident ticket.\n' >> docs/runbooks/disk-space.md
         git add -A && kc "$LEA_N" "$LEA_E" "2026-09-2${i}T11:00:00" "PLAT-091: Add incident record step to runbook" ;;
      2) sed_replace config/app-settings.json '"logLevel": "info"' '"logLevel": "warn"'
         git add -A && kc "$SAM_N" "$SAM_E" "2026-09-2${i}T12:00:00" "PLAT-093: Reduce platform log level to warn" ;;
      3) sed_replace README.md 'Last reviewed: 2026-09-01' 'Last reviewed: 2026-09-23'
         git add -A && kc "$SAM_N" "$SAM_E" "2026-09-2${i}T13:00:00" "PLAT-095: Update README review date" ;;
    esac
  done
  local start; start=$(git rev-parse HEAD)
  git tag assessment-start "$start"
  git switch -q -c feature/PLAT-098-tagging
  edit_final_priya1; git add -A && kc "$PRIYA_N" "$PRIYA_E" "2026-09-24T09:00:00" "PLAT-098: Add tag audit script"
  edit_final_priya2; git add -A && kc "$PRIYA_N" "$PRIYA_E" "2026-09-24T09:30:00" "PLAT-098: Add required tags variable"
  git switch -q main
  git remote add origin "$url"
  git push -q -u origin main 2>&1 | grep -v '^remote:'
  git push -q origin feature/PLAT-098-tagging assessment-start 2>&1 | grep -v '^remote:'
  git branch -D feature/PLAT-098-tagging >/dev/null
  git fetch -q origin
  # the predecessor's leftovers
  sed_replace scripts/health-check.sh 'set -euo pipefail' 'set -euo pipefail
echo "DEBUG: predecessor testing new endpoint"'
  printf 'AZURE_CLIENT_SECRET=%s\n' "$FINAL_KEY" > config/local.env
  mkdir -p "$KS_LABS/tickets/final"
  ticket final/README.md <<EOF
# Your first week at NovaTech

Sam (your lead) is at a conference. Work through the tickets in this folder in the
order you think is right. Everything reaches main through a pull request, following
CONTRIBUTING.md. Nobody will tell you which Git commands to use.

You've been handed the previous engineer's laptop clone: $FINAL_DIR
They left in a hurry. Check what state it's in before you do anything.
EOF
  ticket final/PLAT-102.md <<'EOF'
# PLAT-102   Priority P1   Finance alert

Production compute costs jumped this week. Find the cause in the repo and undo it safely.
In your pull request description, name the offending commit (short hash) and its author.
EOF
  ticket final/PLAT-098.md <<'EOF'
# PLAT-098   Priority P2   Tagging (Priya, on leave)

Priya's branch feature/PLAT-098-tagging is on GitHub and Sam has approved it. Get it into main.
EOF
  ticket final/PLAT-101.md <<'EOF'
# PLAT-101   Priority P2   Certificate expiry check

1. Add scripts/check-cert-expiry.sh (below), executable.
2. Add it to the README scripts table: "Warns when the platform certificate is close to expiry".
3. Add to the END of terraform/variables.tf:

variable "cert_expiry_alert_days" {
  type    = number
  default = 30
}

----- scripts/check-cert-expiry.sh -----
#!/usr/bin/env bash
# Warn when the platform TLS certificate expires soon.
set -euo pipefail
HOST="status.novatech.example"
EXPIRY=$(echo | openssl s_client -servername "$HOST" -connect "$HOST:443" 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2)
DAYS_LEFT=$(( ( $(date -d "$EXPIRY" +%s) - $(date +%s) ) / 86400 ))
if [ "$DAYS_LEFT" -lt 30 ]; then
  echo "WARNING: certificate for $HOST expires in $DAYS_LEFT days"
  exit 1
fi
echo "OK: certificate for $HOST valid for $DAYS_LEFT days"
-----------------------------------------
EOF
  ticket final/PLAT-104.md <<EOF
# PLAT-104   Priority P3   Release

When PLAT-102, PLAT-098 and PLAT-101 are all in main, release main as $ver:
an annotated tag and a GitHub Release whose notes name all three tickets.
EOF
  ticket final/SETUP.md <<'EOF'
# Before you merge anything

CONTRIBUTING.md says main is protected. It isn't yet. Protect it so every change needs a pull request.
EOF
  say ""
  say "  Assessment repo pushed to GitHub. Tickets: $KS_LABS/tickets/final/"
  next_steps "$FINAL_DIR"
}
lab_final_check() {
  check_begin final
  in_repo "$FINAL_DIR"
  git fetch -q --prune origin
  checkn "The predecessor's secret was never pushed" "this is an automatic fail. Ask in Discord how to clean it up" \
    sh -c "test -z \"\$(git log --remotes -S'$FINAL_KEY' --format=%H -- . ':(exclude).github')\""
  checkn "The predecessor's debug line was never pushed" "throw that change away" \
    sh -c "test -z \"\$(git log --remotes -S'DEBUG: predecessor' --format=%H -- . ':(exclude).github')\""
  checkn "Shared history wasn't rewritten" "never reset or force push main" is_ancestor assessment-start origin/main
  check_end final "Now get your score: in your novatech-platform repo, Actions > KloudSkool lab check > Run workflow > final."
}
lab_final_hints() {
cat <<'EOF'
Start where you'd start on a real first day: git status in the clone you were handed. Then read every ticket before touching anything.
Priorities matter: the P1 goes first. git log -S finds when a value appeared. A shared mistake is undone with a revert, through a pull request.
When PLAT-101 conflicts with Priya's work, resolve it on your branch: bring main into it, keep both sides, push.
EOF
}
lab_final_solution() {
cat <<'EOF'

  This is the assessment, so there's no walkthrough here. Every skill it needs is in
  labs 01-14 and the Break Room. Re-do the lab that covers the part you're stuck on.

EOF
}

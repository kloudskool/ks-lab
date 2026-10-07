# shellcheck shell=bash
# Break Room T01-T12 and bonus labs B1, B2. All local: "GitHub" is simulated with local remotes.

brk_dir() { printf '%s/break-%s' "$KS_LABS" "$1"; }
brk_base() {   # brk_base <NN> [protect] : repo with history, pushed to its own local remote
  local nn="$1" d r
  d=$(brk_dir "$nn"); new_repo "$d"
  write_all
  git add scripts && kc "$SAM_N" "$SAM_E" "2026-08-01T09:00:00" "Add operational scripts"
  git add terraform && kc "$SAM_N" "$SAM_E" "2026-08-01T09:20:00" "Add core Terraform"
  git add -A && kc "$DAN_N" "$DAN_E" "2026-08-02T10:00:00" "Add docs and standards"
  r=$(new_bare_remote "break-$nn")
  git remote add origin "$r"
  git push -q -u origin main 2>/dev/null
  [ "${2:-}" = "protect" ] && protect_main_hook "$r"
  return 0
}
brk_next() { next_steps "$(brk_dir "$1")"; }
on_remote_branch() { git for-each-ref --format='%(refname:short)' refs/remotes/origin | grep -E "$1" | head -1; }

# ---------- T01 Started on the wrong branch (uncommitted) ----------
lab_t01_start() {
  brk_base t01
  ks_put start "$(git rev-parse HEAD)"
  sed_replace scripts/backup-logs.sh 'RETENTION_DAYS=14' 'RETENTION_DAYS=7'
  printf '\nvariable "backup_schedule" {\n  type    = string\n  default = "23:00"\n}\n' >> terraform/variables.tf
  ticket T01.md <<'EOF'
# T01  "I've done half the ticket on main"

You've been working on PLAT-060 (backup schedule) for an hour. git status says: On branch main.
Nothing is committed yet. The work belongs on feature/PLAT-060-backup-schedule, committed there.
main must end up exactly as it was. Don't lose anything.
EOF
  brk_next t01
}
lab_t01_check() {
  check_begin t01; in_repo "$(brk_dir t01)"
  local b; b=$(find_branch '^feature/PLAT-060-[a-z0-9-]+$')
  checkn "main is exactly as it was" "nothing should be committed on main" test "$(git rev-parse main)" = "$(ks_get start)"
  checkn "A feature/PLAT-060-... branch exists" "create it: your uncommitted changes come with you" test -n "$b"
  checkn "Both changes are committed on it" "commit the retention and schedule changes on the branch" \
    sh -c "test -n '$b' && git show '$b:scripts/backup-logs.sh' | grep -q 'RETENTION_DAYS=7' && git show '$b:terraform/variables.tf' | grep -q backup_schedule"
  checkn "Working tree is clean" "git status" clean_tree
  check_end t01
}
lab_t01_hints() { printf '%s\n' "Uncommitted changes aren't on any branch yet. They travel with you when you switch." "Creating a new branch from where you are keeps the changes in your working tree." "git switch -c feature/PLAT-060-backup-schedule, then commit."; }
lab_t01_solution() { say ""; say "  git switch -c feature/PLAT-060-backup-schedule"; say "  git commit -am \"PLAT-060: Add nightly backup schedule\""; say ""; say "  If the branch already existed: git stash -u, git switch <branch>, git stash pop."; say ""; }

# ---------- T02 Committed to main instead of a branch ----------
lab_t02_start() {
  brk_base t02 protect
  ks_put start "$(git rev-parse HEAD)"
  printf '\nvariable "log_analytics_sku" {\n  type    = string\n  default = "PerGB2018"\n}\n' >> terraform/variables.tf
  git add -A; kc_me "2026-09-10T10:00:00" "PLAT-061: Add Log Analytics SKU variable"
  printf '\n## Monitoring\n\nLogs go to the shared Log Analytics workspace.\n' >> docs/architecture.md
  git add -A; kc_me "2026-09-10T10:20:00" "PLAT-061: Document monitoring workspace"
  ks_put tip "$(git rev-parse HEAD)"
  ticket T02.md <<'EOF'
# T02  "My push to main was rejected"

You made two commits for PLAT-061... on main. git push says:

  remote: error: GH006: Protected branch update failed for refs/heads/main.

Get both commits onto a branch called feature/PLAT-061-<something> on the remote (ready for a PR),
and get your local main back to matching the remote's main.
EOF
  brk_next t02
}
lab_t02_check() {
  check_begin t02; in_repo "$(brk_dir t02)"
  git fetch -q --prune origin
  local rb; rb=$(on_remote_branch '^origin/feature/PLAT-061-[a-z0-9-]+$')
  checkn "A feature/PLAT-061-... branch is on the remote" "create the branch where you are, then push it" test -n "$rb"
  checkn "It holds both of your commits" "the branch should point at your second commit" sh -c "test -n '$rb' && git merge-base --is-ancestor $(ks_get tip) '$rb'"
  checkn "Local main matches the remote's main" "move main back to origin/main" test "$(git rev-parse main)" = "$(git rev-parse origin/main)"
  checkn "Working tree is clean" "git status" clean_tree
  check_end t02
}
lab_t02_hints() { printf '%s\n' "A branch is a label pointing at a commit. You can put a new label where you are without moving anything." "Create the branch first (so the commits are safe), then move main back." "git branch feature/PLAT-061-monitoring, then git reset --hard origin/main on main, then push the branch."; }
lab_t02_solution() { say ""; say "  git branch feature/PLAT-061-monitoring"; say "  git reset --hard origin/main          # safe: the commits are on the new branch"; say "  git switch feature/PLAT-061-monitoring"; say "  git push -u origin feature/PLAT-061-monitoring"; say ""; }

# ---------- T03 Push rejected ----------
edit_t03_priya() { printf '\nvariable "dns_zone_name" {\n  type    = string\n  default = "platform.novatech.example"\n}\n' > terraform/dns.tf; }
lab_t03_start() {
  brk_base t03
  git switch -q -c feature/PLAT-062-dns
  printf '# DNS\n\nPrivate DNS zone for platform services.\n' > docs/dns.md
  git add -A; kc "$PRIYA_N" "$PRIYA_E" "2026-09-11T09:00:00" "PLAT-062: Start DNS documentation"
  git push -q -u origin feature/PLAT-062-dns 2>/dev/null
  # Priya pushes again from her own clone
  local tmp; tmp=$(mktemp -d 2>/dev/null || mktemp -d -t kslab)
  git clone -q "$(git remote get-url origin)" "$tmp/p" && (cd "$tmp/p" && git switch -q feature/PLAT-062-dns && edit_t03_priya && git add -A && kc "$PRIYA_N" "$PRIYA_E" "2026-09-11T11:00:00" "PLAT-062: Add DNS zone variable" && git push -q 2>/dev/null && git rev-parse HEAD > "$tmp/sha")
  ks_put priya "$(cat "$tmp/sha")"; rm -rf "$tmp"
  printf '\nThe zone is linked to the hub VNet.\n' >> docs/dns.md
  git add -A; kc_me "2026-09-11T11:30:00" "PLAT-062: Note hub VNet link in DNS docs"
  ticket T03.md <<'EOF'
# T03  "Updates were rejected"

You and Priya are both on feature/PLAT-062-dns. You committed and ran git push:

  ! [rejected]        feature/PLAT-062-dns -> feature/PLAT-062-dns (fetch first)

Get your commit onto the remote branch without removing Priya's.
EOF
  brk_next t03
}
lab_t03_check() {
  check_begin t03; in_repo "$(brk_dir t03)"
  git fetch -q origin
  checkn "Priya's commit is still on the remote (no force push)" "never --force a shared branch. Restart: ks-lab break 3" is_ancestor "$(ks_get priya)" origin/feature/PLAT-062-dns
  checkn "Your commit is on the remote" "pull, then push" sh -c "git log origin/feature/PLAT-062-dns --format=%s | grep -q 'hub VNet link'"
  checkn "Local branch matches the remote" "push" test "$(git rev-parse feature/PLAT-062-dns)" = "$(git rev-parse origin/feature/PLAT-062-dns)"
  check_end t03
}
lab_t03_hints() { printf '%s\n' "The remote has a commit you don't. You need it before you can push." "git pull brings it in and merges it with yours." "git pull, then git push. Never git push --force here."; }
lab_t03_solution() { say ""; say "  git pull        # merge Priya's commit with yours"; say "  git push"; say ""; }

# ---------- T04 Bad change already on shared main ----------
lab_t04_start() {
  brk_base t04
  sed_replace terraform/environments/prod.tfvars 'Standard_B2s' 'Standard_D64s_v5'
  git add -A; kc "$DAN_N" "$DAN_E" "2026-09-12T17:40:00" "Tidy formatting in prod tfvars"
  ks_put bad "$(git rev-parse HEAD)"
  sed_replace scripts/health-check.sh 'TIMEOUT=10' 'TIMEOUT=20'; git add -A; kc "$PRIYA_N" "$PRIYA_E" "2026-09-13T09:00:00" "Raise health check timeout"
  printf '5. Record what you removed.\n' >> docs/runbooks/disk-space.md; git add -A; kc "$LEA_N" "$LEA_E" "2026-09-13T10:00:00" "Add record step to runbook"
  sed_replace README.md 'Last reviewed: 2026-09-01' 'Last reviewed: 2026-09-13'; git add -A; kc "$SAM_N" "$SAM_E" "2026-09-13T11:00:00" "Update README review date"
  git push -q origin main 2>/dev/null
  protect_main_hook "$KS_REMOTES/break-t04.git"
  ks_put start "$(git rev-parse HEAD)"
  ticket T04.md <<'EOF'
# T04  Finance: "Why did production compute triple?"

Someone changed the production VM size this week. Three more commits have landed on main since.
main is protected and everyone has pulled it. Undo the bad change without touching the others,
on a branch called revert/PLAT-063-<something> pushed to the remote, ready for a PR.
EOF
  brk_next t04
}
lab_t04_check() {
  check_begin t04; in_repo "$(brk_dir t04)"
  git fetch -q --prune origin
  local rb bad; rb=$(on_remote_branch '^origin/revert/PLAT-063-[a-z0-9-]+$'); bad=$(ks_get bad)
  checkn "A revert/PLAT-063-... branch is on the remote" "branch, revert, push" test -n "$rb"
  checkn "It reverts the bad commit" "find the commit with git log -S, then git revert it" sh -c "test -n '$rb' && git log '$rb' --format=%B | grep -q 'This reverts commit $bad'"
  checkn "Production is back to Standard_B2s on that branch" "the revert should restore the size" sh -c "test -n '$rb' && git show '$rb:terraform/environments/prod.tfvars' | grep -q Standard_B2s"
  checkn "The three later commits are untouched" "only the bad change should go" sh -c "test -n '$rb' && git merge-base --is-ancestor $(ks_get start) '$rb'"
  checkn "The remote's main hasn't been rewritten" "never reset or force push main" test "$(git rev-parse origin/main)" = "$(ks_get start)"
  check_end t04
}
lab_t04_hints() { printf '%s\n' "Don't trust commit messages. Search for the value: git log -S finds the commit that introduced it." "main is shared. You need a new commit that does the opposite, not a rewrite." "git switch -c revert/PLAT-063-vm-size, git revert <hash>, git push -u origin <branch>."; }
lab_t04_solution() { say ""; say "  git log -S Standard_D64s_v5 --oneline -- terraform/environments/prod.tfvars"; say "  git switch -c revert/PLAT-063-vm-size"; say "  git revert <hash>"; say "  git push -u origin revert/PLAT-063-vm-size"; say ""; say "  reset + force push would rewrite history everyone has pulled. Protection blocks it anyway."; say ""; }

# ---------- T05 A secret was committed (not pushed) ----------
lab_t05_start() {
  brk_base t05
  printf '{\n  "appId": "11111111-2222-3333-4444-555555555555",\n  "password": "ks-FAKE-sp-secret-0042",\n  "tenant": "novatech.example"\n}\n' > config/sp-credentials.json
  printf '# Runbook: service principal\n\nThe platform pipeline signs in with a service principal stored in Key Vault.\n' > docs/runbooks/service-principal.md
  git add -A; kc_me "2026-09-14T10:00:00" "PLAT-064: Add service principal runbook"
  ticket T05.md <<'EOF'
# T05  "Wait... what did I just commit?"

Your last commit (not pushed yet) includes config/sp-credentials.json. It holds a real-looking secret.
The runbook in the same commit is fine.

Get the runbook onto the remote's main, with the credentials file in NO commit at all,
and make sure nobody can commit that file by accident again.
EOF
  brk_next t05
}
lab_t05_check() {
  check_begin t05; in_repo "$(brk_dir t05)"
  git fetch -q origin
  checkn "The credentials file is in no commit on any branch" "remove it from the commit before you push. Restart: ks-lab break 5" never_committed config/sp-credentials.json
  checkn "The credentials file is ignored" "add it to .gitignore and commit that" sh -c "git ls-files --error-unmatch .gitignore && git check-ignore -q --no-index config/sp-credentials.json"
  checkn "The runbook is on the remote's main" "push" sh -c "git cat-file -e origin/main:docs/runbooks/service-principal.md"
  checkn "Local main matches the remote" "push" test "$(git rev-parse main)" = "$(git rev-parse origin/main)"
  check_end t05
}
lab_t05_hints() { printf '%s\n' "The commit isn't pushed, so you're allowed to change it." "Stop tracking the file without deleting it, then replace the last commit." "git rm --cached config/sp-credentials.json, add it to .gitignore, git add .gitignore, git commit --amend, then push."; }
lab_t05_solution() {
cat <<'EOF'

  git rm --cached config/sp-credentials.json
  echo "config/sp-credentials.json" >> .gitignore
  git add .gitignore
  git commit --amend --no-edit
  git push

  If it HAD been pushed: treat the secret as compromised. Rotate it first. Then remove the
  file in a new commit. Rewriting history comes last, and only with the repo admin, because
  copies already exist in every clone and fork.

EOF
}

# ---------- T06 Conflict markers made it into main ----------
lab_t06_start() {
  brk_base t06
  local base; base=$(git rev-parse HEAD)
  git switch -q -c feature/PLAT-058-kind
  sed_replace terraform/modules/storage-account/main.tf '  account_replication_type = "LRS"' '  account_replication_type = "LRS"
  account_kind             = "StorageV2"'
  git add -A; kc "$SAM_N" "$SAM_E" "2026-09-02T09:00:00" "PLAT-058: Set storage account kind"
  git switch -q main
  git switch -q -c feature/PLAT-059-tls "$base"
  sed_replace terraform/modules/storage-account/main.tf '  account_replication_type = "LRS"' '  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"'
  git add -A; kc "$LEA_N" "$LEA_E" "2026-09-02T10:00:00" "PLAT-059: Enforce TLS 1.2 on storage"
  git switch -q main; git merge -q feature/PLAT-058-kind
  git merge -q feature/PLAT-059-tls >/dev/null 2>&1
  git add -A; GIT_EDITOR=true kc "$DAN_N" "$DAN_E" "2026-09-02T16:00:00" "Merge branch 'feature/PLAT-059-tls'"
  git branch -qD feature/PLAT-058-kind feature/PLAT-059-tls
  sed_replace README.md 'Last reviewed: 2026-09-01' 'Last reviewed: 2026-09-05'; git add -A; kc "$SAM_N" "$SAM_E" "2026-09-05T11:00:00" "Update README review date"
  git push -q origin main 2>/dev/null
  protect_main_hook "$KS_REMOTES/break-t06.git"
  ks_put start "$(git rev-parse HEAD)"
  ticket T06.md <<'EOF'
# T06  Pipeline failing: terraform validate

The pipeline has failed on every run since last week:

  Error: Argument or block definition required
    on modules/storage-account/main.tf line 6:
     6: <<<<<<< HEAD

Fix it forward on a branch called fix/PLAT-066-<something>, pushed to the remote, ready for a PR.
Both changes in that merge were wanted: the storage account kind AND the TLS minimum.
EOF
  brk_next t06
}
lab_t06_check() {
  check_begin t06; in_repo "$(brk_dir t06)"
  git fetch -q --prune origin
  local rb f; rb=$(on_remote_branch '^origin/fix/PLAT-066-[a-z0-9-]+$'); f=terraform/modules/storage-account/main.tf
  checkn "A fix/PLAT-066-... branch is on the remote" "branch, fix, push" test -n "$rb"
  checkn "No conflict markers in the module on that branch" "remove the <<<<<<< ======= >>>>>>> lines" sh -c "test -n '$rb' && ! git show '$rb:$f' | grep -qE '^(<<<<<<<|=======|>>>>>>>)'"
  checkn "Both wanted settings are kept" "keep account_kind AND min_tls_version" sh -c "test -n '$rb' && git show '$rb:$f' | grep -q account_kind && git show '$rb:$f' | grep -q min_tls_version"
  checkn "Built on top of main (fix forward)" "branch from the current main" sh -c "test -n '$rb' && git merge-base --is-ancestor $(ks_get start) '$rb'"
  check_end t06
}
lab_t06_hints() { printf '%s\n' "Search the whole repo for the marker lines: git grep finds them." "git log -S '<<<<<<<' shows which commit brought them in, and what both sides meant." "Branch, edit the file to keep both lines, commit, push. A revert would throw away half of a wanted merge."; }
lab_t06_solution() { say ""; say "  git grep -n '<<<<<<<'"; say "  git log -S '<<<<<<<' --oneline -- terraform/"; say "  git switch -c fix/PLAT-066-storage-markers"; say "  # edit: keep both account_kind and min_tls_version, delete the marker lines"; say "  git commit -am \"PLAT-066: Remove conflict markers from storage module\""; say "  git push -u origin fix/PLAT-066-storage-markers"; say ""; }

# ---------- T07 .gitignore "isn't working" ----------
lab_t07_start() {
  brk_base t07
  printf '{\n  "version": 4,\n  "serial": 3\n}\n' > terraform/terraform.tfstate
  git add -A; kc "$DAN_N" "$DAN_E" "2026-09-03T09:00:00" "Add Terraform state"
  printf '*.tfstate\n*.tfstate.*\n.terraform/\n' > .gitignore
  git add -A; kc "$LEA_N" "$LEA_E" "2026-09-04T09:00:00" "Ignore Terraform state"
  sed_replace terraform/terraform.tfstate '"serial": 3' '"serial": 4'
  ticket T07.md <<'EOF'
# T07  ".gitignore isn't working"

*.tfstate is in .gitignore, yet git status shows terraform/terraform.tfstate as modified after
every plan. Make Git stop tracking it for good. The file must stay on disk: Terraform needs it.
EOF
  brk_next t07
}
lab_t07_check() {
  check_begin t07; in_repo "$(brk_dir t07)"
  checkn "The state file is no longer tracked" ".gitignore only affects untracked files" sh -c "! git ls-files --error-unmatch terraform/terraform.tfstate"
  checkn "The state file is still on disk" "don't delete it" test -f terraform/terraform.tfstate
  checkn "The change is committed" "commit the removal" sh -c "! git cat-file -e HEAD:terraform/terraform.tfstate"
  checkn "Working tree is clean" "git status" clean_tree
  check_end t07
}
lab_t07_hints() { printf '%s\n' ".gitignore only affects files Git isn't tracking yet. This one is tracked." "Tell Git to stop tracking it but leave it on disk." "git rm --cached terraform/terraform.tfstate, then commit."; }
lab_t07_solution() { say ""; say "  git rm --cached terraform/terraform.tfstate"; say "  git commit -m \"Stop tracking Terraform state\""; say ""; }

# ---------- T08 "I reset and lost my commits" ----------
lab_t08_start() {
  brk_base t08
  git switch -q -c feature/PLAT-067-alerts
  local i; for i in 1 2 3; do
    printf 'alert rule %s\n' "$i" >> docs/alerts.md; git add -A; kc_me "2026-09-15T1${i}:00:00" "PLAT-067: Add alert rule $i"
  done
  ks_put tip "$(git rev-parse HEAD)"
  git reset -q --hard HEAD~3
  ticket T08.md <<'EOF'
# T08  "I ran git reset --hard and my work is gone"

An hour ago you ran git reset --hard HEAD~3 on feature/PLAT-067-alerts by mistake.
Three commits of work have vanished from git log. Get them back on the branch.
EOF
  brk_next t08
}
lab_t08_check() {
  check_begin t08; in_repo "$(brk_dir t08)"
  checkn "Your three commits are back on feature/PLAT-067-alerts" "Git keeps a record of where HEAD has been" is_ancestor "$(ks_get tip)" feature/PLAT-067-alerts
  checkn "Working tree is clean" "git status" clean_tree
  check_end t08
}
lab_t08_hints() { printf '%s\n' "Commits aren't deleted straight away. Git records every place HEAD has pointed." "git reflog lists them, newest first." "Find the entry just before the reset, then git reset --hard <that-hash>."; }
lab_t08_solution() { say ""; say "  git reflog                       # find the line before 'reset: moving to HEAD~3'"; say "  git reset --hard HEAD@{1}        # or the hash from reflog"; say ""; }

# ---------- T09 Detached HEAD with new commits ----------
lab_t09_start() {
  brk_base t09
  git tag -a v1.0.0 -m "Release 1.0.0" >/dev/null
  sed_replace README.md 'Last reviewed: 2026-09-01' 'Last reviewed: 2026-09-10'; git add -A; kc "$SAM_N" "$SAM_E" "2026-09-10T09:00:00" "Update README review date"
  git -c advice.detachedHead=false switch -q --detach v1.0.0
  sed_replace terraform/modules/storage-account/main.tf '  account_tier             = "Standard"' '  account_tier             = "Standard"
  https_traffic_only_enabled = true'
  git add -A; kc_me "2026-09-16T10:00:00" "PLAT-068: Require HTTPS on storage accounts"
  printf '\nStorage accounts accept HTTPS only.\n' >> docs/architecture.md
  git add -A; kc_me "2026-09-16T10:10:00" "PLAT-068: Document HTTPS-only storage"
  ks_put tip "$(git rev-parse HEAD)"
  ticket T09.md <<'EOF'
# T09  "HEAD detached from v1.0.0"

You checked out the v1.0.0 tag to investigate a bug and made two fix commits there.
git status says: HEAD detached from v1.0.0. Your commits aren't on any branch.
Get them onto a branch called fix/PLAT-068-<something> before they're lost.
EOF
  brk_next t09
}
lab_t09_check() {
  check_begin t09; in_repo "$(brk_dir t09)"
  local b; b=$(find_branch '^fix/PLAT-068-[a-z0-9-]+$')
  checkn "A fix/PLAT-068-... branch holds both commits" "create a branch right where you are" sh -c "test -n '$b' && git merge-base --is-ancestor $(ks_get tip) '$b'"
  checkn "You're no longer detached" "switch to the branch" sh -c "git symbolic-ref -q HEAD"
  check_end t09
}
lab_t09_hints() { printf '%s\n' "Detached HEAD means you're on a commit, not on a branch. Your commits are only reachable from HEAD." "A branch created right now, here, makes them safe." "git switch -c fix/PLAT-068-https. Already left? git reflog shows the hash."; }
lab_t09_solution() { say ""; say "  git switch -c fix/PLAT-068-https-storage"; say ""; say "  Already switched away? git reflog, find your last commit, git branch fix/PLAT-068-https-storage <hash>"; say ""; }

# ---------- T10 PR has conflicts ----------
edit_t10_main() { add_readme_row 'scripts/cost-report.sh' 'Emails the weekly cost report'; }
lab_t10_start() {
  brk_base t10
  git switch -q -c feature/PLAT-069-disk-report
  add_readme_row 'scripts/disk-report.sh' 'Summarises disk usage across VMs'
  printf '#!/usr/bin/env bash\ndf -h\n' > scripts/disk-report.sh
  git add -A; kc_me "2026-09-17T09:00:00" "PLAT-069: Add disk usage report script"
  git push -q -u origin feature/PLAT-069-disk-report 2>/dev/null
  local tmp; tmp=$(mktemp -d 2>/dev/null || mktemp -d -t kslab)
  git clone -q "$(git remote get-url origin)" "$tmp/s" && (cd "$tmp/s" && edit_t10_main && printf '#!/usr/bin/env bash\necho cost\n' > scripts/cost-report.sh && git add -A && kc "$SAM_N" "$SAM_E" "2026-09-18T09:00:00" "PLAT-070: Add weekly cost report script" && git push -q origin main 2>/dev/null)
  rm -rf "$tmp"
  protect_main_hook "$KS_REMOTES/break-t10.git"
  git fetch -q origin
  ks_put main "$(git rev-parse origin/main)"
  ticket T10.md <<'EOF'
# T10  "This branch has conflicts that must be resolved"

Your PR for feature/PLAT-069-disk-report has been open a week. main has moved, and GitHub now says
the branch has conflicts. Make the PR mergeable: same branch, conflict resolved, pushed.
Both scripts belong in the README table.
EOF
  brk_next t10
}
lab_t10_check() {
  check_begin t10; in_repo "$(brk_dir t10)"
  git fetch -q origin
  local rb=origin/feature/PLAT-069-disk-report
  checkn "Your branch on the remote includes the latest main" "bring main into your branch" is_ancestor "$(ks_get main)" "$rb"
  checkn "No conflict markers in README.md" "finish resolving" sh -c "! git show $rb:README.md | grep -qE '^(<<<<<<<|=======|>>>>>>>)'"
  checkn "Both scripts are in the README table" "keep both rows" sh -c "git show $rb:README.md | grep -q disk-report.sh && git show $rb:README.md | grep -q cost-report.sh"
  checkn "Local branch matches the remote" "push" test "$(git rev-parse feature/PLAT-069-disk-report)" = "$(git rev-parse "$rb")"
  check_end t10
}
lab_t10_hints() { printf '%s\n' "At work you resolve conflicts on your branch, not on main." "Fetch, then merge origin/main into your feature branch." "Resolve README.md keeping both rows, git add, git commit, git push. The PR updates itself."; }
lab_t10_solution() { say ""; say "  git switch feature/PLAT-069-disk-report"; say "  git fetch"; say "  git merge origin/main             # CONFLICT in README.md"; say "  # keep both rows"; say "  git add README.md && git commit"; say "  git push"; say ""; }

# ---------- T11 Repository not found ----------
lab_t11_start() {
  brk_base t11
  git remote set-url origin "$KS_REMOTES/break-t11-cloud-enginering-lab.git"
  printf '6. Close the alert in the monitoring console.\n' >> docs/runbooks/disk-space.md
  git add -A; kc_me "2026-09-19T09:00:00" "PLAT-071: Add alert closing step to runbook"
  ticket T11.md <<EOF
# T11  "fatal: ... does not appear to be a git repository"

git push fails on a repo that "worked last week". The team repo is at:

  $KS_REMOTES/break-t11.git

(On GitHub this shows up as "remote: Repository not found." Same cause, same fix.)
Get your commit pushed to the team repo.
EOF
  brk_next t11
}
lab_t11_check() {
  check_begin t11; in_repo "$(brk_dir t11)"
  checkn "origin points at the team repo" "check git remote -v against the ticket" test "$(git remote get-url origin)" = "$KS_REMOTES/break-t11.git"
  git fetch -q origin 2>/dev/null
  checkn "Your commit is on the team repo's main" "push" sh -c "git log origin/main --format=%s | grep -q 'alert closing step'"
  check_end t11
}
lab_t11_hints() { printf '%s\n' "Read the error: which URL is Git trying to reach?" "git remote -v shows where origin points. Compare it, letter by letter, with the ticket." "git remote set-url origin <correct-url>, then git push."; }
lab_t11_solution() {
cat <<'EOF'

  git remote -v                       # "enginering": a typo
  git remote set-url origin ~/kloudskool-labs/.remotes/break-t11.git
  git push

  On GitHub, "Repository not found" also appears when you're signed in as a different
  account, or the repo is private and you lack access. And "Authentication failed" with
  a password prompt means: use a personal access token or an SSH key, not your password.

EOF
}

# ---------- T12 Pushing to a repo you don't own ----------
lab_t12_start() {
  local d up fork
  d=$(brk_dir t12); new_repo "$d"
  mkdir -p runbooks; printf '# Runbook template\n\n## Symptoms\n\n## Fix\n' > runbooks/TEMPLATE.md
  git add -A; kc "$SAM_N" "$SAM_E" "2026-08-01T09:00:00" "Add runbook template"
  up=$(new_bare_remote break-t12-upstream); git push -q "$up" main 2>/dev/null
  fork=$(new_bare_remote break-t12-your-fork); git push -q "$fork" main 2>/dev/null
  deny_all_hook "$up"
  git remote add origin "$up"; git fetch -q origin; git branch -q -u origin/main
  git switch -q -c runbook/disk-full
  printf '# Runbook: disk full\n\n## Symptoms\n\nAlerts from check-disk.sh.\n\n## Fix\n\nFollow the disk space runbook.\n' > runbooks/disk-full.md
  git add -A; kc_me "2026-09-20T09:00:00" "Add runbook: disk full"
  ticket T12.md <<EOF
# T12  "Permission denied (403)"

You cloned the community runbook repo directly, committed a runbook, and git push says:

  remote: Permission to kloudskool/cloud-runbooks.git denied to you.
  ... The requested URL returned error: 403

You've now forked it. Your fork is at:   $fork
The original (upstream) is at:          $up

Set the remotes up the standard way (origin = your fork, upstream = the original)
and push your branch to your fork, ready for a PR.
EOF
  brk_next t12
}
lab_t12_check() {
  check_begin t12; in_repo "$(brk_dir t12)"
  checkn "origin is your fork" "git remote set-url, or rename and add" test "$(git remote get-url origin 2>/dev/null)" = "$KS_REMOTES/break-t12-your-fork.git"
  checkn "upstream is the original repo" "git remote rename origin upstream is one way" test "$(git remote get-url upstream 2>/dev/null)" = "$KS_REMOTES/break-t12-upstream.git"
  checkn "Your runbook branch is on your fork" "git push -u origin runbook/disk-full" \
    sh -c "git --git-dir='$KS_REMOTES/break-t12-your-fork.git' log --all --format=%s | grep -q 'disk full'"
  check_end t12
}
lab_t12_hints() { printf '%s\n' "403 means you're not allowed to push there. You push to your fork, then open a PR from it." "Your clone's origin is the original repo. It should be your fork, and the original should be called upstream." "git remote rename origin upstream, git remote add origin <fork>, git push -u origin runbook/disk-full."; }
lab_t12_solution() { say ""; say "  git remote rename origin upstream"; say "  git remote add origin ~/kloudskool-labs/.remotes/break-t12-your-fork.git"; say "  git push -u origin runbook/disk-full"; say ""; }

# ---------- B1 Squash a messy history ----------
lab_b1_start() {
  local d="$KS_LABS/bonus-squash"; new_repo "$d"
  write_readme; git add -A; kc "$SAM_N" "$SAM_E" "2026-08-01T09:00:00" "Add README"
  git switch -q -c feature/PLAT-072-dashboards
  local i m; i=0
  for m in "wip" "wip 2" "fix" "more" "oops typo" "done"; do
    i=$((i + 1)); printf 'Dashboard section %s\n' "$i" >> dashboards.md
    git add -A; kc_me "2026-09-21T1${i}:00:00" "$m"
  done
  ks_put tree "$(git rev-parse HEAD^{tree})"; ks_put main "$(git rev-parse main)"
  ticket B1.md <<'EOF'
# B1  Tidy before the PR

feature/PLAT-072-dashboards has six commits called wip, wip 2, fix, more, oops typo, done.
Before you open the PR, make it ONE commit: "PLAT-072: Document platform dashboards".
The content must stay exactly the same. It has never been pushed.
EOF
  next_steps "$d"
}
lab_b1_check() {
  check_begin b1; in_repo "$KS_LABS/bonus-squash"
  local b=feature/PLAT-072-dashboards
  checkn "One commit on the branch" "squash the six into one" test "$(git rev-list --count "main..$b")" = "1"
  checkn "It sits on main" "parent should be main" test "$(git rev-parse "$b~1")" = "$(ks_get main)"
  checkn "Content is unchanged" "nothing lost or added" test "$(git rev-parse "$b^{tree}")" = "$(ks_get tree)"
  checkn "Message is 'PLAT-072: Document platform dashboards'" "reword the commit" test "$(git log -1 --format=%s "$b")" = "PLAT-072: Document platform dashboards"
  check_end b1
}
lab_b1_hints() { printf '%s\n' "Interactive rebase lets you edit a list of commits before they're replayed." "git rebase -i main. Keep the first as pick, change the others to squash (or fixup)." "Or the quick way: git reset --soft main, then one git commit."; }
lab_b1_solution() { say ""; say "  git rebase -i main      # pick the first, 's' the other five, then write the message"; say "  # or: git reset --soft main && git commit -m \"PLAT-072: Document platform dashboards\""; say ""; }

# ---------- B2 Hotfix on the wrong branch (cherry-pick) ----------
lab_b2_start() {
  local d="$KS_LABS/bonus-cherry-pick"; new_repo "$d"
  write_terraform; printf '2.1.0\n' > VERSION
  git add -A; kc "$SAM_N" "$SAM_E" "2026-08-01T09:00:00" "Add Terraform"
  git switch -q -c release/2.1
  printf '2.1.1\n' > VERSION; git add -A; kc "$SAM_N" "$SAM_E" "2026-09-01T09:00:00" "Bump version to 2.1.1"
  edit_l14_tls; git add -A; kc "$LEA_N" "$LEA_E" "2026-09-01T10:00:00" "PLAT-073: Enforce TLS 1.2 on storage accounts"
  ks_put fix "$(git rev-parse HEAD)"; ks_put rel "$(git rev-parse HEAD)"
  git switch -q main
  ticket B2.md <<'EOF'
# B2  The fix landed on the release branch only

Lea committed PLAT-073 (TLS 1.2) to release/2.1. main needs that fix too, but NOT the version bump
that's also on release/2.1. Get just the fix onto main. Don't change release/2.1.
EOF
  next_steps "$d"
}
lab_b2_check() {
  check_begin b2; in_repo "$KS_LABS/bonus-cherry-pick"
  checkn "main has the TLS fix" "copy just that one commit" blob_has main terraform/modules/storage-account/main.tf 'TLS1_2'
  checkn "main does NOT have the version bump" "only the fix, not the whole branch" blob_has main VERSION '^2\.1\.0$'
  checkn "release/2.1 is unchanged" "don't modify the release branch" test "$(git rev-parse release/2.1)" = "$(ks_get rel)"
  check_end b2
}
lab_b2_hints() { printf '%s\n' "Merging release/2.1 would bring the version bump too." "You want to copy one commit onto main." "git log release/2.1 to find the hash, then on main: git cherry-pick <hash>."; }
lab_b2_solution() { say ""; say "  git log --oneline release/2.1"; say "  git switch main"; say "  git cherry-pick <PLAT-073 hash>"; say ""; }

# shellcheck shell=bash
# Local labs: 00, 00b, p1, 01-07, p3, c1. No GitHub needed.

ks_get() { git config --get "ks.$1" 2>/dev/null; }
ks_put() { git config "ks.$1" "$2"; }

# =====================================================================
# L00 — Workstation ready
# =====================================================================
lab_00_start() {
  say ""
  say "  Nothing to set up for this lab: it checks your own Git settings."
  say "  Configure Git as the lab page asks, then run:  ks-lab check 00"
  say ""
}
git_ver_ok() {
  local v maj min
  v=$(git --version | sed -E 's/[^0-9]*([0-9]+)\.([0-9]+).*/\1 \2/')
  maj=${v% *}; min=${v#* }
  [ "$maj" -gt 2 ] || { [ "$maj" -eq 2 ] && [ "$min" -ge 23 ]; }
}
gcfg() { git config --global --get "$1" 2>/dev/null; }
lab_00_check() {
  check_begin 00
  checkn "Git is version 2.23 or newer" "update Git: brew upgrade git (macOS) or reinstall Git for Windows" git_ver_ok
  checkn "Your name is set" "git config --global user.name \"Your Name\"" test -n "$(gcfg user.name)"
  checkn "Your email is set (use the one on your GitHub account)" "git config --global user.email you@example.com" \
    sh -c "git config --global --get user.email | grep -q '@'"
  checkn "New repositories start on a branch called main" "look up the init.defaultBranch setting" \
    test "$(gcfg init.defaultBranch)" = "main"
  checkn "git pull merges by default (pull.rebase false)" "look up the pull.rebase setting" \
    test "$(gcfg pull.rebase)" = "false"
  checkn "An editor is set for commit and merge messages" "VS Code: git config --global core.editor \"code --wait\"   or nano: \"nano\"" \
    test -n "$(gcfg core.editor)"
  check_end 00
}
lab_00_hints() {
cat <<'EOF'
Every setting here is a global Git setting. Global settings apply to every repository on your machine.
The command shape is: git config --global <setting-name> <value>. Settings with spaces in the value need quotes.
The names are user.name, user.email, init.defaultBranch, pull.rebase and core.editor. git config --global --list shows what you have.
EOF
}
lab_00_solution() {
cat <<'EOF'

  git config --global user.name "Your Name"
  git config --global user.email you@example.com      # same email as your GitHub account
  git config --global init.defaultBranch main
  git config --global pull.rebase false
  git config --global core.editor "code --wait"        # or "nano"
  git config --global --list                            # check them

  Why the email matters: GitHub links commits to your profile by email. A different
  email means your commits show up as someone else's, or as nobody's.

EOF
}

# ---------- 00b: GitHub account ----------
lab_00b_start() {
  say ""
  say "  Create your GitHub account (lesson 320), turn on two-factor authentication,"
  say "  then run:  ks-lab check 00b"
  say ""
}
lab_00b_check() {
  local u="${KS_GH_USER:-}"
  if [ -z "$u" ]; then
    printf '\n  Your GitHub username: '; read -r u
  fi
  u=$(printf '%s' "$u" | tr -d ' @')
  check_begin 00b
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' "https://api.github.com/users/$u" 2>/dev/null)
  if [ "$code" = "403" ] || [ "$code" = "000" ]; then
    say "  (Couldn't reach GitHub to confirm. Saving your username anyway.)"; code=200
  fi
  checkn "GitHub account '$u' exists" "check the spelling: it's the name in your profile URL github.com/<name>" test "$code" = "200"
  [ "$code" = "200" ] && state_set github_user "$u"
  check_end 00b
}
lab_00b_hints() {
cat <<'EOF'
Your username is the part after github.com/ when you open your profile.
It's not your email address.
EOF
}
lab_00b_solution() { say ""; say "  Open github.com, click your avatar (top right): the bold name under it is your username."; say ""; }

# =====================================================================
# P1 — Version chaos (pre-lab)
# =====================================================================
lab_p1_start() {
  local d="$KS_LABS/p1-version-chaos"
  rm -rf "$d"; mkdir -p "$d"; cd "$d" || exit 1
  local base='resource "azurerm_linux_virtual_machine" "app" {
  name     = "vm-app-prod"
  location = "uksouth"
  size     = "SIZE"
}'
  printf '%s\n' "$base" | sed 's/SIZE/Standard_B2s/'    > main.tf
  printf '%s\n' "$base" | sed 's/SIZE/Standard_B4ms/'   > main_final.tf
  printf '%s\n' "$base" | sed 's/SIZE/Standard_D4s_v5/' > main_final_v2.tf
  printf '%s\n' "$base" | sed 's/SIZE/Standard_D4s_v5/; s/uksouth/ukwest/' > main_FINAL_real.tf
  printf '%s\n' "$base" | sed 's/SIZE/Standard_D8s_v5/' > "main_final_v2 (Sam's edits).tf"
  cat > deployed-friday.txt <<'EOF'
deployed the final one on friday i think. ask dan. -- L
EOF
  next_steps "$d"
}
lab_p1_check() {
  check_begin p1
  checkn "You wrote your answer in ANSWER.txt" "create ANSWER.txt in the p1-version-chaos folder" \
    test -s "$KS_LABS/p1-version-chaos/ANSWER.txt"
  check_end p1
}
lab_p1_hints() {
cat <<'EOF'
Open each file and compare. What differs between them?
Is there anything here that proves which file was deployed, when, and by whom?
EOF
}
lab_p1_solution() {
cat <<'EOF'

  There is no way to know. Nothing records which file was deployed, who changed what,
  or why. That's the problem version control solves: one file, a full history of every
  change, who made it, when, and the reason they gave.

EOF
}

# =====================================================================
# L01 — Put the platform scripts under version control
# =====================================================================
lab_01_start() {
  backup_dir "$KS_REPO"
  mkdir -p "$KS_REPO"; cd "$KS_REPO" || exit 1
  write_all
  cat > scratch-notes.txt <<'EOF'
my notes - not for the repo
- ask Sam about the prod VM sizes
- renew parking permit
- the backup share password is on the sticky note (TODO: move to Key Vault)
EOF
  next_steps "$KS_REPO"
}
commits_mixing_areas() {   # prints count of commits touching both scripts/ and terraform/
  local c n=0 f
  for c in $(git rev-list HEAD); do
    f=$(git show --name-only --format= "$c")
    if printf '%s\n' "$f" | grep -q '^scripts/' && printf '%s\n' "$f" | grep -q '^terraform/'; then n=$((n + 1)); fi
  done
  printf '%s' "$n"
}
only_scratch_untracked() { [ "$(ks_porcelain)" = "?? scratch-notes.txt" ]; }
authors_match() {
  local want; want=$(git config user.email)
  [ -z "$(git log --format=%ae | grep -vxF "$want")" ]
}
lab_01_check() {
  check_begin 01
  in_repo "$KS_REPO"
  if ! is_repo; then
    checkn "The folder is a Git repository" "Git doesn't know about this folder yet" false
    check_end 01; return
  fi
  check "The folder is a Git repository" true
  checkn "You're on a branch called main" "run lab 00 first so new repos start on main" on_branch main
  local n; n=$(git rev-list --count HEAD 2>/dev/null || echo 0)
  checkn "At least three commits ($n so far)" "one commit per area: scripts, Terraform, docs and standards" count_ge "$n" 3
  checkn "No commit mixes scripts and Terraform" "stage one area at a time" count_eq "$(commits_mixing_areas)" 0
  checkn "scratch-notes.txt was never committed" "it's your colleague's private notes. Start again with ks-lab start 01" never_committed scratch-notes.txt
  checkn "Everything else is committed (only the scratch notes are untracked)" "git status shows what's left" only_scratch_untracked
  checkn "Commit messages are descriptive (4+ words, no 'update' or 'wip')" "a teammate should understand each one from git log --oneline" good_msg HEAD
  checkn "Commits are under your identity" "your email in the commits should match git config user.email" authors_match
  check_end 01
}
lab_01_hints() {
cat <<'EOF'
git status tells you what Git can see, and what it's already tracking.
git add takes a folder name as well as a file name, so you can stage one area at a time.
Stage scripts/, commit. Stage terraform/, commit. Then stage the rest by name, leaving scratch-notes.txt out, and commit.
EOF
}
lab_01_solution() {
cat <<'EOF'

  cd ~/kloudskool-labs/cloud-engineering-lab
  git init
  git status
  git add scripts/
  git commit -m "Add operational scripts for disk, backup and health checks"
  git add terraform/
  git commit -m "Add Terraform for core resource group and storage"
  git add README.md CONTRIBUTING.md docs/ config/ .github/
  git commit -m "Add README, docs and repository standards"
  git status            # only scratch-notes.txt left, untracked
  git log --oneline

  Made a mistake (committed the notes)? ks-lab start 01 gives you a fresh folder.

EOF
}

# =====================================================================
# L02 — Review before you commit
# =====================================================================
lab_02_start() {
  build_stage_A
  ks_put start "$(git rev-parse HEAD)"
  sed_replace scripts/check-disk.sh 'THRESHOLD=80' 'THRESHOLD=90'
  sed_replace scripts/backup-logs.sh 'set -euo pipefail' 'set -euo pipefail
echo "DEBUG here"'
  sed_replace terraform/variables.tf 'default = "uksouth"' 'default = "uksouthh"'
  ticket PLAT-008.md <<'EOF'
# PLAT-008  Raise the disk usage alert threshold

The disk alert in scripts/check-disk.sh fires too often. Raise the threshold from 80% to 90%.
Nothing else should change in this ticket.
EOF
  next_steps "$KS_REPO"
}
lab_02_check() {
  check_begin 02
  in_repo "$KS_REPO"
  local s; s=$(ks_get start)
  checkn "Exactly one new commit" "commit only the ticket's change, once" test "$(git rev-parse HEAD~1 2>/dev/null)" = "$s"
  checkn "That commit changes only scripts/check-disk.sh" "something else was staged with it" \
    test "$(git diff --name-only HEAD~1 HEAD 2>/dev/null)" = "scripts/check-disk.sh"
  checkn "The threshold in the commit is 90" "the commit should hold the 80 -> 90 change" blob_has HEAD scripts/check-disk.sh '^THRESHOLD=90$'
  checkn "Commit message starts with the ticket id (PLAT-008:)" "see CONTRIBUTING.md" \
    sh -c "git log -1 --format=%s | grep -q '^PLAT-008: '"
  checkn "The debug line is gone from backup-logs.sh" "that change isn't wanted: throw it away" file_lacks scripts/backup-logs.sh 'DEBUG'
  checkn "terraform/variables.tf is back to uksouth" "that change isn't wanted either" file_lacks terraform/variables.tf 'uksouthh'
  checkn "Working tree is clean" "git status should say nothing to commit" clean_tree
  check_end 02
}
lab_02_hints() {
cat <<'EOF'
There are two diffs: what you haven't staged yet, and what you have.
git diff shows unstaged changes. git diff --staged shows what will go into the next commit.
git restore <file> throws away unstaged changes in that file. Check it's the right file first.
EOF
}
lab_02_solution() {
cat <<'EOF'

  git status
  git diff                                   # all three changes
  git add scripts/check-disk.sh
  git diff --staged                          # exactly one change staged
  git restore scripts/backup-logs.sh terraform/variables.tf
  git commit -m "PLAT-008: Raise disk usage alert threshold to 90%"
  git status

  Committed too much already? git reset --soft HEAD~1 undoes the commit and keeps
  the changes staged. Or start again: ks-lab start 02

EOF
}

# =====================================================================
# L03 — Who changed the VM size?  (deterministic team history)
# =====================================================================
L03_DIR="$KS_LABS/platform-history"
lab_03_start() {
  new_repo "$L03_DIR"
  # 1-3
  write_scripts
  printf '# platform-scripts\n\nScripts for the platform team.\n' > README.md
  kc_det "$SAM_N" "$SAM_E" "2026-06-02T09:12:00" "Add initial platform scripts"
  write_terraform; rm -rf terraform/modules
  awk '/^variable "default_tags"/{exit} {print}' terraform/variables.tf > v.tmp && cat v.tmp > terraform/variables.tf && rm v.tmp
  sed_replace terraform/main.tf '    azurerm = {' '    azurerm = {'
  kc_det "$SAM_N" "$SAM_E" "2026-06-03T10:40:00" "Add Terraform for core resource group"
  write_terraform; awk '/^variable "default_tags"/{exit} {print}' terraform/variables.tf > v.tmp && cat v.tmp > terraform/variables.tf && rm v.tmp
  kc_det "$DAN_N" "$DAN_E" "2026-06-05T14:03:00" "Add storage account module"
  # 4-8
  mkdir -p docs/runbooks
  cat > docs/runbooks/disk-space.md <<'EOF'
# Runbook: disk space alert

1. Confirm the alert with `df -h /`.
2. Find large files: `du -xh / --max-depth=2 | sort -h | tail`.
3. Old log archives can be removed from `/mnt/backup/logs` after 14 days.
EOF
  kc_det "$PRIYA_N" "$PRIYA_E" "2026-06-09T11:20:00" "Add disk space runbook"
  write_contributing
  kc_det "$SAM_N" "$SAM_E" "2026-06-12T16:45:00" "Add contributing guide"
  mkdir -p config
  printf '{\n  "service": "novatech-platform",\n  "logLevel": "info",\n  "healthCheckIntervalSeconds": 60\n}\n' > config/app-settings.json
  kc_det "$LEA_N" "$LEA_E" "2026-06-16T09:30:00" "Add app settings for platform service"
  printf '# Platform architecture\n\nOne resource group per environment holds the shared platfrom services.\n' > docs/architecture.md
  kc_det "$DAN_N" "$DAN_E" "2026-06-19T13:15:00" "Document platform architecture"
  printf '# NovaTech Platform Tooling\n\nScripts and Terraform for the platform team.\n' > README.md
  kc_det "$PRIYA_N" "$PRIYA_E" "2026-06-24T10:05:00" "Rename repository title"
  # 9-14
  printf '# Runbook: restore from backup\n\n1. Find the archive in `/mnt/backup/logs`.\n2. Extract with `tar -xzf`.\n' > docs/runbooks/backup-restore.md
  kc_det "$LEA_N" "$LEA_E" "2026-06-30T15:50:00" "Add backup restore runbook"
  sed_replace scripts/backup-logs.sh 'RETENTION_DAYS=14' 'RETENTION_DAYS=21'
  kc_det "$SAM_N" "$SAM_E" "2026-07-03T09:00:00" "Raise backup retention to 21 days"
  cat >> terraform/variables.tf <<'EOF'

variable "default_tags" {
  type = map(string)
  default = {
    environment = "dev"
    owner       = "cloud-team"
  }
}
EOF
  kc_det "$DAN_N" "$DAN_E" "2026-07-08T11:11:00" "Add dev environment tags"
  sed_replace scripts/health-check.sh 'TIMEOUT=10' 'TIMEOUT=15'
  kc_det "$PRIYA_N" "$PRIYA_E" "2026-07-14T14:22:00" "Increase health check timeout to 15 seconds"
  printf '# Runbook: certificate renewal\n\n1. Check expiry with `openssl s_client`.\n2. Renew in Key Vault.\n' > docs/runbooks/cert-renewal.md
  kc_det "$LEA_N" "$LEA_E" "2026-07-17T10:35:00" "Add certificate renewal runbook"
  sed_replace terraform/main.tf 'version = "~> 4.0"' 'version = "~> 4.10"'
  kc_det "$SAM_N" "$SAM_E" "2026-07-21T09:48:00" "Pin azurerm provider to 4.x"
  # 15 — the culprit
  sed_replace terraform/environments/prod.tfvars 'vm_size     = "Standard_B2s"' 'vm_size     = "Standard_D8s_v5"'
  sed_replace config/app-settings.json '"logLevel": "info"' '"logLevel": "debug"'
  kc_det "$DAN_N" "$DAN_E" "2026-07-24T17:02:00" "Tidy formatting in prod tfvars"
  # 16-25
  sed_replace docs/architecture.md 'platfrom' 'platform'
  kc_det "$PRIYA_N" "$PRIYA_E" "2026-07-29T12:00:00" "Fix typo in architecture doc"
  sed_replace scripts/health-check.sh 'TIMEOUT=15' 'TIMEOUT=12'
  kc_det "$LEA_N" "$LEA_E" "2026-08-03T09:25:00" "Lower health check timeout to 12 seconds"
  sed_replace config/app-settings.json '"healthCheckIntervalSeconds": 60' '"healthCheckIntervalSeconds": 60,
  "region": "uksouth"'
  kc_det "$SAM_N" "$SAM_E" "2026-08-06T15:10:00" "Add region to app settings"
  printf '4. If usage is still above the threshold, escalate to the on-call engineer.\n' >> docs/runbooks/disk-space.md
  kc_det "$DAN_N" "$DAN_E" "2026-08-11T10:00:00" "Add escalation step to disk space runbook"
  printf '\noutput "location" {\n  value = azurerm_resource_group.platform.location\n}\n' >> terraform/outputs.tf
  kc_det "$PRIYA_N" "$PRIYA_E" "2026-08-14T16:30:00" "Add location output"
  sed_replace scripts/backup-logs.sh 'Backup complete' 'Backup finished'
  kc_det "$LEA_N" "$LEA_E" "2026-08-18T11:45:00" "Reword backup completion message"
  printf '# NovaTech Cloud Engineering Lab\n\nScripts and Terraform for the platform team.\n' > README.md
  kc_det "$SAM_N" "$SAM_E" "2026-08-20T09:05:00" "Rename repository to NovaTech Cloud Engineering Lab"
  printf 'environment = "dev"\nvm_size     = "Standard_B1s"\n' > terraform/environments/dev.tfvars
  kc_det "$DAN_N" "$DAN_E" "2026-08-24T14:40:00" "Use smaller VM size in dev"
  sed_replace scripts/check-disk.sh 'THRESHOLD=80' 'THRESHOLD=85'
  kc_det "$PRIYA_N" "$PRIYA_E" "2026-08-26T10:10:00" "Raise disk alert threshold to 85 percent"
  printf '\n## Environments\n\n- dev\n- prod\n' >> docs/architecture.md
  kc_det "$LEA_N" "$LEA_E" "2026-08-28T13:55:00" "Document environments"
  next_steps "$L03_DIR"
  say "  This repo is the team's full history. Answer the questions on the lab page"
  say "  using Git, then answer them in the lab's check-in quiz."
  say ""
}
lab_03_check() {
  check_begin 03
  in_repo "$L03_DIR"
  check "The team history repository is set up" test "$(git rev-list --count HEAD)" -ge 25
  say ""
  say "  This lab is checked by its quiz: the answers are only in the history."
  say "  Answer the five questions on the learning platform."
  say ""
}
lab_03_hints() {
cat <<'EOF'
git log can be limited to one file or folder: git log --oneline -- <path>
git log -p shows each commit's change. -S "text" finds commits that added or removed that text.
git show <hash>:<path> prints a file as it was at that commit. git blame <file> shows who last changed each line.
EOF
}
lab_03_solution() {
cat <<'EOF'

  cd ~/kloudskool-labs/platform-history
  git log --oneline -- terraform/environments/prod.tfvars
  git log -p -S "Standard_D8s_v5" -- terraform/environments/prod.tfvars   # Q1: hash + author
  git show <that-hash>                                                     # Q2: the other change
  git log --oneline -- docs/runbooks/ | wc -l                              # Q3
  git log --oneline -- README.md                                          # Q4: take the 2nd hash
  git show <second-hash>:README.md | head -1
  git blame scripts/health-check.sh | grep TIMEOUT                         # Q5

  The lesson: the commit message said "tidy formatting". The diff said otherwise.
  Always read the diff.

EOF
}

# =====================================================================
# L04 — Add a monitoring script on a feature branch
# =====================================================================
lab_04_start() {
  build_stage_B
  ks_put start "$(git rev-parse HEAD)"
  ticket PLAT-012.md <<'EOF'
# PLAT-012  Add a CPU usage check script

Add scripts/check-cpu.sh with the content below, make it executable, and add it
to the scripts table in README.md (purpose: "Alerts when CPU load passes the threshold").

Other engineers deploy from main. Don't change main.

----- scripts/check-cpu.sh -----
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
--------------------------------
EOF
  next_steps "$KS_REPO"
}
find_branch() { git for-each-ref --format='%(refname:short)' "refs/heads/" | grep -E "$1" | head -1; }
msgs_start_with() { [ -z "$(git log --format=%s "$1" | grep -v "^$2")" ] && [ -n "$(git log --format=%s "$1")" ]; }
lab_04_check() {
  check_begin 04
  in_repo "$KS_REPO"
  local s b; s=$(ks_get start); b=$(find_branch '^feature/PLAT-012-[a-z0-9-]+$')
  checkn "A branch named feature/PLAT-012-<description> exists" "lower case, hyphens, see CONTRIBUTING.md" test -n "$b"
  checkn "main hasn't moved" "work went onto main. Start again: ks-lab start 04" test "$(git rev-parse main)" = "$s"
  if [ -n "$b" ]; then
    local n; n=$(git rev-list --count "main..$b")
    checkn "Your branch has at least two commits ($n)" "one for the script, one for the README" count_ge "$n" 2
    checkn "check-cpu.sh is on the branch" "commit the script on your branch" blob_has "$b" scripts/check-cpu.sh 'THRESHOLD=85'
    checkn "check-cpu.sh is executable in Git (mode 100755)" "Windows: git add --chmod=+x scripts/check-cpu.sh, then commit" mode_is "$b" scripts/check-cpu.sh 100755
    checkn "README lists check-cpu.sh" "add a row to the scripts table" blob_has "$b" README.md 'check-cpu\.sh'
    checkn "Every commit message starts with PLAT-012:" "see CONTRIBUTING.md" msgs_start_with "main..$b" "PLAT-012: "
    checkn "Commit messages are descriptive" "4+ words, imperative" good_msg "main..$b"
  fi
  check_end 04
}
lab_04_hints() {
cat <<'EOF'
Which branch are you on right now? git status tells you. Create the branch before you change anything.
One command creates a branch and moves you onto it. The branch name is in CONTRIBUTING.md.
git switch -c feature/PLAT-012-cpu-check. Then git log --oneline main..HEAD lists commits on your branch that main doesn't have.
EOF
}
lab_04_solution() {
cat <<'EOF'

  git switch -c feature/PLAT-012-cpu-check
  # create scripts/check-cpu.sh from the ticket
  chmod +x scripts/check-cpu.sh
  git add scripts/check-cpu.sh
  git add --chmod=+x scripts/check-cpu.sh     # needed on Windows, harmless elsewhere
  git commit -m "PLAT-012: Add CPU usage check script"
  # edit README.md: add the row to the scripts table
  git commit -am "PLAT-012: Document CPU check in README"
  git log --oneline main..HEAD

  Committed on main by mistake? That's Break Room scenario 2. For now: ks-lab start 04.

EOF
}

# =====================================================================
# L05 — Merge it and clean up
# =====================================================================
lab_05_start() {
  build_stage_B
  local m; m=$(git rev-parse HEAD)
  git switch -q -c feature/PLAT-012-cpu-check
  write_cpu_script; git add -A; kc_me "2026-09-03T09:00:00" "PLAT-012: Add CPU usage check script"
  add_readme_row 'scripts/check-cpu.sh' 'Alerts when CPU load passes the threshold'
  git add -A; kc_me "2026-09-03T09:10:00" "PLAT-012: Document CPU check in README"
  ks_put t012 "$(git rev-parse HEAD)"
  git switch -q -c feature/PLAT-015-log-retention "$m"
  sed_replace scripts/backup-logs.sh 'RETENTION_DAYS=14' 'RETENTION_DAYS=30'
  git add -A; kc_me "2026-09-03T10:00:00" "PLAT-015: Keep log archives for 30 days"
  sed_replace docs/runbooks/disk-space.md 'after 14 days' 'after 30 days'
  git add -A; kc_me "2026-09-03T10:05:00" "PLAT-015: Update runbook for 30 day retention"
  ks_put t015 "$(git rev-parse HEAD)"
  git switch -q -c feature/PLAT-016-montoring "$m"
  printf '# Monitoring\n\nDraft: which alerts page the on-call engineer.\n' > docs/monitoring.md
  git add -A; kc_me "2026-09-03T11:00:00" "PLAT-016: Start monitoring overview draft"
  ks_put t016 "$(git rev-parse HEAD)"
  git switch -q -c spike/old-idea "$m"
  printf '#!/usr/bin/env bash\necho "experiment"\n' > scripts/experimental.sh
  git add -A; kc_me "2026-08-20T11:00:00" "Try an experimental cleanup script"
  git switch -q main
  ks_put mainstart "$m"
  ticket PLAT-016.md <<'EOF'
# PLAT-016  Monitoring overview   (IN PROGRESS — not ready to merge)

Note: the branch for this ticket was created with a typo in its name ("montoring").
EOF
  ticket spike-old-idea.md <<'EOF'
# spike/old-idea

Abandoned. The team decided against the experimental cleanup script. Nothing on that branch is needed.
EOF
  next_steps "$KS_REPO"
}
event_05b() {
  in_repo "$KS_REPO"
  local t012; t012=$(ks_get t012)
  [ -n "$t012" ] || die "run ks-lab start 05 first"
  on_branch main || die "switch to main first (the hotfix lands on main)"
  clean_tree || die "your working tree has uncommitted changes. Commit or restore them first"
  is_ancestor "$t012" main || die "merge PLAT-012 into main first (step 1), then run this event"
  sed_replace scripts/health-check.sh 'TIMEOUT=10' 'TIMEOUT=20'
  git add -A; kc "$PRIYA_N" "$PRIYA_E" "2026-09-03T14:00:00" "HOTFIX: Raise health check timeout to 20 seconds"
  ks_put priya "$(git rev-parse HEAD)"
  say ""
  say "  Priya merged an urgent hotfix to main:"
  git log --oneline -1
  say ""
  say "  Now merge PLAT-015. Predict first: fast-forward, or a merge commit?"
  say ""
}
ff_merged()   { git rev-list --first-parent main | grep -qx "$1"; }
merged_by_merge_commit() {   # a merge commit on main's first-parent line has $1 as its second parent
  local c
  for c in $(git rev-list --first-parent --merges main); do
    [ "$(git rev-parse "$c^2")" = "$1" ] && return 0
  done
  return 1
}
lab_05_check() {
  check_begin 05
  in_repo "$KS_REPO"
  local t012 t015 t016 p; t012=$(ks_get t012); t015=$(ks_get t015); t016=$(ks_get t016); p=$(ks_get priya)
  checkn "PLAT-012 is in main as a fast-forward" "merge it before running the event. Start again if needed" ff_merged "$t012"
  checkn "You ran ks-lab event 05b (Priya's hotfix is on main)" "run: ks-lab event 05b" test -n "$p"
  checkn "PLAT-015 is in main through a merge commit" "main had moved, so this merge needs a merge commit" merged_by_merge_commit "$t015"
  checkn "Merged branches are deleted" "git branch -d <name>" sh -c "! git show-ref -q --verify refs/heads/feature/PLAT-012-cpu-check && ! git show-ref -q --verify refs/heads/feature/PLAT-015-log-retention"
  checkn "The abandoned spike branch is deleted" "-d refuses unmerged work. That refusal is a safety check" branch_absent spike/old-idea
  checkn "The typo branch name is gone" "rename it, don't delete it" branch_absent feature/PLAT-016-montoring
  checkn "feature/PLAT-016-monitoring exists with its work intact" "git branch -m <old> <new>" \
    test "$(git rev-parse -q --verify refs/heads/feature/PLAT-016-monitoring)" = "$t016"
  checkn "You're on main with a clean working tree" "git status" sh -c "git symbolic-ref --short HEAD | grep -qx main && test -z \"\$(git status --porcelain)\""
  check_end 05
}
lab_05_hints() {
cat <<'EOF'
You merge INTO the branch you're on. Switch to main first.
A fast-forward is only possible when main hasn't moved since the branch started (lesson 314). For a three-way merge Git opens a message tab in VS Code: close the tab to finish the merge.
git branch -d deletes merged branches and refuses unmerged ones; -D (lesson 313) forces it, only for work you mean to throw away. git branch -m old new renames (lesson 318).
EOF
}
lab_05_solution() {
cat <<'EOF'

  git switch main
  git merge feature/PLAT-012-cpu-check              # "Fast-forward"
  ks-lab event 05b
  git merge feature/PLAT-015-log-retention          # merge commit: save and close the editor
  git log --oneline --graph -8
  git branch -d feature/PLAT-012-cpu-check feature/PLAT-015-log-retention
  git branch -d spike/old-idea                      # refused: not merged
  git branch -D spike/old-idea                      # deliberate: abandoned work
  git branch -m feature/PLAT-016-montoring feature/PLAT-016-monitoring

EOF
}

# =====================================================================
# P3 — Your first conflict (look, then abort)
# =====================================================================
P3_DIR="$KS_LABS/p3-first-conflict"
lab_p3_start() {
  new_repo "$P3_DIR"
  mkdir -p terraform
  printf 'variable "location" {\n  type    = string\n  default = "uksouth"\n}\n' > terraform/variables.tf
  git add -A; kc "$SAM_N" "$SAM_E" "2026-09-01T09:00:00" "Add location variable"
  local base; base=$(git rev-parse HEAD)
  git switch -q -c feature/PLAT-018-dr-region
  sed_replace terraform/variables.tf '"uksouth"' '"ukwest"'
  git add -A; kc "$SAM_N" "$SAM_E" "2026-09-02T09:00:00" "PLAT-018: Move platform to UK West"
  git switch -q main; git merge -q --ff-only feature/PLAT-018-dr-region
  git switch -q -c feature/PLAT-019-eu-region "$base"
  sed_replace terraform/variables.tf '"uksouth"' '"northeurope"'
  git add -A; kc "$LEA_N" "$LEA_E" "2026-09-02T10:00:00" "PLAT-019: Move platform to North Europe"
  git switch -q main
  rm -f "$(git rev-parse --git-dir)/ORIG_HEAD"
  ks_put start "$(git rev-parse HEAD)"
  next_steps "$P3_DIR"
}
lab_p3_check() {
  check_begin p3
  in_repo "$P3_DIR"
  checkn "You attempted the merge" "on main: git merge feature/PLAT-019-eu-region" test -f "$(git rev-parse --git-dir)/ORIG_HEAD"
  checkn "No merge is in progress (you aborted it)" "git merge --abort" no_merge_in_progress
  checkn "main is exactly where it started" "abort puts everything back" test "$(git rev-parse main)" = "$(ks_get start)"
  checkn "Working tree is clean" "git status" clean_tree
  check_end p3
}
lab_p3_hints() {
cat <<'EOF'
Make sure you're on main, then merge Lea's branch into it.
When Git stops, run git status and open the file. Read it before you do anything else.
git merge --abort takes you back to exactly where you were before the merge.
EOF
}
lab_p3_solution() {
cat <<'EOF'

  git switch main
  git merge feature/PLAT-019-eu-region     # CONFLICT (content): Merge conflict in terraform/variables.tf
  git status                               # both modified: terraform/variables.tf
  cat terraform/variables.tf               # read the markers
  git merge --abort

  Sam moved the platform to UK West. Lea moved it to North Europe. Same line, two
  different answers: Git can't choose for you. Lesson 317 shows how to resolve it.

EOF
}

# =====================================================================
# L06 — Two engineers, one tag block
# =====================================================================
lab_06_start() {
  build_stage_C
  local base; base=$(git rev-parse HEAD)
  git switch -q -c feature/PLAT-021-data-class
  awk '
    /^variable "default_tags"/ { skip = 1 }
    !skip { print }
    skip && /^}/ { skip = 0 }
  ' terraform/variables.tf > v.tmp && cat v.tmp > terraform/variables.tf && rm v.tmp
  cat >> terraform/variables.tf <<'EOF'
variable "default_tags" {
  type = map(string)
  default = {
    environment         = "dev"
    owner               = "platform-team"
    data_classification = "confidential"
  }
}
EOF
  printf '\n## Tagging\n\nData classification tags are required on all resources.\n' >> docs/architecture.md
  git add -A; kc_me "2026-09-04T10:00:00" "PLAT-021: Add data classification tag and new owner"
  ks_put branchtip "$(git rev-parse HEAD)"
  git switch -q main
  sed_replace terraform/variables.tf '    owner       = "cloud-team"' '    owner       = "cloud-team"
    cost_centre = "CC-4410"'
  git add -A; kc "$PRIYA_N" "$PRIYA_E" "2026-09-04T11:30:00" "PLAT-020: Add cost centre tag for finance reporting"
  ks_put priya "$(git rev-parse HEAD)"
  ticket PLAT-021.md <<'EOF'
# PLAT-021  Data classification tag

Add a data_classification = "confidential" tag and change the owner tag to "platform-team".
Your branch feature/PLAT-021-data-class is done and approved. Merge it into main.

Note: Priya's PLAT-020 (cost_centre tag) was merged to main this morning. Keep her tag.
EOF
  next_steps "$KS_REPO"
}
tags_correct_at() {
  local t f; f="$(git rev-parse --git-dir)/ks-vars.tmp"
  git show "$1:terraform/variables.tf" > "$f" 2>/dev/null || return 1
  t=$(tag_pairs "$f" | sort); rm -f "$f"
  [ "$t" = "$(printf 'cost_centre=CC-4410\ndata_classification=confidential\nenvironment=dev\nowner=platform-team')" ]
}
lab_06_check() {
  check_begin 06
  in_repo "$KS_REPO"
  checkn "No merge is still in progress" "finish it: stage the resolved file, then commit" no_merge_in_progress
  checkn "No conflict markers anywhere" "search for the <<<<<<< lines" no_markers
  checkn "Your branch is merged into main" "on main: git merge feature/PLAT-021-data-class" is_ancestor "$(ks_get branchtip)" main
  checkn "Priya's work is still in main" "her commit must stay in history" is_ancestor "$(ks_get priya)" main
  checkn "main ends in a merge commit with two parents" "the merge should complete as a merge commit" test "$(parents_of main)" = "2"
  checkn "default_tags holds exactly the four right tags" "environment=dev, owner=platform-team, cost_centre=CC-4410, data_classification=confidential. No key twice" tags_correct_at main
  checkn "The architecture doc change came through too" "that file merged cleanly. It should be in main" blob_has main docs/architecture.md 'Data classification tags'
  checkn "Working tree is clean" "git status" clean_tree
  check_end 06
}
lab_06_hints() {
cat <<'EOF'
git status names the conflicted file, and the file that merged cleanly. Read it before you edit.
VS Code labels main's side Current Change (it has Priya's tag) and your branch Incoming Change (lesson 317). Accept Both Changes leaves two owner lines: edit it so every tag appears once.
Edit and save, stage the file (+ in Source Control), then commit. git merge --abort takes you back to before the merge if you need a fresh go.
EOF
}
lab_06_solution() {
cat <<'EOF'

  git switch main
  git merge feature/PLAT-021-data-class
  git status          # both modified: terraform/variables.tf
  git diff            # read the conflict
  # edit the block to:
  #   default = {
  #     environment         = "dev"
  #     owner               = "platform-team"
  #     cost_centre         = "CC-4410"
  #     data_classification = "confidential"
  #   }
  git grep -n '<<<<<<<'          # nothing left
  git add terraform/variables.tf
  git commit                      # keep the default merge message
  git log --oneline --graph -6

  The trap: keeping both owner lines. Terraform rejects a map with the same key twice.

EOF
}

# =====================================================================
# C1 — Two tickets, one afternoon (stage gate)
# =====================================================================
lab_c1_start() {
  build_stage_C
  write_tags_resolved
  git add -A && kc_me "2026-09-05T10:00:00" "PLAT-021: Add data classification tag and new owner"
  ks_put start "$(git rev-parse HEAD)"
  ticket PLAT-030.md <<'EOF'
# PLAT-030  Add a log rotation script

Add scripts/rotate-logs.sh (below), executable, and list it in the README scripts table
with the purpose "Rotates application logs daily".

----- scripts/rotate-logs.sh -----
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
----------------------------------
EOF
  ticket PLAT-031.md <<'EOF'
# PLAT-031  Document the secondary region

In docs/architecture.md, replace "No secondary region yet." with
"Secondary region: UK West (disaster recovery)."
Update the "Last reviewed:" date at the bottom of README.md to today's date.
EOF
  next_steps "$KS_REPO"
}
reflog_has_branch() { git reflog show HEAD 2>/dev/null | grep -qE "moving from [^ ]+ to $1"; }
lab_c1_check() {
  check_begin c1
  in_repo "$KS_REPO"
  local s; s=$(ks_get start)
  checkn "You worked on a feature/PLAT-030-... branch" "each ticket gets its own branch" reflog_has_branch 'feature/PLAT-030-[a-z0-9-]+'
  checkn "You worked on a feature/PLAT-031-... branch" "each ticket gets its own branch" reflog_has_branch 'feature/PLAT-031-[a-z0-9-]+'
  checkn "rotate-logs.sh is in main" "PLAT-030 isn't merged yet" blob_has main scripts/rotate-logs.sh 'Rotate application logs'
  checkn "README lists rotate-logs.sh" "PLAT-030 asks for a table row" blob_has main README.md 'rotate-logs\.sh'
  checkn "The architecture doc names UK West as secondary" "PLAT-031" blob_has main docs/architecture.md 'Secondary region: UK West'
  checkn "README's Last reviewed date is updated" "PLAT-031" sh -c "! git show main:README.md | grep -q 'Last reviewed: 2026-09-01'"
  checkn "Every ticket commit starts with its ticket id" "PLAT-030: ... or PLAT-031: ..." \
    sh -c "test -z \"\$(git log --no-merges --format=%s $s..main | grep -vE '^PLAT-03[01]: ')\""
  checkn "History on main wasn't rewritten" "never reset main" is_ancestor "$s" main
  checkn "No conflict markers" "check README.md" no_markers
  checkn "Merged branches are deleted" "only main should be left" test "$(git for-each-ref --format=x refs/heads | wc -l | tr -d ' ')" = "1"
  checkn "You're on main with a clean working tree" "git status" sh -c "git symbolic-ref --short HEAD | grep -qx main && test -z \"\$(git status --porcelain)\""
  check_end c1
}
lab_c1_hints() {
cat <<'EOF'
Which lab did you do each part in before? Branch (L04), merge (L05), conflict (L06), clean up (L05).
EOF
}
lab_c1_solution() {
cat <<'EOF'

  git switch -c feature/PLAT-030-log-rotation
  # add scripts/rotate-logs.sh, chmod +x, README row
  git add scripts/rotate-logs.sh README.md
  git commit -m "PLAT-030: Add log rotation script"
  git switch main
  git switch -c feature/PLAT-031-secondary-region
  # edit docs/architecture.md and README.md Last reviewed
  git commit -am "PLAT-031: Document UK West as secondary region"
  git switch main
  git merge feature/PLAT-030-log-rotation          # fast-forward
  git merge feature/PLAT-031-secondary-region      # merge commit
  git branch -d feature/PLAT-030-log-rotation feature/PLAT-031-secondary-region

EOF
}

# =====================================================================
# L07 — The undo ladder (a-e)
# =====================================================================
l07_base() { build_stage_D; ks_put start "$(git rev-parse HEAD)"; }

lab_07a_start() {
  l07_base
  sed_replace terraform/environments/prod.tfvars 'Standard_B2s' 'Standard_E64s_v5'
  say "  Situation a: you edited prod.tfvars by mistake. Nothing is staged."
  next_steps "$KS_REPO"
}
lab_07a_check() {
  check_begin 07a; in_repo "$KS_REPO"
  checkn "prod.tfvars matches the last commit" "throw away the unstaged change" file_has terraform/environments/prod.tfvars 'Standard_B2s'
  checkn "No new commits" "this didn't need a commit" test "$(git rev-parse HEAD)" = "$(ks_get start)"
  checkn "Working tree is clean" "git status" clean_tree
  check_end 07a
}
lab_07a_hints() { printf '%s\n' "Where is the mistake right now: working tree, staging area, or a commit? And could anyone else already have it?" "Working tree only. One command restores a file from the last commit." "git restore <file>"; }
lab_07a_solution() { say ""; say "  git restore terraform/environments/prod.tfvars"; say ""; }

lab_07b_start() {
  l07_base
  printf '5. Record what you removed in the incident ticket.\n' >> docs/runbooks/disk-space.md
  printf '2026-09-07 10:01:22 DEBUG cleanup dry run\n' > debug.log
  git add docs/runbooks/disk-space.md debug.log
  say "  Situation b: you staged debug.log along with your real runbook change."
  next_steps "$KS_REPO"
}
lab_07b_check() {
  check_begin 07b; in_repo "$KS_REPO"
  checkn "Only the runbook change is staged" "debug.log shouldn't be in the staging area" \
    test "$(git diff --cached --name-only)" = "docs/runbooks/disk-space.md"
  checkn "debug.log still exists on disk" "unstage it, don't delete it" test -f debug.log
  checkn "debug.log is not tracked" "unstage it" sh -c "! git ls-files --error-unmatch debug.log"
  checkn "No new commits" "nothing needed committing" test "$(git rev-parse HEAD)" = "$(ks_get start)"
  check_end 07b
}
lab_07b_hints() { printf '%s\n' "Where is the mistake: working tree, staging area, or a commit?" "The staging area. You want the opposite of git add, for one file." "git restore --staged <file> unstages and leaves the file on disk."; }
lab_07b_solution() { say ""; say "  git restore --staged debug.log      # older Git: git reset HEAD debug.log"; say "  git status"; say ""; }

lab_07c_start() {
  l07_base
  git switch -q -c feature/PLAT-033-backup-retention
  printf '\nvariable "backup_retention_days" {\n  type    = number\n  default = 30\n}\n' >> terraform/variables.tf
  git add -A; kc_me "2026-09-07T11:00:00" "PLAT-033: Add backup retenion variable"
  ks_put tip "$(git rev-parse HEAD)"
  printf '# Runbook: backup retention\n\nArchives older than backup_retention_days are deleted nightly.\n' > docs/runbooks/backup.md
  say "  Situation c: your last commit has a typo in its message and is missing"
  say "  docs/runbooks/backup.md. It hasn't been pushed."
  next_steps "$KS_REPO"
}
lab_07c_check() {
  check_begin 07c; in_repo "$KS_REPO"
  checkn "Still exactly one commit on the branch" "fix the commit, don't add a second one" test "$(git rev-list --count main..HEAD)" = "1"
  checkn "It sits directly on main" "its parent should be unchanged" test "$(git rev-parse HEAD~1)" = "$(ks_get start)"
  checkn "The message is spelled right (retention)" "the typo is still there" sh -c "git log -1 --format=%s | grep -q 'retention' && ! git log -1 --format=%s | grep -q 'retenion'"
  checkn "The commit includes docs/runbooks/backup.md" "the missing file isn't in the commit" blob_has HEAD docs/runbooks/backup.md 'backup retention'
  checkn "The commit still has the variable" "keep the original change" blob_has HEAD terraform/variables.tf 'backup_retention_days'
  checkn "Working tree is clean" "git status" clean_tree
  check_end 07c
}
lab_07c_hints() { printf '%s\n' "Where is the mistake: in a commit. Could anyone else have it? No, it's not pushed." "Unpushed commits can be replaced. Stage the missing file first." "git commit --amend replaces the last commit with what's staged, and lets you rewrite the message."; }
lab_07c_solution() { say ""; say "  git add docs/runbooks/backup.md"; say "  git commit --amend -m \"PLAT-033: Add backup retention variable\""; say ""; }

lab_07d_start() {
  l07_base
  git switch -q -c feature/PLAT-034-alerting
  printf '\nvariable "alert_email" {\n  type    = string\n  default = "platform@novatech.example"\n}\n' >> terraform/variables.tf
  git add -A; kc_me "2026-09-07T12:00:00" "PLAT-034: Add alert email variable"
  sed_replace terraform/variables.tf 'platform@novatech.example' 'platform-alerts@novatech.example'
  git add -A; kc_me "2026-09-07T12:05:00" "PLAT-034: Fix alert email default"
  ks_put tree "$(git rev-parse HEAD^{tree})"
  say "  Situation d: your last two commits should have been one. Neither is pushed."
  next_steps "$KS_REPO"
}
lab_07d_check() {
  check_begin 07d; in_repo "$KS_REPO"
  checkn "One commit on the branch" "the two should become one" test "$(git rev-list --count main..HEAD)" = "1"
  checkn "It sits directly on main" "its parent should be main" test "$(git rev-parse HEAD~1)" = "$(ks_get start)"
  checkn "The content is exactly what the two commits held" "nothing should be lost or added" test "$(git rev-parse HEAD^{tree})" = "$(ks_get tree)"
  checkn "Message starts with PLAT-034:" "see CONTRIBUTING.md" sh -c "git log -1 --format=%s | grep -q '^PLAT-034: '"
  checkn "Working tree is clean" "git status" clean_tree
  check_end 07d
}
lab_07d_hints() { printf '%s\n' "In commits, not pushed. So rewriting is allowed." "Move the branch back two commits but keep the changes staged, then commit once." "git reset --soft HEAD~2, then git commit."; }
lab_07d_solution() { say ""; say "  git reset --soft HEAD~2"; say "  git commit -m \"PLAT-034: Add alert email variable\""; say ""; }

lab_07e_start() {
  l07_base
  sed_replace scripts/health-check.sh 'HEALTH_URL="https://status.novatech.example/healthz"' 'HEALTH_URL="https://status.novatech.example/healthz-v2-beta"'
  git add -A; kc "$DAN_N" "$DAN_E" "2026-09-07T09:00:00" "Point health check at new status page"
  ks_put bad "$(git rev-parse HEAD)"
  sed_replace config/app-settings.json '"region": "uksouth"' '"region": "uksouth",
  "drRegion": "ukwest"'
  git add -A; kc "$SAM_N" "$SAM_E" "2026-09-07T10:00:00" "Add DR region to app settings"
  ks_put tip "$(git rev-parse HEAD)"
  local r; r=$(new_bare_remote 07e); git remote add origin "$r"; git push -q -u origin main 2>/dev/null
  say "  Situation e: Dan's commit on main broke the health check URL. Other engineers"
  say "  have already pulled main. Sam's later commit must stay."
  next_steps "$KS_REPO"
}
lab_07e_check() {
  check_begin 07e; in_repo "$KS_REPO"
  local bad; bad=$(ks_get bad)
  checkn "main's existing history is untouched" "main is shared: don't reset it. Start again: ks-lab start 07e" is_ancestor "$(ks_get tip)" main
  checkn "A revert of Dan's commit is on main" "a new commit that undoes it" sh -c "git log main --format=%B | grep -q 'This reverts commit $bad'"
  checkn "The health check URL is back to /healthz" "check scripts/health-check.sh" blob_has main scripts/health-check.sh 'healthz"$'
  checkn "Sam's later change is still there" "only Dan's commit should be undone" blob_has main config/app-settings.json 'drRegion'
  checkn "Working tree is clean" "git status" clean_tree
  check_end 07e
}
lab_07e_hints() { printf '%s\n' "In a commit, and other people have it. Rewriting main would break their copies." "You need a new commit that does the opposite of Dan's." "git log --oneline to find his hash, then git revert <hash>."; }
lab_07e_solution() { say ""; say "  git log --oneline -5"; say "  git revert <dan's-hash>        # save and close the editor"; say "  git push"; say ""; say "  Never reset a shared branch: everyone who pulled it would now have different history."; say ""; }

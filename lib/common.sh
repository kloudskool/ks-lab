# shellcheck shell=bash
# ks-lab common helpers. Works on bash 3.2 (macOS), Git Bash (Windows) and Linux.

KS_ORG="${KS_ORG:-kloudskool}"            # GitHub org that hosts the shared lab repos
KS_HOME="${KS_HOME:-$HOME/.ks-lab}"
KS_STATE="$KS_HOME/state"
KS_LABS="${KS_LABS:-$HOME/kloudskool-labs}"
KS_REPO="$KS_LABS/cloud-engineering-lab"
KS_REMOTES="$KS_LABS/.remotes"
KS_BACKUP="$KS_LABS/.backup"

mkdir -p "$KS_STATE" "$KS_LABS"

# ---------- output ----------
if [ -t 1 ]; then KB=$'\033[1m'; KR=$'\033[0m'; else KB=""; KR=""; fi
say()   { printf '%s\n' "$*"; }
head1() { printf '\n%s%s%s\n' "$KB" "$*" "$KR"; }
die()   { printf '\nks-lab: %s\n\n' "$*" >&2; exit 1; }

# ---------- state ----------
state_get() { [ -f "$KS_STATE/$1" ] && cat "$KS_STATE/$1" || printf '%s' "${2:-}"; }
state_set() { printf '%s' "$2" > "$KS_STATE/$1"; }
state_inc() { local n; n=$(state_get "$1" 0); n=$((n + 1)); state_set "$1" "$n"; printf '%s' "$n"; }

# ---------- completion codes ----------
# Same algorithm is used by the LMS quiz generator and the GitHub check (git blob SHA-1).
ks_code() {
  local h
  h=$(printf 'kloudskool:%s:v1' "$1" | git hash-object --stdin | cut -c1-6 | tr 'abcdef' 'ABCDEF')
  printf 'KS-%s-%s' "$(printf '%s' "$1" | tr 'abcdefghijklmnopqrstuvwxyz' 'ABCDEFGHIJKLMNOPQRSTUVWXYZ')" "$h"
}

# ---------- deterministic commits ----------
# kc "Name" "email" "2026-08-01T09:00:00" "message"   (commits whatever is staged)
kc() {
  fix_modes
  GIT_AUTHOR_NAME="$1" GIT_AUTHOR_EMAIL="$2" GIT_AUTHOR_DATE="$3 +0100" \
  GIT_COMMITTER_NAME="$1" GIT_COMMITTER_EMAIL="$2" GIT_COMMITTER_DATE="$3 +0100" \
    git -c commit.gpgsign=false commit -q --no-verify -m "$4"
}
# Make every scripts/*.sh executable in the index, so trees (and SHAs) match on Windows too.
fix_modes() { local f; for f in $(git ls-files '*.sh'); do chmod +x "$f" 2>/dev/null; git update-index --chmod=+x "$f"; done; }
kc_det() { git add -A && fix_modes && kc "$@"; }

# Write a ticket the student reads outside the repo.
ticket() {   # ticket <file-name>   (content from stdin)
  mkdir -p "$KS_LABS/tickets"
  cat > "$KS_LABS/tickets/$1"
}
next_steps() {  # next_steps <folder>
  say ""
  say "  Ready. Move into the lab folder (your terminal may still be in an old copy):"
  say ""
  say "      cd $1"
  say ""
  say "  Then follow the instructions on the lab page. Tickets are in $KS_LABS/tickets/"
  say ""
}
kc_all() { git add -A && kc "$@"; }

PRIYA_N="Priya Shah";   PRIYA_E="priya.shah@novatech.example"
SAM_N="Sam Okafor";     SAM_E="sam.okafor@novatech.example"
DAN_N="Dan Mercer";     DAN_E="dan.mercer@novatech.example"
LEA_N="Lea Novak";      LEA_E="lea.novak@novatech.example"

# Commits as the student (their identity, fixed date so labs are reproducible)
me_name()  { git config --global user.name  2>/dev/null || printf 'KloudSkool Student'; }
me_email() { git config --global user.email 2>/dev/null || printf 'student@example.com'; }
kc_me() { kc "$(me_name)" "$(me_email)" "$1" "$2"; }

# ---------- repo helpers ----------
new_repo() {   # new_repo <path> : fresh repo, backing up anything already there
  local p="$1"
  backup_dir "$p"
  mkdir -p "$p"
  cd "$p" || die "cannot enter $p"
  git init -q -b main 2>/dev/null || { git init -q && git symbolic-ref HEAD refs/heads/main; }
  git config core.autocrlf false
  git config user.name  "$(me_name)"
  git config user.email "$(me_email)"
}

backup_dir() {   # move an existing folder into the backup area, never overwriting
  [ -e "$1" ] || return 0
  mkdir -p "$KS_BACKUP"
  local dest="$KS_BACKUP/$(basename "$1")-$(date +%Y%m%d-%H%M%S)" n=1
  while [ -e "$dest" ]; do dest="$KS_BACKUP/$(basename "$1")-$(date +%Y%m%d-%H%M%S)-$n"; n=$((n + 1)); done
  mv "$1" "$dest" && say "  (your previous copy was moved to $dest)"
}

new_bare_remote() {   # new_bare_remote <name>  -> prints path
  local p="$KS_REMOTES/$1.git"
  rm -rf "$p"; mkdir -p "$KS_REMOTES"
  git init -q --bare "$p"
  git --git-dir="$p" symbolic-ref HEAD refs/heads/main
  printf '%s' "$p"
}

protect_main_hook() {  # makes a local bare remote reject direct pushes to main, GitHub-style
  cat > "$1/hooks/pre-receive" <<'EOF'
#!/bin/sh
while read old new ref; do
  if [ "$ref" = "refs/heads/main" ]; then
    echo "error: GH006: Protected branch update failed for refs/heads/main."
    echo "error: Changes must be made through a pull request."
    exit 1
  fi
done
exit 0
EOF
  chmod +x "$1/hooks/pre-receive"
}

deny_all_hook() {  # simulates pushing to a repo you have no write access to
  cat > "$1/hooks/pre-receive" <<'EOF'
#!/bin/sh
echo "Permission to kloudskool/cloud-runbooks.git denied to you."
echo "fatal: unable to access 'https://github.com/kloudskool/cloud-runbooks.git/': The requested URL returned error: 403"
exit 1
EOF
  chmod +x "$1/hooks/pre-receive"
}

in_repo() { cd "$1" 2>/dev/null || die "I can't find $1. Run the lab's start command first."; }

github_user() { state_get github_user; }
need_github_user() {
  [ -n "$(github_user)" ] || die "I don't know your GitHub username yet. Run: ks-lab check 00b"
}
origin_is_github() { git remote get-url origin 2>/dev/null | grep -qi 'github.com'; }

# Clone the student's GitHub repo into a temp folder, commit as a teammate, push. No effect on their working tree.
teammate_push() {   # teammate_push <branch> <base-ref-or-empty> <name> <email> <date> <msg> <fn-that-edits-files>
  local branch="$1" base="$2" n="$3" e="$4" d="$5" msg="$6" fn="$7" url tmp
  url=$(git -C "$KS_REPO" remote get-url origin) || die "no origin remote in $KS_REPO"
  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t kslab)
  git clone -q "$url" "$tmp/c" || die "could not clone $url (check you can push to it)"
  (
    cd "$tmp/c" || exit 1
    git config core.autocrlf false
    if git rev-parse -q --verify "origin/$branch" >/dev/null; then git switch -q "$branch"
    else git switch -q -c "$branch" "${base:-origin/main}"; fi
    "$fn"
    git add -A && kc "$n" "$e" "$d" "$msg"
    git push -q origin "$branch" 2>&1 | grep -v '^remote:' || true
    git rev-parse HEAD > "$tmp/sha"
  )
  local sha; sha=$(cat "$tmp/sha" 2>/dev/null); rm -rf "$tmp"; printf '%s' "$sha"
}

# ---------- check framework ----------
C_TOTAL=0; C_FAIL=0
check_begin() { C_TOTAL=0; C_FAIL=0; head1 "Checking lab $1"; }
# check "<description>" <command...>   -- passes when the command exits 0
check() {
  local desc="$1"; shift
  C_TOTAL=$((C_TOTAL + 1))
  if "$@" >/dev/null 2>&1; then printf '  PASS     %s\n' "$desc"
  else printf '  NOT YET  %s\n' "$desc"; C_FAIL=$((C_FAIL + 1)); fi
}
# nudge "<text>" : prints under the previous line only if it failed
LAST_FAIL=0
checkn() {   # checkn "<desc>" "<nudge>" <command...>
  local desc="$1" nudge="$2"; shift 2
  local before=$C_FAIL
  check "$desc" "$@"
  [ "$C_FAIL" -gt "$before" ] && printf '           -> %s\n' "$nudge"
  return 0
}
check_end() {   # check_end <lab> [local-only-note]
  local lab="$1"
  printf '\n'
  if [ "$C_FAIL" -eq 0 ]; then
    state_set "passed-$lab" 1
    if [ -n "${2:-}" ]; then
      say "  All local checks PASS ($C_TOTAL/$C_TOTAL)."
      say "  $2"
    else
      say "  All checks PASS ($C_TOTAL/$C_TOTAL)."
      say ""
      say "  Your completion code:  ${KB}$(ks_code "$lab")${KR}"
      say "  Choose it in the lab's check-in quiz on the learning platform."
    fi
  else
    local a; a=$(state_inc "attempts-$lab")
    say "  $C_FAIL of $C_TOTAL not there yet. Fix those and run the check again."
    say "  Stuck? ks-lab hint $lab  shows the next hint."
    if [ "$a" -ge 2 ]; then say "  You've checked $a times, so  ks-lab solution $lab  is now unlocked."; fi
  fi
  printf '\n'
}

# ---------- small predicates for checks ----------
is_repo()            { git rev-parse --git-dir >/dev/null 2>&1; }
on_branch()          { [ "$(git symbolic-ref --short HEAD 2>/dev/null)" = "$1" ]; }
# macOS Finder drops .DS_Store files into any folder it opens (lessons 306/307 show this). Never fail a check on them.
ks_porcelain()       { git status --porcelain | grep -vE '[ /]\.DS_Store$'; }
clean_tree()         { [ -z "$(ks_porcelain)" ]; }
no_markers()         { ! git grep -qE '^(<<<<<<<|=======$|>>>>>>>)' -- . 2>/dev/null; }
no_merge_in_progress(){ [ ! -f "$(git rev-parse --git-dir)/MERGE_HEAD" ]; }
branch_exists()      { git show-ref -q --verify "refs/heads/$1"; }
branch_absent()      { ! git show-ref -q --verify "refs/heads/$1"; }
is_ancestor()        { git merge-base --is-ancestor "$1" "$2"; }
file_has()           { grep -qE "$2" "$1" 2>/dev/null; }
file_lacks()         { ! grep -qE "$2" "$1" 2>/dev/null; }
blob_has()           { git show "$1:$2" 2>/dev/null | grep -qE "$3"; }
never_committed()    { [ -z "$(git log --all --format=%H -- "$1" 2>/dev/null)" ]; }
never_in_history()   { [ -z "$(git log --all -S"$1" --format=%H 2>/dev/null)" ]; }
count_le()           { [ "$1" -le "$2" ]; }
count_ge()           { [ "$1" -ge "$2" ]; }
count_eq()           { [ "$1" -eq "$2" ]; }
tracked()            { git ls-files --error-unmatch "$1" >/dev/null 2>&1; }
untracked_exists()   { [ -e "$1" ] && ! tracked "$1"; }
mode_is()            { [ "$(git ls-tree "$1" -- "$2" | awk '{print $1}')" = "$3" ]; }
parents_of()         { git rev-list --parents -n1 "$1" | awk '{print NF-1}'; }
good_msg() {  # every commit in range has a message of 4+ words and is not a lazy one-word message
  local range="$1" m bad=0
  while IFS= read -r m; do
    [ -z "$m" ] && continue
    case "$(printf '%s' "$m" | tr 'A-Z' 'a-z')" in
      update|updates|changes|change|wip|commit|stuff|fix|"first commit"|"initial commit"|test) bad=1 ;;
    esac
    [ "$(printf '%s' "$m" | wc -w | tr -d ' ')" -ge 4 ] || bad=1
  done <<EOF
$(git log --format=%s $range)
EOF
  [ "$bad" -eq 0 ]
}

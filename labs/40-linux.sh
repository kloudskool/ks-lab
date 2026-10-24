# shellcheck shell=bash
# Linux Fundamentals labs (module 02/04, lessons 201-226). Run inside the student's Ubuntu VM.
# Ids: lx00 (setup), lx01-lx11, lxc1 (stage gate), lxt01-lxt12 (Break Room), lxfinal.

# ---------- helpers ----------
lx_path()  { printf '%s/%s' "$KS_LABS" "$1"; }
lx_fresh() {   # lx_fresh <folder> : back up any old copy, create it empty, cd into it
  local p; p=$(lx_path "$1")
  backup_dir "$p"; mkdir -p "$p"; cd "$p" || die "cannot enter $p"
}
lx_in()    { cd "$(lx_path "$1")" 2>/dev/null || die "I can't find $(lx_path "$1"). Run the lab's start command first."; }
lx_need_linux() {
  [ "$(uname -s)" = "Linux" ] || die "the Linux labs run inside your Ubuntu VM (lessons 202/203), not on your Mac or Windows terminal."
}
lx_sudo() {    # lx_sudo "<why>" : make sure sudo works before we use it
  say "  ks-lab needs sudo to $1."
  say "  If it asks for a password, it's the one you log in to your Ubuntu VM with."
  sudo -v || die "sudo didn't work. Lesson 217 shows how to check you're in the sudo group."
}
same_file()  { cmp -s "$1" "$2"; }
mode_is_lx() { [ "$(stat -c %a "$1" 2>/dev/null)" = "$2" ]; }
owner_is()   { [ "$(stat -c %U "$1" 2>/dev/null)" = "$2" ]; }
is_dir()     { [ -d "$1" ] && [ ! -L "$1" ]; }
is_file()    { [ -f "$1" ] && [ ! -L "$1" ]; }
absent()     { [ ! -e "$1" ] && [ ! -L "$1" ]; }
empty_file() { [ -f "$1" ] && [ ! -s "$1" ]; }
content_is() { [ "$(cat "$1" 2>/dev/null)" = "$2" ]; }
user_exists()  { getent passwd "$1" >/dev/null 2>&1; }
group_exists() { getent group "$1" >/dev/null 2>&1; }
in_group()     { id -nG "$1" 2>/dev/null | tr ' ' '\n' | grep -qx "$2"; }
svc_active()   { systemctl is-active --quiet "$1" 2>/dev/null; }
pkg_installed(){ dpkg -s "$1" 2>/dev/null | grep -q '^Status: install ok installed'; }
page_has()     { curl -s --max-time 5 http://localhost/ 2>/dev/null | grep -q "$1"; }
bashrc_has()   { grep -qE "$1" "$HOME/.bashrc" 2>/dev/null; }
login_shell_has() {   # login_shell_has <command> <regex> : run in a fresh interactive bash that reads ~/.bashrc
  env -i HOME="$HOME" USER="$USER" TERM=dumb PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    bash -ic "$1" 2>/dev/null | grep -qE "$2"
}
no_swap_files() { [ -z "$(find "$1" -name '.*.sw?' 2>/dev/null)" ]; }
user_pwd_is() { [ "$(cd "$KS_USER_PWD" 2>/dev/null && pwd -P)" = "$(cd "$1" 2>/dev/null && pwd -P)" ]; }
no_proc()     { ! pgrep -u "$(id -u)" -f "$1" >/dev/null 2>&1; }
ssh_ok()      { ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -i "$1" "$USER@localhost" true >/dev/null 2>&1; }
ssh_refused() { ! ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o IdentitiesOnly=yes -i "$1" "$USER@localhost" true >/dev/null 2>&1; }
filler() { yes "$2" | head -c "$1"; }   # filler <bytes> <line> : a file of an exact size

lx_list() {
cat <<'EOF'

  Linux labs (run them inside your Ubuntu VM)
  lx00  Lab 00: is the VM ready?                     lx01  First day on the server
  lx02  Build the project workspace                  lx03  Read the incident notes
  lx04  Back up, then clean up                       lx05  Edit the config (vim and nano)
  lx06  Root-owned files and moving things           lxc1  Stage gate: prepare release 1.3
  lx07  Deploy the web server                        lx08  Onboard a teammate
  lx09  Your first ops script                        lx10  Log in with keys, then revoke one
  lx11  Bonus: links                                 lxfinal  Final assessment: first week on web02
  break lx1 - lx12   Linux Break Room scenarios

EOF
}

# =====================================================================
# lx00  Lab 00: is the VM ready?
# =====================================================================
lab_lx00_start() {
  lx_need_linux
  say ""
  say "  Lab 00 has nothing to set up. It checks your Ubuntu VM is ready for the labs."
  say "  Run:  ks-lab check lx00"
  say ""
}
lab_lx00_check() {
  lx_need_linux
  check_begin lx00
  checkn "You're on Ubuntu" "the labs need the Ubuntu VM from lesson 202 or 203" \
    grep -qi '^ID=ubuntu' /etc/os-release
  checkn "You're logged in as your own user, not root" "log out and log in as the user you created during the install" \
    test "$(id -u)" != "0"
  checkn "Your user is in the sudo group" "lesson 217: groups \$(whoami) should list sudo" \
    in_group "$(id -un)" sudo
  checkn "The VM can reach the internet" "check the VM's network adapter in VirtualBox / VMware Fusion" \
    curl -s --max-time 8 -o /dev/null https://github.com
  checkn "Git is installed" "sudo apt install -y git" command -v git
  checkn "curl is installed" "sudo apt install -y curl" command -v curl
  check_end lx00
}
lab_lx00_hints() {
cat <<'EOF'
Each NOT YET line says what's missing. Fix them one at a time, then check again.
groups $(whoami) shows your groups. Your install user is in sudo automatically.
No internet? In VirtualBox or VMware Fusion, check the VM's network adapter is connected (NAT is fine).
EOF
}
lab_lx00_solution() {
cat <<'EOF'

  sudo apt update
  sudo apt install -y git curl
  groups $(whoami)          # should include sudo
  ks-lab check lx00

EOF
}

# =====================================================================
# lx01  First day on the server  (after 207: pwd, cd, ls -l, ls -a)
# =====================================================================
lab_lx01_start() {
  lx_need_linux
  lx_fresh web01
  mkdir -p app/current config releases/v1.0 releases/v1.1 releases/v1.2 var/log scripts
  printf '#!/bin/bash\necho "Starting the NovaTech web app"\n' > app/start.sh
  printf '# NovaTech web app\nStart it with app/start.sh\n' > app/README.md
  printf 'v1.2.0\n' > app/current/VERSION
  printf 'server {\n    listen 80;\n    root /var/www/html;\n}\n' > config/nginx.conf
  printf 'APP_ENV=production\nAPP_PORT=80\n' > config/app.env
  printf 'DB_PASSWORD=not-a-real-password\n' > config/.env.production
  printf '#!/bin/bash\necho "app v1.0"\n' > releases/v1.0/app.sh
  printf '#!/bin/bash\necho "app v1.1"\n' > releases/v1.1/app.sh
  printf '#!/bin/bash\necho "app v1.2"\n' > releases/v1.2/app.sh
  printf 'v1.2: faster start-up\nv1.1: new logo\nv1.0: first release\n' > releases/release-notes.txt
  filler 48213 '10.0.0.7 - - "GET / HTTP/1.1" 200 512' > var/log/access.log
  filler 9050  'INFO request handled' > var/log/app.log
  filler 1200  'WARN slow response' > var/log/error.log
  printf '#!/bin/bash\necho "backing up web01"\n' > scripts/backup.sh
  ticket LX01.md <<'EOF'
# LX01: First day on web01

Your lead wants to know you can find your way around web01 before you touch anything.
Explore ~/kloudskool-labs/web01 with pwd, cd and ls, and answer the questions on the lab page.
Don't create, change or delete anything.
When you've found the folder that holds a hidden file, cd into it and run: ks-lab check lx01
EOF
  next_steps "$(lx_path web01)"
}
lab_lx01_check() {
  check_begin lx01
  local w; w=$(lx_path web01)
  checkn "web01 is still there, untouched" "run ks-lab start lx01 to put it back. This lab is look, don't touch" \
    sh -c "test -f '$w/config/.env.production' && test -d '$w/releases/v1.0' && test -f '$w/var/log/access.log'"
  checkn "Your terminal is in the folder that holds the hidden file" "ls -a shows hidden files. cd into the folder that has one, then check again from there" \
    user_pwd_is "$w/config"
  check_end lx01
}
lab_lx01_hints() {
cat <<'EOF'
pwd tells you where you are. cd ~/kloudskool-labs/web01 takes you to the server folder. ls shows what's there.
ls -l marks folders with a d at the start of the line and shows each file's size. ls -a also shows hidden files: their names start with a dot.
The hidden file is in web01/config. cd ~/kloudskool-labs/web01/config, then run ks-lab check lx01 from there.
EOF
}
lab_lx01_solution() {
cat <<'EOF'

  cd ~/kloudskool-labs/web01
  ls                       # app  config  releases  scripts  var
  ls releases              # 4 items: release-notes.txt v1.0 v1.1 v1.2
  ls -l var/log            # access.log is the biggest
  ls -l app                # current starts with d: it's a folder
  ls -a config             # .env.production is hidden
  cd config
  pwd
  ks-lab check lx01

EOF
}

# =====================================================================
# lx02  Build the project workspace  (after 210: touch, paths, mkdir -p)
# =====================================================================
lab_lx02_start() {
  lx_need_linux
  lx_fresh projects
  ticket LX02.md <<'EOF'
# LX02: Workspace for the billing API

Create this inside ~/kloudskool-labs/projects:

billing-api/
  README.md
  src/
    app.sh
  tests/
  config/
    dev/settings.conf
    prod/settings.conf
  logs/
    app.log      <- create this one from inside src/, using a relative path

Every file starts empty.
EOF
  next_steps "$(lx_path projects)"
}
lab_lx02_check() {
  check_begin lx02
  local b; b="$(lx_path projects)/billing-api"
  checkn "billing-api exists in projects" "cd ~/kloudskool-labs/projects, then mkdir billing-api" is_dir "$b"
  checkn "Folders src, tests and logs exist" "mkdir can make several folders in one command" \
    sh -c "test -d '$b/src' && test -d '$b/tests' && test -d '$b/logs'"
  checkn "config/dev and config/prod exist" "mkdir -p makes the parent folders too (lesson 210)" \
    sh -c "test -d '$b/config/dev' && test -d '$b/config/prod'"
  checkn "README.md and src/app.sh exist and are empty" "touch creates an empty file" \
    sh -c "test -f '$b/README.md' && ! test -s '$b/README.md' && test -f '$b/src/app.sh' && ! test -s '$b/src/app.sh'"
  checkn "Both settings.conf files exist and are empty" "touch config/dev/settings.conf config/prod/settings.conf" \
    sh -c "test -f '$b/config/dev/settings.conf' && ! test -s '$b/config/dev/settings.conf' && test -f '$b/config/prod/settings.conf' && ! test -s '$b/config/prod/settings.conf'"
  checkn "logs/app.log exists" "from inside src: touch ../logs/app.log (.. is the folder above)" empty_file "$b/logs/app.log"
  checkn "Nothing extra landed in src or tests" "a typo can create a stray file or folder: ls -R billing-api shows everything, and lesson 213's rm removes it" \
    sh -c "test \"\$(ls -A '$b/src')\" = 'app.sh' && test -z \"\$(ls -A '$b/tests')\""
  check_end lx02
}
lab_lx02_hints() {
cat <<'EOF'
Start with pwd. Then cd ~/kloudskool-labs/projects so every relative path starts from there.
mkdir -p billing-api/config/dev creates billing-api, config and dev in one go. touch creates empty files.
Last step: cd billing-api/src, then touch ../logs/app.log. Two dots means the folder above where you are.
EOF
}
lab_lx02_solution() {
cat <<'EOF'

  cd ~/kloudskool-labs/projects
  mkdir -p billing-api/src billing-api/tests billing-api/logs billing-api/config/dev billing-api/config/prod
  touch billing-api/README.md billing-api/src/app.sh
  touch billing-api/config/dev/settings.conf billing-api/config/prod/settings.conf
  cd billing-api/src
  touch ../logs/app.log
  ls -R ~/kloudskool-labs/projects/billing-api
  ks-lab check lx02

EOF
}

# =====================================================================
# lx03  Read the incident notes  (after 211: cat, echo, >, cat a b > c)
# =====================================================================
lab_lx03_start() {
  lx_need_linux
  lx_fresh incident
  cat > app.log <<'EOF'
2026-10-03 09:00:01 INFO web01 started
2026-10-03 09:14:22 INFO 1200 requests handled
2026-10-03 09:31:07 WARN disk /var at 85%
2026-10-03 09:52:40 WARN disk /var at 91%
2026-10-03 10:05:13 ERROR disk /var at 97%, writes failing
2026-10-03 10:05:14 INFO alert sent to on-call
EOF
  printf 'Server: web01\nRegion: uksouth\n' > server.txt
  printf 'Owner: Priya Shah (platform team)\n' > owner.txt
  printf '# Runbook: disk full on web01\n1. Check how full the disk is.\n2. Find the biggest log files.\n' > notes-part1.txt
  printf '3. Move old logs to the backup share.\n4. Confirm the disk is below 80%%.\n' > notes-part2.txt
  next_steps "$(lx_path incident)"
}
lab_lx03_check() {
  check_begin lx03
  local d; d=$(lx_path incident)
  checkn "summary.txt holds exactly the incident line" "echo \"INC-2041: web01 disk at 97%\" > summary.txt (check the percentage in app.log)" \
    content_is "$d/summary.txt" "INC-2041: web01 disk at 97%"
  checkn "runbook.txt is part 1 followed by part 2" "one command: cat notes-part1.txt notes-part2.txt > runbook.txt" \
    sh -c "cat '$d/notes-part1.txt' '$d/notes-part2.txt' | cmp -s - '$d/runbook.txt'"
  checkn "The original files are unchanged" "ks-lab start lx03 puts them back. > replaces a file's contents, so point it at a new file" \
    sh -c "grep -q 'writes failing' '$d/app.log' && grep -q 'Find the biggest' '$d/notes-part1.txt' && grep -q 'below 80' '$d/notes-part2.txt'"
  check_end lx03
}
lab_lx03_hints() {
cat <<'EOF'
cat app.log prints the whole log. The ERROR line has the number you need.
echo "some text" > file writes that text into a file, creating it if it doesn't exist.
cat can read two files in one go, and > sends what it prints into a new file: cat a b > c.
EOF
}
lab_lx03_solution() {
cat <<'EOF'

  cd ~/kloudskool-labs/incident
  cat app.log                        # ERROR ... disk /var at 97%
  cat server.txt owner.txt           # owner: Priya Shah
  echo "INC-2041: web01 disk at 97%" > summary.txt
  cat notes-part1.txt notes-part2.txt > runbook.txt
  cat summary.txt runbook.txt
  ks-lab check lx03

EOF
}

# =====================================================================
# lx04  Back up, then clean up  (after 214: rmdir, rm -r, cp, cp -r)
# =====================================================================
lab_lx04_start() {
  lx_need_linux
  backup_dir "$(lx_path backups)"; mkdir -p "$(lx_path backups)"
  lx_fresh cleanup
  mkdir -p config releases/v1.0 releases/v1.1 releases/v1.2 tmp/old-a tmp/old-b
  printf 'server {\n    listen 80;\n    root /var/www/html;\n}\n' > config/nginx.conf
  printf 'APP_ENV=production\nAPP_PORT=80\n' > config/app.env
  for v in 1.0 1.1 1.2; do printf '#!/bin/bash\necho "app v%s"\n' "$v" > "releases/v$v/app.sh"; printf 'release %s\n' "$v" > "releases/v$v/NOTES.txt"; done
  ticket LX04.md <<'EOF'
# LX04: Clean up web01 (ticket OPS-210)

Before anything is deleted:
1. Copy config/nginx.conf to config/nginx.conf.bak (same folder).
2. Copy the whole config folder to ~/kloudskool-labs/backups/config-backup

Then clean up:
3. Remove the empty folders tmp/old-a and tmp/old-b, then tmp itself.
4. Remove the old releases v1.0 and v1.1. Keep v1.2: it's live.
EOF
  next_steps "$(lx_path cleanup)"
}
lab_lx04_check() {
  check_begin lx04
  local c bk; c=$(lx_path cleanup); bk="$(lx_path backups)/config-backup"
  checkn "config/nginx.conf.bak is a copy of nginx.conf" "cp config/nginx.conf config/nginx.conf.bak" \
    same_file "$c/config/nginx.conf" "$c/config/nginx.conf.bak"
  checkn "backups/config-backup holds the config files" "cp -r config ~/kloudskool-labs/backups/config-backup  (a folder needs -r)" \
    sh -c "cmp -s '$c/config/nginx.conf' '$bk/nginx.conf' && cmp -s '$c/config/app.env' '$bk/app.env'"
  checkn "tmp and its empty folders are gone" "rmdir tmp/old-a tmp/old-b, then rmdir tmp" absent "$c/tmp"
  checkn "v1.0 and v1.1 are gone" "they aren't empty, so rmdir refuses: rm -r releases/v1.0 (add -i to be asked first)" \
    sh -c "! test -e '$c/releases/v1.0' && ! test -e '$c/releases/v1.1'"
  checkn "v1.2 and the original config are untouched" "ks-lab start lx04 to start again. Read the path twice before rm -r" \
    sh -c "test -f '$c/releases/v1.2/app.sh' && test -f '$c/releases/v1.2/NOTES.txt' && test -f '$c/config/nginx.conf' && test -f '$c/config/app.env'"
  check_end lx04
}
lab_lx04_hints() {
cat <<'EOF'
Backups first, deletes last. cp copies a file; a folder needs cp -r.
rmdir only removes empty folders, which makes it the safe choice for tmp. For folders with files in, it's rm -r.
cp -r config ~/kloudskool-labs/backups/config-backup, then rm -ri releases/v1.0 releases/v1.1 so you confirm each delete.
EOF
}
lab_lx04_solution() {
cat <<'EOF'

  cd ~/kloudskool-labs/cleanup
  cp config/nginx.conf config/nginx.conf.bak
  cp -r config ~/kloudskool-labs/backups/config-backup
  rmdir tmp/old-a tmp/old-b
  rmdir tmp
  rm -ri releases/v1.0 releases/v1.1      # answer y to each question
  ls -R
  ks-lab check lx04

EOF
}

# =====================================================================
# lx05  Edit the config  (after 216: vim, nano)
# =====================================================================
LX05_APP='# NovaTech app settings
ENVIRONMENT=staging
PORT=8080
DEBUG=true
LOG_PATH=/var/log/staging/app.log
DB_HOST=db.staging.novatech.internal'
LX05_APP_DONE='# NovaTech app settings
ENVIRONMENT=production
PORT=80
LOG_PATH=/var/log/production/app.log
DB_HOST=db.production.novatech.internal'
LX05_MOTD='Welcome to web01 (NovaTech production)
TEMPORARY: remove before go-live
Unauthorised access is prohibited'
LX05_MOTD_DONE='Welcome to web01 (NovaTech production)
Unauthorised access is prohibited
Maintenance window: Sundays 02:00-04:00 UTC'
lab_lx05_start() {
  lx_need_linux
  lx_fresh editors
  printf '%s\n' "$LX05_APP" > app.conf
  printf '%s\n' "$LX05_MOTD" > motd.txt
  next_steps "$(lx_path editors)"
}
lab_lx05_check() {
  check_begin lx05
  local d; d=$(lx_path editors)
  checkn "app.conf says production everywhere, not staging" "in vim: :%s/staging/production/g then :wq" \
    sh -c "grep -q 'production' '$d/app.conf' && ! grep -q 'staging' '$d/app.conf'"
  checkn "app.conf has no DEBUG line" "in vim, put the cursor on the DEBUG line and press dd" file_lacks "$d/app.conf" 'DEBUG'
  checkn "app.conf says PORT=80" "in vim, i to insert, fix the number, Esc, then :wq" file_has "$d/app.conf" '^PORT=80$'
  checkn "app.conf matches the ticket exactly" "compare with the 'After' box on the lab page. Nothing else should change" \
    content_is "$d/app.conf" "$LX05_APP_DONE"
  checkn "motd.txt matches the ticket exactly" "in nano: Ctrl+K cuts the TEMPORARY line; type the new line at the end; Ctrl+X, Y, Enter" \
    content_is "$d/motd.txt" "$LX05_MOTD_DONE"
  checkn "No vim swap files left behind" "a .swp file means vim is still open somewhere or was closed badly. Close vim with :wq or :q!, then delete the .swp file with rm" \
    no_swap_files "$d"
  check_end lx05
}
lab_lx05_hints() {
cat <<'EOF'
vim starts in normal mode: press i to type, Esc to stop. :wq saves and quits; :q! quits without saving.
In normal mode: dd deletes the line under the cursor, :%s/old/new/g replaces every match. nano lets you type straight away.
nano: Ctrl+K cuts the line the cursor is on. Ctrl+X, then Y, then Enter saves and exits.
EOF
}
lab_lx05_solution() {
cat <<'EOF'

  cd ~/kloudskool-labs/editors
  vim app.conf
    :%s/staging/production/g     (Enter)
    move to the DEBUG line, dd
    move to PORT=8080, i, change it to 80, Esc
    :wq
  nano motd.txt
    put the cursor on the TEMPORARY line, Ctrl+K
    go to the end, type: Maintenance window: Sundays 02:00-04:00 UTC
    Ctrl+X, Y, Enter
  cat app.conf motd.txt
  ks-lab check lx05

EOF
}

# =====================================================================
# lx06  Root-owned files and moving things  (after 218: sudo, mv)
# =====================================================================
lx_clean_etc() {   # remove /etc/novatech so a lab starts clean
  if [ -e /etc/novatech ]; then
    lx_sudo "remove the old /etc/novatech from a previous attempt"
    sudo rm -rf /etc/novatech
  fi
}
lab_lx06_start() {
  lx_need_linux
  lx_clean_etc
  lx_fresh ops
  mkdir -p scripts docs old-docs
  printf '#!/bin/bash\necho "deploying web01"\n' > scripts/deploy_v2.sh
  printf 'Handover notes for web01\n' > notes.txt
  printf 'Old wiki export\n' > old-docs/wiki.txt
  ticket LX06.md <<'EOF'
# LX06: Config and tidy-up on web01

1. Check your user can use sudo.
2. Create the folder /etc/novatech
3. Create /etc/novatech/app.env containing exactly these two lines:
   APP_ENV=production
   APP_PORT=80
4. In ~/kloudskool-labs/ops:
   - rename scripts/deploy_v2.sh to scripts/deploy.sh
   - move notes.txt into docs/
   - rename the folder old-docs to archive
EOF
  next_steps "$(lx_path ops)"
}
lab_lx06_check() {
  check_begin lx06
  local o; o=$(lx_path ops)
  checkn "/etc/novatech exists" "a normal user can't create folders in /etc: sudo mkdir /etc/novatech" is_dir /etc/novatech
  checkn "/etc/novatech/app.env has the two lines" "sudo nano /etc/novatech/app.env (sudo in front of the editor, too)" \
    content_is /etc/novatech/app.env "$(printf 'APP_ENV=production\nAPP_PORT=80')"
  checkn "app.env is owned by root" "create it with sudo, not in your home folder" owner_is /etc/novatech/app.env root
  checkn "scripts/deploy.sh exists and deploy_v2.sh is gone" "mv renames: mv scripts/deploy_v2.sh scripts/deploy.sh" \
    sh -c "test -f '$o/scripts/deploy.sh' && ! test -e '$o/scripts/deploy_v2.sh'"
  checkn "notes.txt is inside docs" "mv notes.txt docs/" sh -c "test -f '$o/docs/notes.txt' && ! test -e '$o/notes.txt'"
  checkn "old-docs is now called archive, with its file" "mv old-docs archive" \
    sh -c "test -f '$o/archive/wiki.txt' && ! test -e '$o/old-docs'"
  check_end lx06
}
lab_lx06_hints() {
cat <<'EOF'
groups $(whoami) should list sudo. touch /etc/test gives Permission denied: that's expected without sudo.
Put sudo in front of every command that writes under /etc, including the editor: sudo nano /etc/novatech/app.env
mv does both jobs: mv old-name new-name renames, mv file folder/ moves.
EOF
}
lab_lx06_solution() {
cat <<'EOF'

  groups $(whoami)
  sudo mkdir /etc/novatech
  sudo nano /etc/novatech/app.env      # type the two lines, Ctrl+X, Y, Enter
  cat /etc/novatech/app.env
  cd ~/kloudskool-labs/ops
  mv scripts/deploy_v2.sh scripts/deploy.sh
  mv notes.txt docs/
  mv old-docs archive
  ks-lab check lx06

EOF
}

# =====================================================================
# lxc1  Stage gate: prepare release 1.3  (Labs 01-06, no hints)
# =====================================================================
lab_lxc1_start() {
  lx_need_linux
  lx_clean_etc
  lx_fresh release
  mkdir -p config releases/v1.0 releases/v1.2 archive
  printf 'APP_NAME=web01\nVERSION=1.2\nTLS_MIN=1.0\n' > config/app.conf
  printf '#!/bin/bash\necho "app v1.0"\n' > releases/v1.0/app.sh
  printf '#!/bin/bash\necho "app v1.2"\n' > releases/v1.2/app.sh
  printf 'draft notes, do not ship\n' > releases/v1.3-notes-draft.txt
  ticket LXC1.md <<'EOF'
# REL-300: Prepare release 1.3 on web01

Work in ~/kloudskool-labs/release.
1. Create the folder releases/v1.3/config
2. Copy config/app.conf into releases/v1.3/config/
3. In releases/v1.3/config/app.conf, change VERSION=1.2 to VERSION=1.3 and TLS_MIN=1.0 to TLS_MIN=1.2.
   Leave config/app.conf as it is.
4. Create releases/v1.3/NOTES.txt containing exactly: v1.3: TLS 1.2 minimum
5. Move releases/v1.3-notes-draft.txt into archive/
6. Remove releases/v1.0. Keep v1.2.
7. Create /etc/novatech/release containing exactly one line: 1.3
EOF
  next_steps "$(lx_path release)"
}
lab_lxc1_check() {
  check_begin lxc1
  local r; r=$(lx_path release)
  checkn "releases/v1.3/config/app.conf exists" "mkdir -p, then cp" is_file "$r/releases/v1.3/config/app.conf"
  checkn "The v1.3 copy says VERSION=1.3 and TLS_MIN=1.2" "edit the copy, not the original" \
    content_is "$r/releases/v1.3/config/app.conf" "$(printf 'APP_NAME=web01\nVERSION=1.3\nTLS_MIN=1.2')"
  checkn "The original config/app.conf is unchanged" "ks-lab start lxc1 to start again" \
    content_is "$r/config/app.conf" "$(printf 'APP_NAME=web01\nVERSION=1.2\nTLS_MIN=1.0')"
  checkn "NOTES.txt says exactly: v1.3: TLS 1.2 minimum" "check spelling and the colon" \
    content_is "$r/releases/v1.3/NOTES.txt" "v1.3: TLS 1.2 minimum"
  checkn "The draft notes are in archive" "move, don't copy" \
    sh -c "test -f '$r/archive/v1.3-notes-draft.txt' && ! test -e '$r/releases/v1.3-notes-draft.txt'"
  checkn "v1.0 is gone and v1.2 is still there" "v1.0 isn't empty" \
    sh -c "! test -e '$r/releases/v1.0' && test -f '$r/releases/v1.2/app.sh'"
  checkn "/etc/novatech/release says 1.3" "it's under /etc" content_is /etc/novatech/release "1.3"
  check_end lxc1
}
lab_lxc1_hints() {
cat <<'EOF'
Which lab did each step come from? Folders (02), copy and remove (04), edit (05), echo into a file (03), sudo and mv (06).
EOF
}
lab_lxc1_solution() {
cat <<'EOF'

  cd ~/kloudskool-labs/release
  mkdir -p releases/v1.3/config
  cp config/app.conf releases/v1.3/config/
  nano releases/v1.3/config/app.conf          # VERSION=1.3, TLS_MIN=1.2
  echo "v1.3: TLS 1.2 minimum" > releases/v1.3/NOTES.txt
  mv releases/v1.3-notes-draft.txt archive/
  rm -r releases/v1.0
  sudo mkdir -p /etc/novatech
  sudo nano /etc/novatech/release             # one line: 1.3
  ks-lab check lxc1

EOF
}

# =====================================================================
# lx07  Deploy the web server  (after 220: apt, curl, ps aux | grep, systemctl)
# =====================================================================
lab_lx07_start() {
  lx_need_linux
  state_set lx07-event 0
  ticket LX07.md <<'EOF'
# LX07: Put a web server on web01

1. Refresh the package list, then install nginx.
2. Prove it works: curl localhost shows "Welcome to nginx".
3. Find nginx's processes with ps aux and grep. Note the master process's PID.
4. Check the service with systemctl status nginx.
5. Run: ks-lab event lx07b   (something happens to nginx)
6. Work out what happened and get the site back.
7. Replace the home page: create /var/www/html/index.html containing exactly:
   NovaTech web01 is up
8. curl localhost now shows that line. Run: ks-lab check lx07
EOF
  say ""
  say "  This lab works on the VM itself, so there's no lab folder."
  say "  The ticket is in $KS_LABS/tickets/LX07.md. Follow the lab page."
  say ""
}
event_lx07b() {
  pkg_installed nginx || die "install nginx first (step 1)."
  lx_sudo "simulate the problem"
  sudo systemctl stop nginx
  state_set lx07-event 1
  say ""
  say "  Something has happened to nginx on web01."
  say "  Users report the site isn't loading. Find out why and fix it."
  say ""
}
lab_lx07_check() {
  check_begin lx07
  checkn "nginx is installed" "sudo apt update, then sudo apt install -y nginx" pkg_installed nginx
  checkn "You ran the event (step 5)" "run: ks-lab event lx07b" test "$(state_get lx07-event 0)" = "1"
  checkn "The nginx service is running" "systemctl status nginx shows inactive (dead)? sudo systemctl start nginx" svc_active nginx
  checkn "The site shows: NovaTech web01 is up" "sudo nano /var/www/html/index.html, type the line, save. Then curl localhost" \
    page_has "NovaTech web01 is up"
  check_end lx07
}
lab_lx07_hints() {
cat <<'EOF'
sudo apt update refreshes the list, sudo apt install -y nginx installs it. curl localhost fetches the page.
After the event, curl fails. systemctl status nginx tells you whether the service is running, and since when it isn't.
sudo systemctl start nginx brings it back. The page lives in /var/www/html, which only root can write to.
EOF
}
lab_lx07_solution() {
cat <<'EOF'

  sudo apt update
  sudo apt install -y nginx
  curl localhost                       # Welcome to nginx
  ps aux | grep nginx                  # one master process, some workers
  systemctl status nginx               # active (running)
  ks-lab event lx07b
  curl localhost                       # Failed to connect
  systemctl status nginx               # inactive (dead)
  sudo systemctl start nginx
  sudo nano /var/www/html/index.html   # NovaTech web01 is up
  curl localhost
  ks-lab check lx07

EOF
}

# =====================================================================
# lx08  Onboard a teammate  (after 222: adduser, groupadd, usermod -aG, su -, chmod)
# =====================================================================
lab_lx08_start() {
  lx_need_linux
  if user_exists priya || group_exists platform; then
    lx_sudo "remove the priya user and platform group from a previous attempt"
    user_exists priya && sudo deluser --remove-home priya >/dev/null 2>&1
    group_exists platform && sudo groupdel platform >/dev/null 2>&1
  fi
  lx_fresh perms
  printf '#!/bin/bash\necho "deploying"\n' > deploy.sh
  printf 'DB_PASSWORD=not-a-real-password\n' > secrets.env
  printf '# Platform runbooks\n' > README.md
  printf '#!/bin/bash\necho "checking disk"\n' > check-disk.sh
  chmod 644 deploy.sh secrets.env README.md check-disk.sh
  ticket LX08.md <<'EOF'
# LX08: Priya joins the platform team

Accounts:
1. Create a user called priya (any password you'll remember; full name Priya Shah).
2. Create a group called platform.
3. Add priya to platform without removing her from any group she's already in. Add yourself too.
4. Switch to priya's account, prove who you are, then exit back.

Permissions, in ~/kloudskool-labs/perms:
5. deploy.sh     owner: read, write, execute   group: read, execute   others: nothing
6. secrets.env   owner: read, write            group: nothing          others: nothing
7. README.md     owner: read, write            group: read             others: read
8. check-disk.sh add execute for the owner only; leave everything else as it is
EOF
  next_steps "$(lx_path perms)"
}
lab_lx08_check() {
  check_begin lx08
  local p; p=$(lx_path perms)
  checkn "User priya exists" "sudo adduser priya" user_exists priya
  checkn "Group platform exists" "sudo groupadd platform" group_exists platform
  checkn "priya is in platform" "sudo usermod -aG platform priya   (the a means add)" in_group priya platform
  checkn "You are in platform too" "sudo usermod -aG platform \$(whoami)" in_group "$(id -un)" platform
  checkn "deploy.sh is rwxr-x---" "chmod 750 deploy.sh  (7=rwx, 5=r-x, 0=none)" mode_is_lx "$p/deploy.sh" 750
  checkn "secrets.env is rw-------" "chmod 600 secrets.env" mode_is_lx "$p/secrets.env" 600
  checkn "README.md is rw-r--r--" "chmod 644 README.md" mode_is_lx "$p/README.md" 644
  checkn "check-disk.sh is rwxr--r--" "chmod u+x check-disk.sh adds execute for the owner only" mode_is_lx "$p/check-disk.sh" 744
  check_end lx08
}
lab_lx08_hints() {
cat <<'EOF'
sudo adduser priya asks a few questions; Enter skips the optional ones. sudo groupadd platform makes the group.
sudo usermod -aG platform priya. Without -a, Linux replaces her groups instead of adding one. groups priya shows the result.
Numbers: read 4, write 2, execute 1. Owner, group, others: rwxr-x--- is 750. chmod u+x adds execute for the owner only.
EOF
}
lab_lx08_solution() {
cat <<'EOF'

  sudo adduser priya
  sudo groupadd platform
  sudo usermod -aG platform priya
  sudo usermod -aG platform $(whoami)
  groups priya
  sudo su - priya
  whoami
  exit
  cd ~/kloudskool-labs/perms
  chmod 750 deploy.sh
  chmod 600 secrets.env
  chmod 644 README.md
  chmod u+x check-disk.sh
  ls -l
  ks-lab check lx08

EOF
}

# =====================================================================
# lx09  Your first ops script  (after 224: env vars, .bashrc, shebang, chmod, PATH, /usr/local/bin)
# =====================================================================
lab_lx09_start() {
  lx_need_linux
  ticket LX09.md <<'EOF'
# LX09: server-info.sh

1. Make an environment variable TEAM with the value platform, so it survives logging out.
2. Create the script ~/bin/server-info.sh. It must:
   - start with the bash shebang
   - print   Team: <the value of TEAM>
   - print   Host: <the value of HOSTNAME>
3. Make the script runnable by you only: read, write and execute for you; nothing for group and others.
4. Make ~/bin part of your PATH permanently, so typing server-info.sh runs it from any folder.
5. Share it: copy it to /usr/local/bin and let everyone read and run it (rwxr-xr-x).
EOF
  say ""
  say "  This lab works in your home folder (~/.bashrc and ~/bin), not a lab folder."
  say "  The ticket is in $KS_LABS/tickets/LX09.md. Follow the lab page."
  say ""
}
lab_lx09_check() {
  check_begin lx09
  local s="$HOME/bin/server-info.sh"
  checkn "~/.bashrc exports TEAM=platform" "add  export TEAM=\"platform\"  at the end of ~/.bashrc (nano ~/.bashrc), then source ~/.bashrc" \
    bashrc_has '^[[:space:]]*export[[:space:]]+TEAM="?platform"?[[:space:]]*$'
  checkn "A new terminal knows TEAM" "save ~/.bashrc and check the line has no typos" login_shell_has 'echo "$TEAM"' '^platform$'
  checkn "~/bin/server-info.sh exists" "mkdir ~/bin, then nano ~/bin/server-info.sh" is_file "$s"
  checkn "It starts with #!/bin/bash" "the shebang must be the very first line" sh -c "head -n1 '$s' | grep -qx '#!/bin/bash'"
  checkn "It prints Team: and Host: lines" "echo \"Team: \$TEAM\" and echo \"Host: \$HOSTNAME\"" \
    sh -c "TEAM=platform HOSTNAME=web01 bash '$s' | grep -qx 'Team: platform' && TEAM=platform HOSTNAME=web01 bash '$s' | grep -qx 'Host: web01'"
  checkn "Only you can use it: rwx------" "chmod 700 ~/bin/server-info.sh" mode_is_lx "$s" 700
  checkn "~/bin is on your PATH in new terminals" "add  export PATH=\"\$HOME/bin:\$PATH\"  to ~/.bashrc, then source ~/.bashrc" \
    login_shell_has 'command -v server-info.sh' "^$HOME/bin/server-info.sh$"
  checkn "/usr/local/bin/server-info.sh exists" "sudo cp ~/bin/server-info.sh /usr/local/bin/" is_file /usr/local/bin/server-info.sh
  checkn "Everyone can read and run the shared copy: rwxr-xr-x" "the copy kept your 700. A script must be readable to run: sudo chmod 755 /usr/local/bin/server-info.sh" \
    mode_is_lx /usr/local/bin/server-info.sh 755
  check_end lx09
}
lab_lx09_hints() {
cat <<'EOF'
NAME=value only lasts until you close the terminal. To keep it, add  export TEAM="platform"  to ~/.bashrc and run source ~/.bashrc.
First line #!/bin/bash, then echo lines. ./ runs it from its folder once you've given yourself execute: chmod 700.
For PATH, add  export PATH="$HOME/bin:$PATH"  to ~/.bashrc. Copy with sudo cp, then sudo chmod 755: others need read as well as execute.
EOF
}
lab_lx09_solution() {
cat <<'EOF'

  nano ~/.bashrc
    add at the end:
      export TEAM="platform"
      export PATH="$HOME/bin:$PATH"
  source ~/.bashrc
  mkdir -p ~/bin
  nano ~/bin/server-info.sh
      #!/bin/bash
      echo "Team: $TEAM"
      echo "Host: $HOSTNAME"
  chmod 700 ~/bin/server-info.sh
  server-info.sh
  sudo cp ~/bin/server-info.sh /usr/local/bin/
  sudo chmod 755 /usr/local/bin/server-info.sh   # +x alone gives 711: others can't read it
  ls -l /usr/local/bin/server-info.sh
  ks-lab check lx09

EOF
}

# =====================================================================
# lx10  Log in with keys, then revoke one  (after 225: ssh, ssh-keygen, ssh-copy-id, ssh -i)
# =====================================================================
lab_lx10_start() {
  lx_need_linux
  ticket LX10.md <<'EOF'
# LX10: Key-based SSH on web01, then a stolen key

1. Make sure the SSH server is installed and running on the VM.
2. SSH from the VM to itself with your password: ssh <your-user>@localhost. Type yes, log in, whoami, exit.
3. Create a key pair (ssh-keygen, the default file), copy the public key to the server (ssh-copy-id),
   and log in with ssh -i ~/.ssh/id_ed25519 <your-user>@localhost. No password this time.
4. Incident: your id_ed25519 private key was on a laptop that's been stolen.
   - Create a new key pair in ~/.ssh/id_ed25519_new
   - Copy the new public key to the server
   - Remove the OLD public key from ~/.ssh/authorized_keys
   - Prove the old key no longer gets in, and the new one does.
EOF
  say ""
  say "  This lab works on the VM itself. The ticket is in $KS_LABS/tickets/LX10.md."
  say ""
}
lab_lx10_check() {
  check_begin lx10
  local old="$HOME/.ssh/id_ed25519" new="$HOME/.ssh/id_ed25519_new" ak="$HOME/.ssh/authorized_keys"
  checkn "The SSH server is installed" "sudo apt install -y openssh-server" pkg_installed openssh-server
  checkn "The ssh service is running" "sudo systemctl start ssh" sh -c "systemctl is-active --quiet ssh || systemctl is-active --quiet sshd"
  checkn "Your first key pair exists" "ssh-keygen (press Enter for the default file)" sh -c "test -f '$old' && test -f '$old.pub'"
  checkn "Your new key pair exists" "ssh-keygen -f ~/.ssh/id_ed25519_new" sh -c "test -f '$new' && test -f '$new.pub'"
  checkn "The new public key is in authorized_keys" "ssh-copy-id -i ~/.ssh/id_ed25519_new.pub \$(whoami)@localhost" \
    sh -c "grep -qF \"\$(cut -d' ' -f2 '$new.pub')\" '$ak'"
  checkn "The old public key is gone from authorized_keys" "nano ~/.ssh/authorized_keys and delete the line that matches ~/.ssh/id_ed25519.pub" \
    sh -c "test -f '$old.pub' && ! grep -qF \"\$(cut -d' ' -f2 '$old.pub')\" '$ak'"
  checkn "The new key logs you in" "ssh -i ~/.ssh/id_ed25519_new \$(whoami)@localhost" ssh_ok "$new"
  checkn "The old key no longer gets in" "remove its line from authorized_keys" ssh_refused "$old"
  check_end lx10
}
lab_lx10_hints() {
cat <<'EOF'
sudo systemctl status ssh shows whether the SSH server is running. On the VM, localhost means the VM itself.
ssh-keygen makes a pair: the .pub file is public and goes to the server; the other file is the private key and never leaves you.
ssh-copy-id -i <key>.pub adds a public key to ~/.ssh/authorized_keys. Revoking means deleting that key's line from the file.
EOF
}
lab_lx10_solution() {
cat <<'EOF'

  sudo apt install -y openssh-server
  sudo systemctl status ssh
  ssh $(whoami)@localhost              # yes, password, whoami, exit
  ssh-keygen                           # Enter, Enter, Enter
  ssh-copy-id $(whoami)@localhost
  ssh -i ~/.ssh/id_ed25519 $(whoami)@localhost     # no password; exit
  ssh-keygen -f ~/.ssh/id_ed25519_new
  ssh-copy-id -i ~/.ssh/id_ed25519_new.pub $(whoami)@localhost
  cat ~/.ssh/id_ed25519.pub            # note the end of the line
  nano ~/.ssh/authorized_keys          # delete the line that matches it
  ssh -i ~/.ssh/id_ed25519_new $(whoami)@localhost # gets in; exit
  ssh -i ~/.ssh/id_ed25519 $(whoami)@localhost     # asks for a password: Ctrl+C
  ks-lab check lx10

EOF
}

# =====================================================================
# lx11  Bonus: links  (after 226: ln, ln -s)
# =====================================================================
lab_lx11_start() {
  lx_need_linux
  lx_fresh links
  mkdir -p releases/v1.2 releases/v1.3 config
  printf 'app v1.2\n' > releases/v1.2/VERSION
  printf 'app v1.3\n' > releases/v1.3/VERSION
  printf 'APP_ENV=production\n' > config/app.conf
  ln -s releases/v1.2 current
  ln -s /var/log/novatech-old logs
  next_steps "$(lx_path links)"
}
lab_lx11_check() {
  check_begin lx11
  local l; l=$(lx_path links)
  checkn "current is a soft link to releases/v1.3" "rm current, then ln -s releases/v1.3 current" \
    sh -c "test -L '$l/current' && test \"\$(readlink '$l/current')\" = 'releases/v1.3' -o \"\$(readlink '$l/current')\" = 'releases/v1.3/'"
  checkn "app.conf.link is a hard link to config/app.conf" "ln config/app.conf app.conf.link  (no -s)" \
    sh -c "test ! -L '$l/app.conf.link' && test \"\$(stat -c %i '$l/app.conf.link')\" = \"\$(stat -c %i '$l/config/app.conf')\""
  checkn "logs is no longer a broken link" "ls -l logs shows where it points. rm logs, then ln -s /var/log logs" \
    sh -c "test -L '$l/logs' && test -e '$l/logs'"
  check_end lx11
}
lab_lx11_hints() {
cat <<'EOF'
ls -l shows links with an arrow: name -> target. A link whose target doesn't exist is broken.
ln -s target name makes a soft link. ln target name (no -s) makes a hard link: a second name for the same file.
rm current removes the link, not the folder it points to. Then ln -s releases/v1.3 current.
EOF
}
lab_lx11_solution() {
cat <<'EOF'

  cd ~/kloudskool-labs/links
  ls -l
  rm current
  ln -s releases/v1.3 current
  ln config/app.conf app.conf.link
  ls -li config/app.conf app.conf.link     # same inode number
  rm logs
  ln -s /var/log logs
  ks-lab check lx11

EOF
}

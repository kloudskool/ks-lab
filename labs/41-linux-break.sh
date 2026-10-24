# shellcheck shell=bash
# Linux Break Room (lxt01-lxt12) and final assessment (lxfinal).
# Started with:  ks-lab break lx3   (or ks-lab start lxt03)

lxb_start() {   # lxb_start <nn> : fresh folder break-lxtNN, cd into it
  lx_need_linux
  lx_fresh "break-lxt$1"
}
lxb_ready() {   # lxb_ready <nn> <ticket text...>
  local nn="$1"; shift
  printf '%s\n' "$@" | ticket "LXT$nn.md"
  say ""
  say "  Broken on purpose. Read the ticket:  cat $KS_LABS/tickets/LXT$nn.md"
  say "  Work in:  cd $(lx_path "break-lxt$nn")"
  say "  When it's fixed:  ks-lab check lxt$nn"
  say ""
}

# ---------- T1: Permission denied ----------
lab_lxt01_start() {
  lxb_start 01
  printf '#!/bin/bash\necho "Backup of web01 complete"\n' > backup.sh
  chmod 644 backup.sh
  lxb_ready 01 "# LXT01: ./backup.sh says Permission denied" "" \
    "The nightly backup script in break-lxt01 won't run:" "  ./backup.sh: Permission denied" \
    "Make it runnable by its owner. Don't open it up to everyone (no 777)."
}
lab_lxt01_check() {
  check_begin lxt01
  local f; f="$(lx_path break-lxt01)/backup.sh"
  checkn "The owner can execute backup.sh" "ls -l shows rw-: there's no x for the owner" sh -c "test \"\$(stat -c %A '$f' | cut -c4)\" = x"
  checkn "Others can't write to it" "777 lets anyone change your script. chmod 755 or chmod u+x is enough" \
    sh -c "test \"\$(stat -c %A '$f' | cut -c9)\" = -"
  checkn "./backup.sh runs" "run it from inside break-lxt01" sh -c "cd '$(lx_path break-lxt01)' && ./backup.sh | grep -q complete"
  check_end lxt01
}
lab_lxt01_hints() { printf '%s\n' "Permission denied on a script you own almost always means a missing x. ls -l shows it." "chmod u+x adds execute for the owner only." "chmod u+x backup.sh, then ./backup.sh"; }
lab_lxt01_solution() { printf '\n  cd ~/kloudskool-labs/break-lxt01\n  ls -l backup.sh        # -rw-r--r--\n  chmod u+x backup.sh\n  ./backup.sh\n\n'; }

# ---------- T2: a shared script only root can run ----------
lab_lxt02_start() {
  lxb_start 02
  lx_sudo "install a shared script in /usr/local/bin"
  printf '#!/bin/bash\necho "web01 status: OK"\n' | sudo tee /usr/local/bin/novatech-status >/dev/null
  sudo chmod 700 /usr/local/bin/novatech-status
  lxb_ready 02 "# LXT02: novatech-status: Permission denied" "" \
    "The team's status script was installed in /usr/local/bin so everyone could use it." \
    "Running  novatech-status  gives Permission denied for everyone except root." \
    "Make it runnable by every user, without giving anyone write access."
}
lab_lxt02_check() {
  check_begin lxt02
  local f=/usr/local/bin/novatech-status
  checkn "Others can read and execute novatech-status" "ls -l $f shows rwx------. A script needs read and execute: sudo chmod 755 $f" \
    sh -c "test \"\$(stat -c %A $f | cut -c8-10)\" = r-x"
  checkn "Only root can change it" "group and others mustn't have w" sh -c "test \"\$(stat -c %A $f | cut -c6)\" = - && test \"\$(stat -c %A $f | cut -c9)\" = - && test \"\$(stat -c %U $f)\" = root"
  checkn "novatech-status runs for you" "type novatech-status" sh -c "novatech-status | grep -q OK"
  check_end lxt02
}
lab_lxt02_hints() { printf '%s\n' "ls -l /usr/local/bin/novatech-status: who owns it, and what can others do?" "A bash script has to be readable as well as executable. Others need r and x." "sudo chmod 755 /usr/local/bin/novatech-status"; }
lab_lxt02_solution() { printf '\n  ls -l /usr/local/bin/novatech-status     # -rwx------ root\n  sudo chmod 755 /usr/local/bin/novatech-status\n  novatech-status\n\n'; }

# ---------- T3: variable lost after logout ----------
lab_lxt03_start() {
  lxb_start 03
  lxb_ready 03 "# LXT03: REGION is empty again" "" \
    "Every morning the deploy scripts fail because REGION is empty." \
    "Yesterday someone typed  REGION=uksouth  in the terminal and it worked until they logged out." \
    "Make REGION=uksouth stick for every new terminal you open."
}
lab_lxt03_check() {
  check_begin lxt03
  checkn "~/.bashrc exports REGION=uksouth" "add  export REGION=\"uksouth\"  at the end of ~/.bashrc" \
    bashrc_has '^[[:space:]]*export[[:space:]]+REGION="?uksouth"?[[:space:]]*$'
  checkn "A new terminal knows REGION" "save the file, then source ~/.bashrc" login_shell_has 'echo "$REGION"' '^uksouth$'
  check_end lxt03
}
lab_lxt03_hints() { printf '%s\n' "A variable you type in the terminal dies with that terminal (lesson 223)." "Variables that survive live in ~/.bashrc, with export in front." "nano ~/.bashrc, add export REGION=\"uksouth\", save, source ~/.bashrc"; }
lab_lxt03_solution() { printf '\n  nano ~/.bashrc                  # add: export REGION="uksouth"\n  source ~/.bashrc\n  bash -c '"'"'echo $REGION'"'"'       # uksouth\n\n'; }

# ---------- T4: site down ----------
lab_lxt04_start() {
  lxb_start 04
  pkg_installed nginx || die "this scenario needs nginx. Do Lab 07 first (sudo apt install -y nginx)."
  lx_sudo "break the web server"
  sudo systemctl stop nginx
  lxb_ready 04 "# LXT04: web01 is down" "" "Monitoring says http://localhost on web01 stopped answering." \
    "Nobody changed the code. Find out what's wrong and get the site back."
}
lab_lxt04_check() {
  check_begin lxt04
  checkn "nginx is running" "systemctl status nginx, then sudo systemctl start nginx" svc_active nginx
  checkn "localhost answers" "curl localhost" sh -c "curl -s --max-time 5 -o /dev/null http://localhost/"
  check_end lxt04
}
lab_lxt04_hints() { printf '%s\n' "curl localhost confirms the symptom. What does the service say about itself?" "systemctl status nginx shows inactive (dead)." "sudo systemctl start nginx"; }
lab_lxt04_solution() { printf '\n  curl localhost              # Failed to connect\n  systemctl status nginx      # inactive (dead)\n  sudo systemctl start nginx\n  curl localhost\n\n'; }

# ---------- T5: runaway process ----------
lab_lxt05_start() {
  lxb_start 05
  printf '#!/bin/bash\n# report generator stuck in a loop\nwhile true; do sleep 1; done\n' > report-gen.sh
  chmod 755 report-gen.sh
  pkill -u "$(id -u)" -f break-lxt05/report-gen.sh 2>/dev/null
  setsid nohup "$(lx_path break-lxt05)/report-gen.sh" >/dev/null 2>&1 < /dev/null &
  lxb_ready 05 "# LXT05: a report job won't finish" "" \
    "A report generator from break-lxt05 has been running for hours and should have stopped long ago." \
    "Find its process and stop it. Don't delete the script: the team needs it to find the bug."
}
lab_lxt05_check() {
  check_begin lxt05
  checkn "report-gen.sh is no longer running" "ps aux | grep report-gen shows its PID (second column). kill <PID>" no_proc "break-lxt05/report-gen.sh"
  checkn "The script is still there" "ks-lab break lx5 to start again" is_file "$(lx_path break-lxt05)/report-gen.sh"
  check_end lxt05
}
lab_lxt05_hints() { printf '%s\n' "ps aux lists every process. Too much? Pipe it into grep." "ps aux | grep report-gen. The PID is the second column. Ignore the line for grep itself." "kill <PID> (sudo kill if it isn't yours), then ps aux | grep report-gen again"; }
lab_lxt05_solution() { printf '\n  ps aux | grep report-gen\n  kill <PID>                  # the number in the second column\n  ps aux | grep report-gen    # only the grep line is left\n\n'; }

# ---------- T6: can't edit a root-owned file ----------
lab_lxt06_start() {
  lxb_start 06
  lx_sudo "create a root-owned config file"
  sudo mkdir -p /etc/novatech
  printf 'MAINTENANCE=on\n' | sudo tee /etc/novatech/maintenance.conf >/dev/null
  lxb_ready 06 "# LXT06: can't switch maintenance mode off" "" \
    "Maintenance finished, but /etc/novatech/maintenance.conf still says MAINTENANCE=on." \
    "Your colleague tried nano and got: [ Error writing ... Permission denied ]" \
    "Change it to MAINTENANCE=off. The file must stay owned by root."
}
lab_lxt06_check() {
  check_begin lxt06
  checkn "maintenance.conf says MAINTENANCE=off" "sudo nano /etc/novatech/maintenance.conf" content_is /etc/novatech/maintenance.conf "MAINTENANCE=off"
  checkn "It's still owned by root" "don't copy it to your home and back; edit it in place with sudo" owner_is /etc/novatech/maintenance.conf root
  check_end lxt06
}
lab_lxt06_hints() { printf '%s\n' "ls -l /etc/novatech/maintenance.conf: who owns it?" "Only root can write there. The editor needs elevated privileges, not just you." "sudo nano /etc/novatech/maintenance.conf"; }
lab_lxt06_solution() { printf '\n  ls -l /etc/novatech/maintenance.conf\n  sudo nano /etc/novatech/maintenance.conf     # on -> off, Ctrl+X, Y, Enter\n  cat /etc/novatech/maintenance.conf\n\n'; }

# ---------- T7: config deleted ----------
lab_lxt07_start() {
  lxb_start 07
  mkdir -p config backups/2026-10-01
  printf 'server {\n    listen 80;\n    server_name web01.novatech.example;\n    root /var/www/html;\n}\n' > backups/2026-10-01/nginx.conf
  printf 'APP_ENV=production\n' > config/app.env
  lxb_ready 07 "# LXT07: nginx.conf was deleted" "" \
    "Someone ran rm on config/nginx.conf in break-lxt07 by mistake. There's no recycle bin." \
    "Last night's backup is in backups/2026-10-01. Put nginx.conf back where it was. Keep the backup."
}
lab_lxt07_check() {
  check_begin lxt07
  local d; d=$(lx_path break-lxt07)
  checkn "config/nginx.conf is back, same as the backup" "cp backups/2026-10-01/nginx.conf config/" same_file "$d/backups/2026-10-01/nginx.conf" "$d/config/nginx.conf"
  checkn "The backup is still there" "copy, don't move" is_file "$d/backups/2026-10-01/nginx.conf"
  check_end lxt07
}
lab_lxt07_hints() { printf '%s\n' "ls -R shows what's in backups." "You want a copy, so the backup survives for next time." "cp backups/2026-10-01/nginx.conf config/"; }
lab_lxt07_solution() { printf '\n  cd ~/kloudskool-labs/break-lxt07\n  ls -R backups\n  cp backups/2026-10-01/nginx.conf config/\n  cat config/nginx.conf\n\n'; }

# ---------- T8: SSH key too open ----------
lab_lxt08_start() {
  lxb_start 08
  pkg_installed openssh-server || die "this scenario needs the SSH server. Do Lab 10 first (sudo apt install -y openssh-server)."
  local k="$HOME/.ssh/kloudskool_break"
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
  rm -f "$k" "$k.pub"
  ssh-keygen -q -t ed25519 -N '' -C kloudskool-break -f "$k"
  touch "$HOME/.ssh/authorized_keys"; chmod 600 "$HOME/.ssh/authorized_keys"
  grep -qF "$(cut -d' ' -f2 "$k.pub")" "$HOME/.ssh/authorized_keys" || cat "$k.pub" >> "$HOME/.ssh/authorized_keys"
  chmod 644 "$k"
  lxb_ready 08 "# LXT08: SSH refuses the key" "" \
    "This used to work:  ssh -i ~/.ssh/kloudskool_break $(id -un)@localhost" \
    "Now it prints WARNING: UNPROTECTED PRIVATE KEY FILE and asks for a password." \
    "Fix it so the key logs you in again. Don't create a new key."
}
lab_lxt08_check() {
  check_begin lxt08
  local k="$HOME/.ssh/kloudskool_break"
  checkn "Only you can read the private key" "the warning says the permissions are too open. chmod 600 ~/.ssh/kloudskool_break" \
    sh -c "test \"\$(stat -c %a '$k')\" = 600 -o \"\$(stat -c %a '$k')\" = 400"
  checkn "The key logs you in" "ssh -i ~/.ssh/kloudskool_break \$(whoami)@localhost" ssh_ok "$k"
  check_end lxt08
}
lab_lxt08_hints() { printf '%s\n' "Read the warning: it names the file and its permissions." "A private key must be readable by you only. ls -l shows -rw-r--r--." "chmod 600 ~/.ssh/kloudskool_break"; }
lab_lxt08_solution() { printf '\n  ls -l ~/.ssh/kloudskool_break        # -rw-r--r--\n  chmod 600 ~/.ssh/kloudskool_break\n  ssh -i ~/.ssh/kloudskool_break $(whoami)@localhost\n\n'; }

# ---------- T9: usermod -G without -a ----------
lab_lxt09_start() {
  lxb_start 09
  lx_sudo "create the user sam and the groups"
  user_exists sam && sudo deluser --remove-home sam >/dev/null 2>&1
  for g in developers oncall platform; do group_exists "$g" || sudo groupadd "$g"; done
  sudo adduser --disabled-password --gecos "Sam Okafor" sam >/dev/null 2>&1 || sudo useradd -m -c "Sam Okafor" sam
  sudo usermod -aG developers sam; sudo usermod -aG oncall sam
  sudo usermod -G platform sam
  lxb_ready 09 "# LXT09: Sam lost his access" "" \
    "Yesterday sam was in the developers and oncall groups. Someone added him to platform with:" \
    "  sudo usermod -G platform sam" \
    "Now he can't reach the developer or on-call folders. He needs all three: developers, oncall and platform."
}
lab_lxt09_check() {
  check_begin lxt09
  checkn "sam is in developers" "sudo usermod -aG developers sam" in_group sam developers
  checkn "sam is in oncall" "sudo usermod -aG oncall sam" in_group sam oncall
  checkn "sam is still in platform" "always use -aG so you add, not replace" in_group sam platform
  check_end lxt09
}
lab_lxt09_hints() { printf '%s\n' "groups sam shows what he has now." "usermod -G without -a replaces the whole list. That's what went wrong." "sudo usermod -aG developers sam, then sudo usermod -aG oncall sam"; }
lab_lxt09_solution() { printf '\n  groups sam                        # sam platform\n  sudo usermod -aG developers sam\n  sudo usermod -aG oncall sam\n  groups sam\n\n'; }

# ---------- T10: rmdir says not empty ----------
lab_lxt10_start() {
  lxb_start 10
  mkdir -p releases/v0.9 releases/v1.0
  printf 'locked by deploy 2026-09-30\n' > releases/v0.9/.lock
  printf '#!/bin/bash\necho "app v1.0"\n' > releases/v1.0/app.sh
  lxb_ready 10 "# LXT10: rmdir says the folder isn't empty" "" \
    "releases/v0.9 in break-lxt10 looks empty: ls shows nothing in it." \
    "But rmdir releases/v0.9 says: Directory not empty." \
    "Find out what's in it, then remove v0.9. v1.0 is live: keep it."
}
lab_lxt10_check() {
  check_begin lxt10
  local d; d=$(lx_path break-lxt10)
  checkn "releases/v0.9 is gone" "ls -a releases/v0.9 shows hidden files. Then rm -r releases/v0.9" absent "$d/releases/v0.9"
  checkn "releases/v1.0 is untouched" "ks-lab break lx10 to start again" is_file "$d/releases/v1.0/app.sh"
  check_end lxt10
}
lab_lxt10_hints() { printf '%s\n' "ls hides files whose names start with a dot." "ls -a releases/v0.9 shows a .lock file. rmdir only removes truly empty folders." "rm -r releases/v0.9 (or rm -ri to be asked first)"; }
lab_lxt10_solution() { printf '\n  cd ~/kloudskool-labs/break-lxt10\n  ls -a releases/v0.9      # .lock\n  cat releases/v0.9/.lock\n  rm -ri releases/v0.9\n  ls releases               # v1.0\n\n'; }

# ---------- T11: mv went wrong ----------
lab_lxt11_start() {
  lxb_start 11
  mkdir -p scripts archive docs
  printf '#!/bin/bash\necho "deploying web01"\n' > archive/deploy.sh.old
  printf 'How we deploy web01\n' > docs/runbook.md
  mv docs scripts/
  lxb_ready 11 "# LXT11: the deploy script is missing" "" \
    "A colleague tidied break-lxt11 with mv and it went wrong:" \
    "  - scripts/deploy.sh ended up as archive/deploy.sh.old" \
    "  - the docs folder ended up inside scripts/" \
    "Put both back: scripts/deploy.sh, and docs/ at the top of break-lxt11 with runbook.md inside."
}
lab_lxt11_check() {
  check_begin lxt11
  local d; d=$(lx_path break-lxt11)
  checkn "scripts/deploy.sh is back" "mv can move and rename in one go: mv archive/deploy.sh.old scripts/deploy.sh" \
    sh -c "test -f '$d/scripts/deploy.sh' && ! test -e '$d/archive/deploy.sh.old'"
  checkn "docs is back at the top with runbook.md" "from break-lxt11: mv scripts/docs ." \
    sh -c "test -f '$d/docs/runbook.md' && ! test -e '$d/scripts/docs'"
  check_end lxt11
}
lab_lxt11_hints() { printf '%s\n' "ls -R shows where everything ended up." "mv old-path new-path. The new path can be in a different folder with a different name." "mv archive/deploy.sh.old scripts/deploy.sh, then mv scripts/docs ."; }
lab_lxt11_solution() { printf '\n  cd ~/kloudskool-labs/break-lxt11\n  ls -R\n  mv archive/deploy.sh.old scripts/deploy.sh\n  mv scripts/docs .\n  ls -R\n\n'; }

# ---------- T12: script only works from one folder ----------
lab_lxt12_start() {
  lxb_start 12
  mkdir -p data scripts
  printf 'web01: 1200 requests, 0 errors\n' > data/today.txt
  printf '#!/bin/bash\ncat ./data/today.txt\n' > scripts/report.sh
  chmod 755 scripts/report.sh
  lxb_ready 12 "# LXT12: the report fails from cron" "" \
    "scripts/report.sh works when you run it from break-lxt12, but from anywhere else it says:" \
    "  cat: ./data/today.txt: No such file or directory" \
    "Fix the script so it works from any folder. Don't move data/today.txt."
}
lab_lxt12_check() {
  check_begin lxt12
  local d; d=$(lx_path break-lxt12)
  checkn "report.sh works when run from /" "the script uses a relative path. Use the full path that starts with /" \
    sh -c "cd / && '$d/scripts/report.sh' 2>/dev/null | grep -q '1200 requests'"
  checkn "report.sh works when run from your home folder" "same fix" sh -c "cd \"\$HOME\" && '$d/scripts/report.sh' 2>/dev/null | grep -q '1200 requests'"
  checkn "data/today.txt is still where it was" "fix the script, not the data" is_file "$d/data/today.txt"
  check_end lxt12
}
lab_lxt12_hints() { printf '%s\n' "./ means the folder you're in now, not the folder the script lives in (lesson 209)." "A full path starts at / and works from anywhere." "In report.sh, replace ./data/today.txt with the full path. pwd inside break-lxt12 tells you the start of it."; }
lab_lxt12_solution() { printf '\n  cd ~/kloudskool-labs/break-lxt12\n  pwd                        # e.g. /home/you/kloudskool-labs/break-lxt12\n  nano scripts/report.sh     # cat /home/you/kloudskool-labs/break-lxt12/data/today.txt\n  cd /\n  ~/kloudskool-labs/break-lxt12/scripts/report.sh\n\n'; }

# =====================================================================
# lxfinal  Final assessment: first week on web02. Scored out of 100, 70 passes. No hints.
# =====================================================================
lab_lxfinal_start() {
  lx_need_linux
  lx_sudo "reset the parts of the VM this assessment uses"
  pkill -u "$(id -u)" -f web02/scripts/sync-loop.sh 2>/dev/null
  user_exists lea && sudo deluser --remove-home lea >/dev/null 2>&1
  group_exists webops && sudo groupdel webops >/dev/null 2>&1
  sudo rm -f /usr/local/bin/web02-health /etc/novatech/web02.conf
  lx_fresh web02
  mkdir -p config releases/v1.8 releases/v1.9 scripts logs
  printf 'APP_NAME=web02\nENVIRONMENT=staging\nLOG_PATH=/var/log/staging/web02.log\n' > config/app.conf
  printf '#!/bin/bash\necho "app v1.8"\n' > releases/v1.8/app.sh
  printf '#!/bin/bash\necho "app v1.9"\n' > releases/v1.9/app.sh
  printf '#!/bin/bash\necho "deploying web02"\n' > scripts/deploy-new.sh
  printf '#!/bin/bash\necho "web02 health: OK"\n' > scripts/health.sh
  printf '#!/bin/bash\nwhile true; do sleep 1; done\n' > scripts/sync-loop.sh
  chmod 644 scripts/*.sh; chmod 755 scripts/sync-loop.sh
  setsid nohup "$(lx_path web02)/scripts/sync-loop.sh" >/dev/null 2>&1 < /dev/null &
  ticket LXFINAL.md <<'EOF'
# Your first week on web02

Ten tickets, 10 points each. 70 passes. Work in ~/kloudskool-labs/web02 unless a ticket says otherwise.

WEB-1  Create releases/v2.0/config and copy config/app.conf into it.
WEB-2  In the v2.0 copy only, change every "staging" to "production".
WEB-3  Remove releases/v1.8. Keep v1.9.
WEB-4  Rename scripts/deploy-new.sh to scripts/deploy.sh and make it rwx for you, nothing for anyone else.
WEB-5  Create the user lea and the group webops, and put lea in webops.
WEB-6  nginx is installed, running, and http://localhost shows a page containing: web02 ready
WEB-7  APP_ENV=production is set for every new terminal you open.
WEB-8  /usr/local/bin/web02-health is a copy of scripts/health.sh that every user can run.
WEB-9  A process started from scripts/sync-loop.sh is stuck. Stop it (keep the script).
WEB-10 /etc/novatech/web02.conf contains exactly one line: OWNER=platform
EOF
  next_steps "$(lx_path web02)"
}
lx_score() {   # lx_score <points> "<ticket>" <command...>
  local pts="$1" desc="$2"; shift 2
  LX_MAX=$((LX_MAX + pts))
  if "$@" >/dev/null 2>&1; then LX_SCORE=$((LX_SCORE + pts)); printf '  %3s/%-3s  %s\n' "$pts" "$pts" "$desc"
  else printf '  %3s/%-3s  %s\n' 0 "$pts" "$desc"; fi
}
lx_final_w9() { no_proc "web02/scripts/sync-loop.sh" && test -f "$1/scripts/sync-loop.sh"; }
lab_lxfinal_check() {
  local w; w=$(lx_path web02); LX_SCORE=0; LX_MAX=0
  head1 "Scoring the final assessment"
  lx_score 10 "WEB-1  v2.0 config copied" is_file "$w/releases/v2.0/config/app.conf"
  lx_score 10 "WEB-2  v2.0 copy says production, original untouched" \
    sh -c "test -f '$w/releases/v2.0/config/app.conf' && ! grep -q staging '$w/releases/v2.0/config/app.conf' && grep -q 'ENVIRONMENT=production' '$w/releases/v2.0/config/app.conf' && grep -q 'ENVIRONMENT=staging' '$w/config/app.conf'"
  lx_score 10 "WEB-3  v1.8 removed, v1.9 kept" sh -c "! test -e '$w/releases/v1.8' && test -f '$w/releases/v1.9/app.sh'"
  lx_score 10 "WEB-4  scripts/deploy.sh is rwx------" sh -c "! test -e '$w/scripts/deploy-new.sh' && test \"\$(stat -c %a '$w/scripts/deploy.sh')\" = 700"
  lx_score 10 "WEB-5  lea is in webops" in_group lea webops
  lx_score 10 "WEB-6  nginx serves 'web02 ready'" sh -c "systemctl is-active --quiet nginx && curl -s --max-time 5 http://localhost/ | grep -q 'web02 ready'"
  lx_score 10 "WEB-7  APP_ENV=production in new terminals" login_shell_has 'echo "$APP_ENV"' '^production$'
  lx_score 10 "WEB-8  web02-health runs for every user" \
    sh -c "cmp -s '$w/scripts/health.sh' /usr/local/bin/web02-health && test \"\$(stat -c %A /usr/local/bin/web02-health | cut -c8-10)\" = r-x"
  lx_score 10 "WEB-9  sync-loop stopped, script kept" lx_final_w9 "$w"
  lx_score 10 "WEB-10 /etc/novatech/web02.conf says OWNER=platform" content_is /etc/novatech/web02.conf "OWNER=platform"
  printf '\n  Score: %s/%s\n\n' "$LX_SCORE" "$LX_MAX"
  if [ "$LX_SCORE" -ge 70 ]; then
    state_set passed-lxfinal 1
    say "  PASS. Your completion code:  ${KB}$(ks_code lxfinal)${KR}"
    say "  Enter it in the final assessment debrief on the learning platform."
  else
    state_inc attempts-lxfinal >/dev/null
    say "  70 passes. Fix the tickets scoring 0 and run the check again. There are no hints in the final."
  fi
  printf '\n'
}
lab_lxfinal_hints() { printf '%s\n' "There are no hints in the final assessment. Each ticket matches a lab: re-do that lab if you're stuck."; }
lab_lxfinal_solution() { printf '\n  This is the assessment, so there is no walkthrough. Every ticket matches one of Labs 01-10\n  or the Break Room. Re-do the lab for the ticket you are stuck on.\n\n'; }

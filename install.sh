#!/usr/bin/env bash
# KloudSkool ks-lab installer.  Run:  curl -fsSL https://raw.githubusercontent.com/kloudskool/ks-lab/main/install.sh | bash
set -e
KS_ORG=kloudskool
DEST="$HOME/.ks-lab/app"
if ! command -v git >/dev/null 2>&1; then
  if [ "$(uname)" = "Linux" ]; then echo "Git isn't installed yet. Run:  sudo apt update && sudo apt install -y git  then run this installer again."
  else echo "Git isn't installed yet. Do lesson 302 (macOS) or 303 (Windows) first."; fi
  exit 1
fi
if [ -d "$DEST/.git" ]; then
  git -C "$DEST" pull -q --ff-only
else
  rm -rf "$DEST"; mkdir -p "$HOME/.ks-lab"
  git clone -q --depth 1 "https://github.com/$KS_ORG/ks-lab.git" "$DEST"
fi
chmod +x "$DEST/bin/ks-lab"
LINE='export PATH="$HOME/.ks-lab/app/bin:$PATH"'
add_path() { [ -f "$1" ] && grep -qF '.ks-lab/app/bin' "$1" && return 0; printf '\n# KloudSkool labs\n%s\n' "$LINE" >> "$1"; }
add_path "$HOME/.bashrc"
[ "$(uname)" = "Darwin" ] && add_path "$HOME/.zshrc"
[ -f "$HOME/.zshrc" ] && add_path "$HOME/.zshrc"
[ -f "$HOME/.bash_profile" ] && add_path "$HOME/.bash_profile"
echo ""
echo "  ks-lab is installed."
echo "  Close this terminal, open a new one, and run:  ks-lab version"
echo ""

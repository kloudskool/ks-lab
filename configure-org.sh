#!/usr/bin/env bash
# Only needed if your GitHub organisation is NOT called "kloudskool".
# Usage: ./configure-org.sh <your-github-org>     (run once, before pushing this repo)
set -euo pipefail
NEW="${1:?usage: ./configure-org.sh <your-github-org>}"
cd "$(dirname "$0")"
for f in $(grep -rlE 'kloudskool/|KS_ORG(:-|: |=)kloudskool|\|\| .kloudskool.' --exclude=configure-org.sh --exclude-dir=.git .); do
  sed -e "s#kloudskool/#$NEW/#g" -e "s#KS_ORG:-kloudskool#KS_ORG:-$NEW#g" -e "s#KS_ORG: kloudskool#KS_ORG: $NEW#g" \
      -e "s#KS_ORG=kloudskool#KS_ORG=$NEW#g" -e "s#|| 'kloudskool'#|| '$NEW'#g" "$f" > "$f.tmp" && cat "$f.tmp" > "$f" && rm "$f.tmp"
  echo "updated $f"
done

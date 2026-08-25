#!/usr/bin/env bash

set -euo pipefail

if git rev-parse --verify HEAD^ >/dev/null 2>&1; then
	git diff --check HEAD^ HEAD
fi

jq empty luci-app-shinra/root/usr/share/rpcd/acl.d/luci-app-shinra.json
jq empty luci-app-shinra/root/usr/share/shinra/defaults/dashboard.json

python3 - <<'PY'
import pathlib
import yaml

for path in pathlib.Path('.github/workflows').glob('*.yml'):
    yaml.safe_load(path.read_text(encoding='utf-8'))
PY

while IFS= read -r -d '' file; do
	node --check "$file"
done < <(find luci-app-shinra/htdocs -type f -name '*.js' -print0)

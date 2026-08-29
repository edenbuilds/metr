#!/bin/zsh
set -euo pipefail

settings="${CLAUDE_SETTINGS_PATH:-$HOME/.claude/settings.json}"
helper="${METR_STATUSLINE_HELPER:-/Applications/metr.app/Contents/Helpers/metr-statusline}"

if [[ ! -x "$helper" ]]; then
  print -u2 "metr statusline helper not found at $helper. Install metr first."
  exit 1
fi

mkdir -p "${settings:h}" "${settings:h}/backups"
if [[ -e "$settings" ]]; then
  if python3 - "$settings" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    value = json.load(f)
raise SystemExit(0 if value.get("statusLine") is not None else 1)
PY
  then
    print "Claude Code already has a statusLine. metr left it unchanged."
    exit 2
  fi
  backup="${settings:h}/backups/settings-before-metr-statusline-$(date +%Y%m%d-%H%M%S).json"
  cp "$settings" "$backup"
else
  print '{}' > "$settings"
  backup=""
fi

tmp="${settings}.metr-tmp.$$"
python3 - "$settings" "$tmp" "$helper" <<'PY'
import json, sys
settings, output, helper = sys.argv[1:]
with open(settings, encoding="utf-8") as f:
    value = json.load(f)
value["statusLine"] = {"type": "command", "command": helper}
with open(output, "w", encoding="utf-8") as f:
    json.dump(value, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
mv "$tmp" "$settings"
print "Installed metr's official Claude Code statusLine hook."
[[ -n "$backup" ]] && print "Backup: $backup"

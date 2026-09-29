#!/usr/bin/env bash
# Ставит Orbitl.app в новый симулятор iPhone, запускает и через 25 секунд проверяет,
# что процесс жив. Если нет — печатает отчёт о сбое и журнал приложения и падает.
#
#   bash scripts/smoke-launch.sh path/to/Orbitl.app [секунды]
set -uo pipefail

app="${1:?путь к Orbitl.app}"
wait_seconds="${2:-25}"
bundle="app.orbitl.ios"
out="$(mktemp -d)"

runtime="$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x["platform"]=="iOS" and x["isAvailable"]]; print(r[-1]["identifier"])')"
device_type="$(xcrun simctl list devicetypes -j | python3 -c 'import json,sys; d=[x for x in json.load(sys.stdin)["devicetypes"] if x["name"].startswith("iPhone") and "Pro" not in x["name"] and "Plus" not in x["name"]]; print(d[-1]["identifier"])')"
udid="$(xcrun simctl create orbitl-smoke "$device_type" "$runtime")"
echo "Симулятор $udid ($device_type, $runtime)"
cleanup() { xcrun simctl shutdown "$udid" >/dev/null 2>&1; xcrun simctl delete "$udid" >/dev/null 2>&1; }
trap cleanup EXIT

xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b >/dev/null
xcrun simctl install "$udid" "$app"

xcrun simctl spawn "$udid" log stream --level debug --style compact \
  --predicate 'subsystem == "app.orbitl.ios" OR process == "Orbitl"' > "$out/app.log" 2>&1 &
log_pid=$!
sleep 2

touch "$out/started"
if ! xcrun simctl launch "$udid" "$bundle"; then
  echo "::error::Orbitl не запустился"
fi
sleep "$wait_seconds"

alive=0
if xcrun simctl spawn "$udid" launchctl list 2>/dev/null | grep -q "UIKitApplication:$bundle"; then
  alive=1
fi
kill "$log_pid" >/dev/null 2>&1

echo "::group::Журнал приложения"
tail -n 300 "$out/app.log"
echo "::endgroup::"

# Отчёты о сбоях симулятора пишутся в отчёты хоста.
found=0
while IFS= read -r report; do
  found=1
  echo "::group::$report"
  head -c 120000 "$report"
  echo
  echo "::endgroup::"
done < <(find "$HOME/Library/Logs/DiagnosticReports" -name 'Orbitl*' -newer "$out/started" 2>/dev/null)

if [[ "$alive" != 1 ]]; then
  echo "::error::Orbitl закрылся в первые $wait_seconds с после запуска$([[ $found == 1 ]] && echo ', отчёт о сбое выше')"
  exit 1
fi
echo "Orbitl работает $wait_seconds с после запуска"

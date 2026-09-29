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

# Самая новая среда iOS и последний iPhone из тех, что она поддерживает.
# ORBITL_SIM_RUNTIME=26.2 выбирает среду этой версии (под SDK выбранного Xcode).
export ORBITL_SIM_RUNTIME="${ORBITL_SIM_RUNTIME:-}"
read -r runtime device_type < <(xcrun simctl list runtimes -j | python3 -c '
import json, os, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
wanted = os.environ.get("ORBITL_SIM_RUNTIME", "")
if wanted:
    runtimes = [r for r in runtimes if r["version"] == wanted or r["version"].startswith(wanted + ".")]
if not runtimes:
    sys.exit("Нет среды iOS " + (wanted or "в симуляторе"))
runtime = runtimes[-1]
phones = [d for d in runtime.get("supportedDeviceTypes", []) if d.get("productFamily") == "iPhone"]
# Порядок в списке не по году: сначала ищется iPhone 17, затем 16, иначе последний в списке.
names = {d["name"]: d for d in phones}
phone = next((names[n] for n in ("iPhone 17", "iPhone 16") if n in names), phones[-1])
print(runtime["identifier"], phone["identifier"])
')
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
# simctl launch печатает «app.orbitl.ios: <pid>»; процессы симулятора — процессы хоста.
pid="$(xcrun simctl launch "$udid" "$bundle" | tee /dev/stderr | awk -F': ' -v b="$bundle" '$1 == b { print $2 }')"
[[ -n "$pid" ]] || echo "::error::Orbitl не запустился"
sleep "$wait_seconds"

# Жив, если жив его pid или launchd симулятора ещё держит задание приложения.
alive=0
if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
  alive=1
elif xcrun simctl spawn "$udid" launchctl list 2>/dev/null | grep -q "UIKitApplication:$bundle"; then
  alive=1
fi
kill "$log_pid" >/dev/null 2>&1

if [[ "$alive" != 1 ]]; then
  # Причина завершения (runningboardd, SpringBoard, launchd): сбой, watchdog, jetsam или выход.
  echo "::group::Завершение процесса (pid ${pid:-?})"
  ps -p "${pid:-0}" -o pid,stat,etime,command 2>/dev/null || echo "(процесса $pid нет)"
  xcrun simctl spawn "$udid" launchctl list 2>/dev/null | grep -i orbitl || echo "(в launchctl list нет задания Orbitl)"
  xcrun simctl spawn "$udid" log show --last 3m --style compact --predicate \
    '(process == "runningboardd" OR process == "SpringBoard" OR process == "launchd" OR process == "ReportCrash") AND (eventMessage CONTAINS[c] "orbitl" OR eventMessage CONTAINS[c] "'"${pid:-orbitl}"'")' \
    2>/dev/null | grep -Ei "termin|exit|kill|crash|watchdog|jetsam|signal|reason|invalidat" | tail -n 80
  echo "::endgroup::"
fi

# Собственный журнал Orbitl (Application Support/Logs): фазы входа и ядра, соединение, ошибки.
container="$(xcrun simctl get_app_container "$udid" "$bundle" data 2>/dev/null)"
echo "::group::Журнал Orbitl"
cat "$container/Library/Application Support/Logs/"orbitl-*.log 2>/dev/null || echo "(файла журнала нет)"
cat "$container/Library/Application Support/Logs/"*.txt 2>/dev/null
echo "::endgroup::"

echo "::group::Системный журнал процесса (записи Orbitl и ошибки)"
grep -E "app\.orbitl\.ios|[Ee]rror|[Ff]ault|Kotlin|exception" "$out/app.log" | grep -v "KeyboardVisualMode" | tail -n 200
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

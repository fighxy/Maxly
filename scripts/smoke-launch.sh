#!/usr/bin/env bash
# Ставит Maxly.app в новый симулятор iPhone, запускает и через 25 секунд проверяет,
# что процесс жив. Если нет — печатает отчёт о сбое и журнал приложения и падает.
#
#   bash scripts/smoke-launch.sh path/to/Maxly.app [секунды]
set -uo pipefail

app="${1:?путь к Maxly.app}"
wait_seconds="${2:-25}"
bundle="app.maxly.ios"
out="$(mktemp -d)"

# Самая новая среда iOS и последний iPhone из тех, что она поддерживает.
# MAXLY_SIM_RUNTIME=26.2 выбирает среду этой версии (под SDK выбранного Xcode).
export MAXLY_SIM_RUNTIME="${MAXLY_SIM_RUNTIME:-}"
read -r runtime device_type < <(xcrun simctl list runtimes -j | python3 -c '
import json, os, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
wanted = os.environ.get("MAXLY_SIM_RUNTIME", "")
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
# Команда с пределом времени в секундах: на macOS нет timeout(1). По истечении команда и её
# дочерние процессы снимаются, код возврата ненулевой.
run_limited() {
  local limit=$1
  shift
  "$@" &
  local cmd=$!
  ( sleep "$limit"; pkill -P "$cmd" 2>/dev/null; kill "$cmd" 2>/dev/null ) &
  local timer=$!
  wait "$cmd"
  local status=$?
  kill "$timer" 2>/dev/null
  wait "$timer" 2>/dev/null
  return "$status"
}

boot_sim() {
  xcrun simctl boot "$1" && xcrun simctl bootstatus "$1" -b >/dev/null
}

udid=""
cleanup() {
  [[ -n "$udid" ]] || return 0
  run_limited 60 xcrun simctl shutdown "$udid" >/dev/null 2>&1
  run_limited 60 xcrun simctl delete "$udid" >/dev/null 2>&1
}
trap cleanup EXIT

# Симулятор на раннере иногда зависает при загрузке или установке приложения. Каждая фаза
# ограничена по времени и отмечается в журнале; зависший симулятор удаляется и создаётся
# новый, вторая попытка — последняя. Первый запуск приложения на свежем симуляторе бывает
# очень долгим (в прогонах 339 и 340 — 4–7 минут, приложение потом работает нормально),
# поэтому у запуска предел больше.
boot_limit=180
install_limit=300
launch_limit=600
prepared=0
for attempt in 1 2; do
  udid="$(xcrun simctl create maxly-smoke "$device_type" "$runtime")"
  echo "Симулятор $udid ($device_type, $runtime), попытка $attempt"
  if ! run_limited "$boot_limit" boot_sim "$udid"; then
    echo "::warning::Симулятор не загрузился за $boot_limit с (попытка $attempt)"
  else
    echo "Симулятор загружен"
    if run_limited "$install_limit" xcrun simctl install "$udid" "$app"; then
      echo "Maxly установлен"
      prepared=1
      break
    fi
    echo "::warning::Maxly не установился за $install_limit с (попытка $attempt)"
  fi
  cleanup
  udid=""
done
if [[ "$prepared" != 1 ]]; then
  echo "::error::Симулятор не подготовился за 2 попытки (загрузка или установка зависла)"
  exit 1
fi

xcrun simctl spawn "$udid" log stream --level debug --style compact \
  --predicate 'subsystem == "app.maxly.ios" OR process == "Maxly"' > "$out/app.log" 2>&1 &
log_pid=$!
sleep 2

touch "$out/started"
# simctl launch печатает «app.maxly.ios: <pid>»; процессы симулятора — процессы хоста.
pid="$(run_limited "$launch_limit" xcrun simctl launch "$udid" "$bundle" | tee /dev/stderr | awk -F': ' -v b="$bundle" '$1 == b { print $2 }')"
[[ -n "$pid" ]] || echo "::error::Maxly не запустился (за $launch_limit с)"
sleep "$wait_seconds"

# Жив, если жив его pid или launchd симулятора ещё держит задание приложения.
alive=0
if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
  alive=1
elif run_limited 60 xcrun simctl spawn "$udid" launchctl list 2>/dev/null | grep -q "UIKitApplication:$bundle"; then
  alive=1
fi
kill "$log_pid" >/dev/null 2>&1

if [[ "$alive" != 1 ]]; then
  # Причина завершения (runningboardd, SpringBoard, launchd): сбой, watchdog, jetsam или выход.
  echo "::group::Завершение процесса (pid ${pid:-?})"
  ps -p "${pid:-0}" -o pid,stat,etime,command 2>/dev/null || echo "(процесса $pid нет)"
  run_limited 60 xcrun simctl spawn "$udid" launchctl list 2>/dev/null | grep -i maxly || echo "(в launchctl list нет задания Maxly)"
  run_limited 120 xcrun simctl spawn "$udid" log show --last 3m --style compact --predicate \
    '(process == "runningboardd" OR process == "SpringBoard" OR process == "launchd" OR process == "ReportCrash") AND (eventMessage CONTAINS[c] "maxly" OR eventMessage CONTAINS[c] "'"${pid:-maxly}"'")' \
    2>/dev/null | grep -Ei "termin|exit|kill|crash|watchdog|jetsam|signal|reason|invalidat" | tail -n 80
  echo "::endgroup::"
fi

# Собственный журнал Maxly (Application Support/Logs): фазы входа и ядра, соединение, ошибки.
# Папка журнала ищется прямо в файлах симулятора: simctl get_app_container на занятом симуляторе
# отвечал до 9 минут (прогон 341).
logs="$(find "$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Containers/Data/Application" \
  -path '*/Library/Application Support/Logs/maxly-*.log' 2>/dev/null | head -n 1)"
logs="${logs%/*}"
echo "::group::Журнал Maxly"
if [[ -n "$logs" ]]; then
  cat "$logs/"maxly-*.log 2>/dev/null
  cat "$logs/"*.txt 2>/dev/null
else
  echo "(файла журнала нет)"
fi
echo "::endgroup::"

echo "::group::Системный журнал процесса (записи Maxly и ошибки)"
grep -E "app\.maxly\.ios|[Ee]rror|[Ff]ault|Kotlin|exception" "$out/app.log" | grep -v "KeyboardVisualMode" | tail -n 200
echo "::endgroup::"

# Отчёты о сбоях симулятора пишутся в отчёты хоста.
found=0
while IFS= read -r report; do
  found=1
  echo "::group::$report"
  head -c 120000 "$report"
  echo
  echo "::endgroup::"
done < <(find "$HOME/Library/Logs/DiagnosticReports" -name 'Maxly*' -newer "$out/started" 2>/dev/null)

if [[ "$alive" != 1 ]]; then
  echo "::error::Maxly закрылся в первые $wait_seconds с после запуска$([[ $found == 1 ]] && echo ', отчёт о сбое выше')"
  exit 1
fi
echo "Maxly работает $wait_seconds с после запуска"

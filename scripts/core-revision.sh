#!/usr/bin/env bash
# Печатает ревизию ядра из core.lock, которую нужно собрать.
#
#   bash scripts/core-revision.sh maxly-ios/core.lock
#
# revision= в core.lock — коммит, ветка или `latest`. `latest` — последний коммит `main` ядра, на
# котором прошёл его CI (workflow `ios-core.yml`); если GitHub API недоступен — `main` (и
# предупреждение в stderr). Коммит и ветка печатаются как есть. MAX_CORE_REVISION, если задана,
# важнее core.lock: так CI один раз узнаёт ревизию (для ключа кэша) и передаёт её скрипту сборки.
# Пока CI только что влитого ядра идёт, `latest` — ещё прежний коммит: приложению, которому уже
# нужно новое ядро (или ядро из незалитой ветки), коммит вписывается в core.lock явно.
set -euo pipefail

lock="${1:?Укажите core.lock}"
if [[ -n "${MAX_CORE_REVISION:-}" ]]; then
  echo "$MAX_CORE_REVISION"
  exit 0
fi
revision="$(grep '^revision=' "$lock" | head -n 1 | cut -d= -f2- | tr -d '[:space:]')"
repository="$(grep '^repository=' "$lock" | head -n 1 | cut -d= -f2- | tr -d '[:space:]')"
if [[ -z "$revision" || -z "$repository" ]]; then
  echo "В $lock нужны строки revision= и repository=" >&2
  exit 1
fi
if [[ "$revision" != "latest" ]]; then
  echo "$revision"
  exit 0
fi

slug="${repository#https://github.com/}"
slug="${slug%.git}"
auth=()
if [[ -n "${MAX_KMP_CORE_TOKEN:-}" ]]; then auth=(-H "Authorization: Bearer ${MAX_KMP_CORE_TOKEN}"); fi
green="$(curl -fsSL ${auth[@]+"${auth[@]}"} -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${slug}/actions/workflows/ios-core.yml/runs?branch=main&status=success&per_page=1" 2>/dev/null \
  | python3 -c 'import json, sys; runs = json.load(sys.stdin).get("workflow_runs") or []; print(runs[0]["head_sha"] if runs else "")' 2>/dev/null \
  || true)"
if [[ -n "$green" ]]; then
  echo "Ядро: последний зелёный коммит main — $green" >&2
  echo "$green"
else
  echo "::warning::Не удалось узнать последний зелёный коммит ядра, берётся main." >&2
  echo "main"
fi

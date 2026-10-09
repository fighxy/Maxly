#!/usr/bin/env bash
# Обновляет единственный пререлиз платформы (ios-latest, android-latest, desktop-latest)
# сборкой текущего коммита: ссылка на файл не меняется, внутри всегда последняя зелёная сборка.
# Выпуск и его тег постоянные: скрипт только заменяет файлы и заметки. Встроенный токен Actions
# не может создать тег на коммите, в истории которого правились воркфлоу (HTTP 403), поэтому тег
# не пересоздаётся, а настоящий SHA сборки пишется в заголовок и заметки.
# CI вызывает скрипт только после успешной сборки на push в main.
#
# Переменные: TAG, TITLE, NOTES; WATCH — пути через пробел, на которые запускается сборка
# платформы; GITHUB_REPOSITORY, GITHUB_SHA и GH_TOKEN задаёт Actions.
# Аргументы — файлы выпуска; имя файла становится именем в выпуске (Maxly.apk, Maxly.msi и т. п.).
set -euo pipefail

: "${TAG:?}" "${TITLE:?}" "${NOTES:?}" "${WATCH:?}"
repo="$GITHUB_REPOSITORY"
sha="$GITHUB_SHA"

if [[ $# -eq 0 ]]; then
  echo "::error::Нет файлов для выпуска"
  exit 1
fi
for file in "$@"; do
  if [[ ! -f "$file" ]]; then
    echo "::error::Нет файла $file"
    exit 1
  fi
done

# Выпуск только для свежей сборки. Если main ушёл дальше и новые коммиты задевают пути этой
# платформы, выпуск сделает их прогон; если задевают только другие платформы, эта сборка
# остаётся последней и публикуется.
tip="$(gh api "repos/$repo/commits/main" --jq .sha)"
if [[ "$tip" != "$sha" ]]; then
  status="$(gh api "repos/$repo/compare/$sha...$tip" --jq .status)"
  if [[ "$status" != "ahead" ]]; then
    echo "::notice::Коммита $sha больше нет в main ($status): выпуск $TAG пропущен"
    exit 0
  fi
  changed="$(gh api "repos/$repo/compare/$sha...$tip" --jq '.files[].filename')"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    for prefix in $WATCH; do
      if [[ "$path" == "$prefix"* ]]; then
        echo "::notice::В main есть более новый коммит для $TAG ($tip меняет $path): выпуск пропущен"
        exit 0
      fi
    done
  done <<< "$changed"
fi

# Файлы заменяются на месте, выпуск не удаляется: если что-то упадёт, старая сборка останется.
if gh release view "$TAG" --repo "$repo" > /dev/null 2>&1; then
  gh release upload "$TAG" "$@" --repo "$repo" --clobber
  gh release edit "$TAG" --repo "$repo" --prerelease --title "$TITLE" --notes "$NOTES"
else
  # Первый выпуск платформы. Если встроенному токену создать тег нельзя, выпуск создают один раз
  # вручную (gh release create "$TAG" ... --prerelease), дальше CI только обновляет файлы.
  if ! gh release create "$TAG" "$@" --repo "$repo" --target "$sha" --prerelease \
    --title "$TITLE" --notes "$NOTES"; then
    echo "::error::Выпуска $TAG нет, а создать его токеном CI не удалось. Создайте его один раз вручную."
    exit 1
  fi
fi
echo "Выпуск $TAG: https://github.com/$repo/releases/tag/$TAG"

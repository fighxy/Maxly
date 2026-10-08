# Черновики на сервере: общие сценарии

Черновик поля ввода живёт на устройстве и на сервере, чтобы его видели другие сессии.
Правила слияния одинаковы на Swift (`orbitle-ios`) и Kotlin (`orbitle-shared`). Swift
проигрывает сценарии в `DraftsFixtureTests` (`orbitle-ios/Tests/OrbitleDomainTests`),
логика — `DraftSync` в `OrbitleDomain`. Новый файл без проигрывателя — ошибка.

Здесь только смысл: когда именно сохранять (задержка, уход из чата, фон) — дело клиента.
Черновик — текст с разметкой и ответ; черновик из одного ответа (пустой текст + `replyTo`)
тоже сохраняется. Вложения в черновик не попадают никогда. После успешной отправки сообщения
черновик стирает ядро (`DRAFT_DISCARD` после `sendText`, `sendFormattedText`,
`sendAttachments`, `sendMedia`): клиент сам его не стирает.

## Протокол

- `DRAFT_SAVE` 176 `{chatId | userId, draft: {text, elements, replyTo?}}`, ответ `{time}` —
  время сохранения на сервере, оно становится `updateTime` черновика. Вложения не уходят.
- `DRAFT_DISCARD` 177 `{chatId | userId, time}`, `time` — `updateTime` стираемого черновика.
- Адрес: личный чат, бот и «Избранное» — **`userId`** собеседника (у «Избранного» — свой id),
  группа и канал — `chatId`.
- `LOGIN` приносит `drafts: {chats|users: {saved: {id: draft}, discarded: {id: time}}}`;
  черновик сервера — `{saveTime, text, elements, replyTo?}`.

## Правила

**Слияние (`merge`).**
1. Пустой текст (после обрезки) без ответа — черновика нет.
2. Из двух непустых побеждает больший `updateTime`; при равном остаётся локальный.
3. Стирание с сервера (`discardedAt`) не раньше `updateTime` победителя стирает черновик
   (равное время — стирает: так сервер помечает стирание именно этого черновика).
4. Разметка (`spans`) и ответ (`replyTo`) идут вместе с текстом.

**Что отправить (`outgoing`).**
1. Непустой черновик, который отличается от серверного (текст после обрезки, разметка или
   ответ), — `DRAFT_SAVE`; текст обрезается по краям, разметка сдвигается
   (как `formatting/serialize-trim`), `elements` всегда список. Пустой текст (черновик из
   одного ответа) не отправляется: ключа `text` в `draft` нет.
2. Пустой черновик, когда на сервере есть черновик, — `DRAFT_DISCARD` с его `updateTime`.
3. Иначе — ничего.

## Файлы

`merge`: `local`, `server` — `{text, updateTime, replyTo?, spans?}` или `null`; `discardedAt` —
мс или `null`; `expect` — черновик или `null`.

`outgoing`: `me`, `chat {id, type: DIALOG|CHAT|CHANNEL, peerId?}`, `server`, `local`;
`expect.request` — `DRAFT_SAVE`, `DRAFT_DISCARD` или `null`, `expect.payload` — тело запроса
(id строками, `replyTo` только если есть).

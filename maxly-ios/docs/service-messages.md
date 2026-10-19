# Служебные сообщения

Служебное сообщение — сообщение без текста с вложением `CONTROL`: событие чата лежит в
`event`. Лента показывает его серой плашкой по центру (без пузыря, аватара, меню и ответа
свайпом), строка списка чатов — тем же текстом без имени автора над ним и без галочек.
Закрепление (`pin`, `unpin`) — тоже `CONTROL`, но у него своя плашка (`pins.md`).

События, поля и правила текста — в `test-fixtures/service-messages/README.md`, сценарии там же.

## Путь данных

1. Ядро отдаёт вложения сообщения как пришли: `IosMessage.contentJson` и `contentJson` пуша
   `message` несут `attaches` с `CONTROL` целиком.
2. `MessageContentCodec.serviceNotice` разбирает его в `MessageContent.service`
   (`ServiceNotice`: событие, участники, название, текст сервера).
3. `MessageRepositoryImpl.upsert` дописывает в событие имена участников (у отправителя этого
   сообщения или из последнего сохранённого сообщения участника), id аккаунта и текст
   сообщения (`ServiceNotice.filled`).
4. Текст строит `ServiceText` (`MaxlyDomain`): лента — `MessageBubble`, строка списка —
   `SyncEngine` (пуш), `ChatRepositoryImpl.replaceLast` (удалили последнее) и снимок
   списка (`servicePreviews`). Вид последнего сообщения в строке — `MessageMediaKind.service`.
5. Служебные строки не входят в непрочитанные, не выбираются, не закрепляются и не
   помечаются непрочитанными (`MessageContent.isService`). Уведомление приходит только
   о «теперь в MAX».

## Чего не хватает в ядре

- `IosChat` не несёт вложений последнего сообщения: у `CONTROL` пусты и `lastText`, и
  `lastMedia` (`attachmentKind` знает только медиа). Пока последнего сообщения нет в базе,
  строка показывает «Служебное сообщение». Нужен, например, `lastContentJson` (тот же
  фрагмент, что `IosMessage.contentJson`) или готовый `lastControl` (`event`, `userId`,
  `userIds`, `title`, `chatType`).
- В `contentJson` у `CONTROL` только id участников (`userId`, `userIds`). Имена клиент
  ищет сам и не всегда находит. Ядро знает их (`MaxState.displayName`), как уже делает для
  `link.message.senderName`: нужен, например, `userNames` (id → имя) в каждом `CONTROL`.

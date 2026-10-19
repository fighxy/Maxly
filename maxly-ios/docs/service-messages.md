# Служебные сообщения

Служебное сообщение — сообщение без текста с вложением `CONTROL`: событие чата лежит в
`event`. Лента показывает его серой плашкой по центру (без пузыря, аватара, меню и ответа
свайпом), строка списка чатов — тем же текстом без имени автора над ним и без галочек.
Закрепление (`pin`, `unpin`) — тоже `CONTROL`, но у него своя плашка (`pins.md`).

События, поля и правила текста — в `test-fixtures/service-messages/README.md`, сценарии там же.

## Путь данных

Текст пишет ядро (`controlFallbackText`, ядро 3b21250): лента, строка списка чатов и
уведомление показывают одно и то же, как Android и десктоп.

1. Ядро отдаёт вложения сообщения как пришли (`contentJSON` с `CONTROL` целиком) и готовый
   `IosControl` (событие, участники, название, `fallbackText`, `message`, `shortMessage`):
   - история — `IosMessage.control`;
   - пуши `message` и `edited` — `IosEvent.control`;
   - строка списка чатов — `IosChat.lastControl` (по последнему сообщению чата).

   `fallbackText` — текст сервера (`shortMessage`, затем `message`), иначе текст известного
   события: «Вы» для аккаунта, имена отправителя и участников из стора ядра, «теперь в MAX» для
   `hello` и `new` личного чата, «Закреплено: …» / «Сообщение закреплено» у `pin` (текст из
   `pinnedMessage` или стора), «Закрепление снято» у `unpin`. `nil` — ядру сказать нечего
   (`system`, незнакомое событие без текста сервера). У `pin` ещё `pinnedMessageId` и
   `pinnedText`. Сообщения без `type` ядро не отбрасывает (`type` = `""`).
   `CONTROL` ядро узнаёт само (с 3b21250): `_type` в любом регистре, а без `_type` —
   `type: "control"`. Клиент вложение не переписывает.
2. `MaxIosCore` переносит `IosControl` в `CoreControl` (`CoreMessage.control`,
   `CoreEvent.control`, `CoreChat.lastControl`).
3. `MessageContentCodec.serviceNotice` разбирает `CONTROL` в `MessageContent.service`
   (`ServiceNotice`), `CoreMapping.withControl` кладёт в него текст ядра (`coreText`), а без
   `CONTROL` во фрагменте — само событие. Так же — у сообщения из пуша (`MessageRecord(event)`).
4. `MessageRepositoryImpl.upsert` дописывает в событие имена участников, id аккаунта и текст
   сообщения (`ServiceNotice.filled`): они нужны, только если текста ядра нет.
5. `ServiceText` (`MaxlyDomain`) отдаёт `coreText`; без него — текст сервера или сообщения,
   иначе «Служебное сообщение». Сообщение, сохранённое без текста ядра (старой сборкой),
   пишется теми же словами, что пишет ядро (`ServiceText.storedText`), пока история не
   перечитана. Своих формулировок, отличных от ядра, у iOS нет.
6. Где показывается:
   - лента — `MessageBubble` (`ServiceEventNotice`);
   - строка списка — `CoreMapping.chat` по `lastControl` (текст ядра, вид
     `MessageMediaKind.service`; сообщения в базе для этого не нужно), `SyncEngine` (пуши
     `message` и `edited`), `ChatRepositoryImpl.replaceLast` (удалили последнее) и снимок
     списка (`servicePreviews`);
   - уведомление — `SyncEngine`: тот же текст, что в строке.
7. Служебные строки не входят в непрочитанные, не выбираются, не закрепляются и не
   помечаются непрочитанными (`MessageContent.isService`). Уведомление приходит только
   о «теперь в MAX» (`hello`, `new` личного чата).

Закрепление (`pin`, `unpin`) — `MessageContent.pin` (`PinNotice`), а не событие: своя плашка
(`ServiceMessageNotice`) с текстом ядра (`PinNotice.coreText`) и переходом к закреплённому по
`pinnedMessage.id` (или `IosControl.pinnedMessageId`). Без текста ядра — те же слова
(`ServiceText.text(pin)`, `ServiceText.pinPreview`): пустой текст и `pin` без `pinnedMessage`
— «Сообщение закреплено» (это не снятие, `PinNotice.unpinned` = `false`), `unpin` —
«Закрепление снято». Строка списка и уведомление о закреплении — тем же текстом.

## Чего не хватает в ядре

- В `contentJSON` у `CONTROL` только id участников (`userId`, `userIds`). Имена знает
  `fallbackText`, но не сам фрагмент: если ядро имени не знает, текст безличный
  («Добавлены участники»), даже когда имя есть в базе iOS.

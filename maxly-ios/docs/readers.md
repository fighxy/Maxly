# «Кем прочитано» и сведения о сообщении

Кто прочитал сообщение в группе и прочитано ли своё сообщение в личном чате. Протокол взят из
официального веб-клиента Max (только факты, код не заимствован). Общие с Kotlin сценарии,
правила и формат — в [`test-fixtures/readers`](../../test-fixtures/readers/README.md).

## Протокол

Отдельного запроса «кто прочитал» нет: список собирает клиент из двух источников.

| Источник | Тело | Что даёт |
|---|---|---|
| `participants` карточки чата (`LOGIN`, `CHAT_INFO` 48, пуши чата) | `{"<userId>": <мс>}` | до какого времени каждый прочитал чат |
| 130 `NOTIF_MARK` (пуш) | `{chatId, userId, mark, unread?, setAsUnread?}` | новая отметка участника |
| 181 `MSG_GET_DETAILED_REACTIONS` | запрос `{chatId, messageId, count: 100}`, ответ `reactions: [{userId, reaction}]` | кто как отреагировал |

`CHAT_MEMBERS` 59 (`type: "MEMBER"`) отдаёт `readMark` у каждого участника — веб берёт его для
участников, которых нет в карточке. `MSG_GET_STAT` 74 — просмотры и пересылки постов канала,
к прочтениям отношения не имеет.

Веб-клиент держит список живым: отметки из пушей 130 сразу меняют его, реакции 181 кэшируются
до пуша `NOTIF_MSG_REACTIONS_CHANGED` 155, открытия чата или переподключения. В вебе это
подменю «Кто прочитал» в меню сообщения, без времени и счётчиков. Экрана сведений в вебе нет.

## Правила

`MessageReaders` (OrbitleDomain) — чистые правила без сети и хранения:

- `isAvailable(chatId:chatType:isVideoConversation:participantsCount:messageState:maxReadmarks:)` —
  только `CHAT` без `videoConversation`, участников (`participantsCount`, а без него — размер
  `participants`) не больше порога (`max-readmarks` сервера,
  по умолчанию 100, `maxReadmarks(server:)`), сообщение отправлено (не `sending`, `failed`,
  `scheduled`). Своё или чужое — неважно. В личных чатах, «Избранном» и каналах — нет.
- `marks(participants:pushed:)` — разбор `participants` (числа и строки) и слияние с пушами 130:
  бо́льшая отметка побеждает. `merged(_:_:)` — то же для следующего пуша.
- `build(messageTime:authorId:me:marks:reactions:)` — сначала отреагировавшие в порядке ответа
  181 (с эмодзи), затем прочитавшие (`messageTime <= mark`) по убыванию отметки, при равной — по
  id как числу. Каждый один раз, без себя и без автора. `readMark` — отметка; у отреагировавшего
  с отметкой раньше сообщения — `nil`. `reactions == nil` — 181 не удался:
  только прочитавшие, без ошибки.
- `privateStatus(chatId:chatType:isOwn:messageState:messageTime:peerMark:)` — строка
  «Прочитано» / «Доставлено» для своего отправленного сообщения в личном чате (кроме
  «Избранного»): прочитано, если отметка собеседника больше нуля и не раньше сообщения.

- `MessageInfo.editedTime(updateTime:)` — время для строки «изменено» или `nil`.

Тесты: `ReadersFixtureTests` (OrbitleDomainTests) проигрывают все файлы `test-fixtures/readers`.

## Экран сведений

Пункт «Сведения» (`info.circle`) в контекстном меню любого отправленного сообщения — своего и
чужого, в любом чате; у `sending`, `failed`, запланированных и сообщений без серверного id его нет
(`MessageInfoViewModel.isAvailable(for:)`). Открывает лист `MessageInfoView` (как список
реакций: `NavigationStack`, `List`, «Закрыть», `.medium`/`.large`):

- «Отправлено» — время сообщения («сегодня в 15:00», «вчера в…», «3 октября в…», в другом
  году — с годом);
- «Изменено» и время правки, если `updateTime > 0`; если сервер пометил правку без времени —
  просто «Изменено»;
- «Переслано из» — автор исходного сообщения пересылки;
- в личном чате, только у своего сообщения, — «Прочитано» / «Доставлено» (`privateStatus`
  по признаку прочтения сообщения); у входящих и в «Избранном» строки нет;
- в группе, где `isReadersAvailable`, — раздел «Кем прочитано»: загрузка, список (аватар, имя,
  «Прочитано · время» или эмодзи реакции), пустой — «Пока никто не прочитал», ошибка —
  «Не удалось загрузить список» с «Повторить». Нажатие на человека закрывает лист и открывает
  личный чат с ним.

`MessageInfoViewModel` (OrbitlePresentation) — строки и состояние списка, тесты —
`MessageInfoViewModelTests`.

## Подключение

Список собирает ядро (`maxly-core`, `core.lock`) по тем же правилам и сценариям:

- `MaxIosClient.isReadersAvailable(chatId:)` — показывать ли раздел (по сохранённой карточке
  чата и `max-readmarks`);
- `MaxIosClient.loadMessageReaders(chatId:messageId:)` — освежает `CHAT_INFO`, при нехватке
  участников добирает 59, запрашивает 181 и отдаёт `IosMessageReader(userId, name, reaction,
  readMark)`; `readMark == 0` — отметки нет, пустая реакция — реакции нет.

Цепочка: `MaxIosCore` → `MaxCore.loadMessageReaders` / `isReadersAvailable` →
`MaxAPI.messageReaders` / `readersAvailable` → `MessageRepository.messageReaders(messageId:)` /
`readersAvailable(chatId:)`. Репозиторий находит серверный id и чат по сохранённому сообщению,
а пустые имена и аватары дополняет из локальной базы (профили и сообщения автора) — аватаров
мост не отдаёт.

Время правки: `IosMessage.updateTime` и `IosEvent.updateTime` (мс, `0` — правки не было) →
`CoreMessage` / `CoreEvent.updateTimeMs` → `MessageRecord.updateTimeMs` → `SDMessage.updateTimeMs`
→ `Message.editedAt`. Запись без времени (`0`) сохранённое время не стирает.

Ядро и клиентские правила расходятся в мелочах: «Избранное» (`chatId == "0"`) и состояние
сообщения (`sending`, `failed`, запланированное) проверяет только клиент; при повторе ключа в
`participants` ядро берёт последнее значение, `MessageReaders` — бо́льшее. `MessageReaders`
остаётся эталоном сценариев `test-fixtures/readers`.

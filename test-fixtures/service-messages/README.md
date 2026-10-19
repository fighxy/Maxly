# Служебные сообщения: общие сценарии

Служебное сообщение — сообщение с вложением `CONTROL`: в нём нет текста, а событие чата
лежит в `event`. Клиент показывает его серой плашкой по центру ленты (без пузыря и аватара)
и тем же текстом в строке списка чатов. Swift проигрывает сценарии в
`ServiceMessageFixtureTests` (`maxly-ios/Tests/MaxlyDataTests`): разбор — `MessageContentCodec`,
текст — `ServiceText` в `MaxlyDomain`. Android и десктоп — в `ServiceMessagesFixtureTest`
(`maxly-shared`): разбор — `ServiceMessages.notice`, текст — `ServiceMessages.text`. Новый файл
без проигрывателя — ошибка.

## Вложение

`{_type: "CONTROL", event, userId?, userIds?, title?, chatType?, url?, photoToken?,
showHistory?, startPayload?, shortMessage? | message?}`. Известные события:

| event | смысл | поля |
|---|---|---|
| `hello` | контакт теперь в MAX | `userId?` |
| `new` | создан чат или канал; у `DIALOG` — контакт теперь в MAX | `chatType`, `title`, `userIds` |
| `add` | добавлены участники (сам себя — вступил) | `userIds`, `showHistory` |
| `remove` | удалены участники (сам себя — вышел) | `userIds` / `userId` |
| `leave` | отправитель покинул чат | — |
| `joinByLink` | отправитель вступил по ссылке | — |
| `title` | новое название | `title` |
| `icon` | новое фото чата | `url`, `photoToken` |
| `botStarted` | запущен бот | `startPayload` |
| `system` | текст сервера | `shortMessage` / `message` / текст сообщения |
| `pin`, `unpin` | закрепление: своя плашка, не событие | `pinnedMessage` |

Автор события — отправитель сообщения. Имена участников ядро не присылает (только id):
клиент берёт их из того, что уже знает (`names` сценария).

## Правила текста

1. Своё событие (отправитель — `viewer`) — от «Вы» с глаголом во множественном числе
   («Вы создали чат»), чужое — имя и глагол с «(а)» («Анна создал(а) чат»).
2. Участник-аккаунт — «вас». Участники без имени — счётом («2 участника», «5 участников»),
   с именами — через запятую и «и», неизвестные после имён — «и ещё N».
3. Название — в «ёлочках». Пустое название — без него.
4. Нет имени отправителя — «Участник»; у «теперь в MAX» — «Контакт».
5. `system` и незнакомое событие — текст сервера (`shortMessage`, `message`, затем текст
   сообщения), без него — «Служебное сообщение».
6. Регистр `event` и `_type` не важен; `userId` `0` — нет участника.
7. Текст ядра (`coreText`, из `IosControl.fallbackText`: свой у `new` и `botStarted`, у
   остальных событий — `shortMessage`, затем `message` сервера) заменяет свой текст, кроме
   «теперь в MAX» для `new` личного чата (там ядро пишет общее «Чат создан»).

## Формат

`{kind: "control", name, description, cases: [{name, message: {sender, senderName, text,
attaches}, viewer, names, coreText?, expect: {kind, text}}]}`. `expect.kind` — вид события `ServiceText.Kind`
(`joined`, `created`, `added`, `removed`, `left`, `joinedByLink`, `renamed`, `photo`,
`botStarted`, `system`, `unknown`); `null` — сообщение не служебное событие (закрепление).

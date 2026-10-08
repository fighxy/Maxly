# Статус «в сети / был(а)»

Где виден статус человека и откуда он берётся. Тексты и общие с Kotlin сценарии — в
[`test-fixtures/presence`](../../test-fixtures/presence/README.md) (`PresenceFixtureTests`).

## Где показывается

| Место | Что | Обновление |
|---|---|---|
| Список чатов | точка у аватара личного чата | по изменениям `PresenceStore` |
| Шапка личного чата | «в сети» цветом акцента или «был(а) …» со строчной | `TimelineView(.everyMinute)` и изменения |
| Профиль человека | «В сети» / «Был(а) …» | раз в минуту и изменения |
| Контакты | строка под именем, точка | таймер раз в минуту и изменения |
| Участники группы | строка под именем, точка (себе — нет) | `TimelineView(.everyMinute)` и изменения |
| Шапка настроек (свой статус) | «в сети» / «был(а) …» со строчной под номером | свой запрос раз в 15 с, мимо `PresenceStore` ([`privacy.md`](privacy.md)) |

У групп, каналов, ботов и «Избранного» статуса нет.

## Мост ядра (84a9ffc)

| Вызов | Что делает |
|---|---|
| `loadPresence(userIds)` | `CONTACT_PRESENCE` пачками по 100; кого сервер не вернул — статус `3` |
| `presenceOf(userId)` | то, что ядро уже знает, без запроса |
| `setAppActive(active)` | приложение на экране / в фоне, ответа нет |
| поле `presence: Int` | у `IosContact`, `IosProfile`, `IosGroupMember` |
| событие `presence` | `authorId` — человек, `presence` — код, `timeMs` — последний визит, мс |

Коды: `-1` не прислан, `0` не в сети (время — `seenMs`), `1` в сети, `2` недавно, `3` давно.
Перевод — `Contact.Presence.server(status:seenMs:)`; на стороне Data — `CorePresence.presence`
и `CoreMapping.presence(status:online:seenMs:)` (без кода — старые поля `online`/`seen`).

## Поток данных

```
контакты, профили ─┐
событие presence ──┼─► PresenceStore (одно на приложение) ─► changes() ─► экраны
loadPresence ──────┘          ▲
                              └── CorePresenceService.refresh(ids) ◄── экраны: кого видно
```

- `PresenceStore` (OrbitleDomain): `.unknown` известное не затирает, запись старше известной не
  применяется, «в сети» без подтверждения через 5 минут становится «был(а)» во время последнего
  подтверждения.
- `CorePresenceService` (OrbitleData, `PresenceProvider`): `refresh(ids)` берёт только числовые
  id, каждого не чаще раза в минуту, и пишет ответ в хранилище; при ошибке спросит снова при
  следующем показе. `presence(of:)` — из хранилища, а если там пусто — `presenceOf` ядра.
- `SyncEngine` пишет события `presence` в то же хранилище (`attachPresence`).
- Экраны получают `PresenceProvider`: просят статусы видимых людей (`refresh`), после ответа
  сами читают уже известные значения (изменением они не придут) и слушают `changes()`.

| Экран | Кого спрашивает |
|---|---|
| `ChatListViewModel` | собеседников видимых личных чатов: `id чата ^ свой id`; тех же — раз в минуту |
| `ContactsViewModel` | всех контактов после каждого списка, не задерживая показ |
| `ChatMembersListModel` | участников каждой загруженной страницы, кроме себя |
| `ChatProfileViewModel` | собеседника (`peerId` профиля человека) при загрузке и открытии экрана |

Живой статус экрана важнее статуса из списка или карточки; пока о человеке ничего не известно,
остаётся статус из списка (в списке чатов — серверная точка).

## Приложение на экране

`RootView` по `scenePhase`: `.active` → `AppContainer.setAppActive(true)`, `.background` →
`false`; после входа ядру сразу сообщается `true`. При выходе из аккаунта хранилище очищается,
а `CorePresenceService` забывает, кого спрашивал.

## Проверки

- `PresenceFixtureTests` — тексты по сценариям.
- `PresenceLiveTests`, `ChatListPresenceTests` — живые обновления экранов.
- `ChatProfileViewModelTests.livePresence` — шапка и профиль.
- `CorePresenceTests` (OrbitleData) — коды ядра, пачки и минутный порог, ошибка, событие.

# Локальная база iOS-клиента

## Схема

| Модель | Поля | Связи |
|---|---|---|
| `SDChat` | id, title, kind (dialog, group, channel), lastMessageId, unreadCount, updatedAt | messages, каскадное удаление |
| `SDMessage` | id, chatId, authorId, text, timestamp, status (sending, sent, delivered, read, failed), mediaId | chat, media (nullify) |
| `SDUser` | id, name, avatarUrl | нет |
| `SDMediaItem` | id, kind (photo, video, audio, file, sticker), url, size, localPath | нет |

Все `id` уникальны (`@Attribute(.unique)`). В `SDMessage` лежит и связь `chat`, и поле `chatId`: по полю быстрее фильтровать. Перечисления хранятся строками (`*Raw`), чтобы новые значения не ломали схему. Контейнер создаётся в `SwiftDataStack`, который умеет работать в памяти для тестов и полностью очищать базу при выходе.

## Почему SwiftData

SwiftData встроена в iOS 17+, работает со Swift 6 и SwiftUI, не требует сторонних зависимостей, а через `@ModelActor` даёт фоновые записи без гонок данных. Модели остаются внутри `OrbitlData`, а наружу выходят только доменные типы и Sendable-записи (`ChatRecord`, `MessageRecord`). Поэтому базу можно заменить, не трогая экраны. **Риск:** производительность на десятках тысяч сообщений нужно проверить прототипом (architecture.md, «iOS-клиент»).

## Swift 6 и потоки

Репозитории `ChatRepositoryImpl` и `MessageRepositoryImpl` сделаны как `@ModelActor`, у каждого свой фоновый `ModelContext`. Модели SwiftData не Sendable и не покидают актор. Главный контекст (`SwiftDataStack.mainContext`) нужен только для чтения на главном акторе.

## Пагинация

Используется курсор по `timestamp`. Страница содержит `pageSize` (50) сообщений строго старше курсора, от новых к старым (`page(chatId:before:limit:)`). Экран подписан на `messages(chatId:)` и получает последние N сообщений чата. `loadOlder` увеличивает N на страницу, а если в кэше старше ничего нет, запрашивает историю с сервера, начиная от `oldestTimestamp(chatId:)`.

## Синхронизация с сервером

Схема такая: сначала кэш, потом фоновое обновление.

1. Подписка на `chats()` или `messages(chatId:)` сразу отдаёт данные из базы.
2. `refresh()` и `SyncEngine` в фоне запрашивают сервер и пишут результат через `upsert(_:)`.
3. После каждой записи репозиторий заново отдаёт снимок всем подписчикам, и экран обновляется сам.
4. Исходящее сообщение сначала записывается со статусом `sending` и локальным id, затем уходит через `OutboxQueue`. После ответа сервера статус меняется на `sent`, при ошибке на `failed`.

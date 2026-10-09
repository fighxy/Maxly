# Конфиденциальность: режим призрака и настройки MAX

Решение Ивана и команды (окончательное): в «Настройки → Безопасность» часть «Конфиденциальность».
Сверху — дополнительный блок «Дополнительно» (так же называется на Android) с тремя
переключателями, ниже — настройки приватности MAX в порядке MAX и секция «Информация». В шапке
настроек под номером — свой статус так, как его видит сервер.

Режим призрака, отметки о прочтении, свой статус и настройки приватности делает ядро
`maxly-core` (ревизия из `core.lock`, `ac9c7fb`). Приложение подключено к нему одним
адаптером `CoreGhostPrivacyControls` (раздел 7): флаги и настройки живут в ядре и на сервере,
приложение их не хранит и сеть само не трогает.

## 1. Где на экране

```
Настройки (вкладка)
├── Шапка: аватар, имя, номер, ● в сети / был(а) …      свой статус (раздел 3)
└── Безопасность ›
    ├── Пароль для входа, почта для восстановления
    ├── Семейная защита: Отключена / Вы администратор / Профиль под защитой / Неизвестно
    ├── КОНФИДЕНЦИАЛЬНОСТЬ — Дополнительно
    │   ├── Режим призрака                         переключатель
    │   ├── Не отправлять отметки о прочтении      переключатель
    │   └── Показывать мой онлайн                  переключатель, по умолчанию включён
    ├── (без заголовка)
    │   ├── Безопасный режим                       переключатель
    │   ├── Найти меня по номеру ›                 Могут все / Могут контакты
    │   ├── Позвонить ›                            Могут все / Могут контакты
    │   ├── Пригласить в чат ›                     Могут все / Могут контакты
    │   └── Показывать контент ›                   Весь / Безопасный
    ├── Информация
    │   ├── Видеть статус «в сети» ›               Контакты / Никто
    │   └── Видеть мой номер ›                     Могут все / Могут контакты / Никто
    ├── Приватный режим (на устройстве, docs/privacy-mode.md)
    ├── Имена из адресной книги
    └── Чёрный список ›
```

## 2. «Дополнительно»

| Переключатель | Что делает ядро | Что делает приложение |
|---|---|---|
| **Режим призрака** | `setGhostMode` / `ghostMode()`: `PING` 1 и `LOGIN` 19 с `interactive: false` (в том числе первый `LOGIN` после запуска и при возврате из фона), один `PING` сразу при переключении; не шлёт `MSG_TYPING` 65 никакого вида: текст, запись голосового и кружка, загрузка фото, видео и файлов, стикеры (`sendTyping` молча ничего не делает). Флаг хранится в ядре и переживает выход и перезапуск | `GhostControls.setGhostMode` → мост; сразу спрашивает свой статус |
| **Не отправлять отметки о прочтении** | `setHideReadReceipts` / `hideReadReceipts()`: `markRead` / `markReadAt` идут через `MaxClient.markRead` и без сети читают чат на устройстве — ответ несёт локальный счётчик и отметку; счётчик чата в сторе ядра остаётся нулём и после переподключения, пока отметка сервера не догонит (`localReadMarkOf`). Просмотры историй тоже не уходят; `SET_AS_UNREAD` — как обычно | ничего сверх обычного: экран чата шлёт отметку по увиденному (`markRead(chatId:messageId:at:)`), ответ `markReadAt` применяется как раньше. Местная отметка ядра (`localReadMark`) входит в свою позицию чата: по ней встаёт разделитель непрочитанных ([`read-marks.md`](read-marks.md)) |
| **Показывать мой онлайн** | — | строка в шапке настроек (раздел 3); настройка устройства (`SelfCheckStore`) |

Приложение **не дублирует** логику ядра: не трогает `setAppActive`, `TypingReporter` и
`markRead`. Всё, что гасится, гасится в ядре. Изменения флагов приходят событиями моста
`ghostMode` / `hideReadReceipts` (`text` — `on` / `off`), так экран видит и переключение с
другого места.

Подпись под блоком (коротко и честно):

- отправленные сообщения и реакции видны как обычно — режим их не прячет;
- у собеседника сообщения остаются непрочитанными;
- выключение отметок ничего не отправляет задним числом: уже прочитанное на этом устройстве у
  собеседника останется непрочитанным, пока не придёт новое сообщение и его не прочитают.

Флаги — настройка устройства в ядре: выход из аккаунта и вход другим их не сбрасывают.

## 3. Свой статус в шапке

- **Где.** `SettingsView`, шапка, строка под номером: точка (зелёная — в сети, серая — нет) и
  текст. Скрыта, если «Показывать мой онлайн» выключено или статус неизвестен.
- **Текст.** Правила `test-fixtures/presence` для шапки чата, со строчной: «в сети»,
  «был(а) 5 минут назад», «был(а) в 12:40», «был(а) вчера в 09:05», «был(а) недавно» и т. д.
  Пересчитывается раз в минуту (`TimelineView(.everyMinute)`).
- **Запрос.** `GhostControls.checkOwnPresence()` → `checkOwnPresence` моста: один свежий
  `CONTACT_PRESENCE` 35 со своим id в обход кэша статусов (`PresenceStore` и
  `CorePresenceService` не участвуют). Код и время визита переводятся тем же
  `Contact.Presence.server`, что и у остальных людей. Сервер промолчал о себе — статус
  неизвестен, строка не показывается. Ядро само не опрашивает: расписание — в приложении.
- **Когда спрашивать** (`GhostSettingsModel`):
  - каждые 15 с, пока шапка на экране, приложение не в фоне и строка включена;
  - сразу — при появлении шапки, при возврате приложения из фона и при включении строки;
  - сразу — при переключении режима призрака; если шапка в это время не видна (переключают в
    «Безопасности»), один запрос без опроса, чтобы по возвращении строка была свежей;
  - в фоне и вне шапки запросов нет. Поздний ответ старого запроса не перетирает новый.
- **Фон.** `RootView` → `AppContainer.setAppActive` по `scenePhase` (`.active` / `.background`)
  → `GhostSettingsModel.setAppForeground`.

## 4. Настройки MAX

Изменение — `setPrivacy(key, value)` (доступ строкой) или `setPrivacyFlag(key, enabled)` (флаги)
моста, то есть `CONFIG` 22 `{settings:{user:{<ключ>: <значение>}}}`; чтение — `config.user`
(`watchAccountSettings`, поля `IosAccountSettings`). Каждая строка открывает список вариантов
с галочкой; подзаголовок списка — вопрос настройки. Выбор применяется сразу и откатывается при
отказе (ошибка — под списком).

| Строка | Подзаголовок списка | Ключ | Варианты → значение |
|---|---|---|---|
| Безопасный режим | — (переключатель) | `SAFE_MODE` | `true` / `false` |
| Найти меня по номеру | Кто может найти меня по номеру телефона | `SEARCH_BY_PHONE` | «Могут все» `ALL`, «Могут контакты» `CONTACTS` |
| Позвонить | Кто может мне звонить | `INCOMING_CALL` | «Могут все» `ALL`, «Могут контакты» `CONTACTS` |
| Пригласить в чат | Кто может пригласить меня в чат | `CHATS_INVITE` | «Могут все» `ALL`, «Могут контакты» `CONTACTS` |
| Показывать контент | Какой контент мне показывать | `CONTENT_LEVEL_ACCESS` | «Весь» `false`, «Безопасный» `true` |
| Видеть статус «в сети» | Кто может видеть, когда я в сети | `HIDDEN` | «Контакты» `false`, «Никто» `true` (с подтверждением: «Вы тоже перестанете видеть, кто в сети») |
| Видеть мой номер | Кто может видеть мой номер телефона | `PHONE_NUMBER_PRIVACY` | «Могут все» `ALL`, «Могут контакты» `CONTACTS`, «Никто» `NOBODY` |

- Значение вне списка (сервер допускает `NOBODY` у звонков и приглашений) показывается
  строгим вариантом списка — «Могут контакты».
- «Никто» уходит как `NOBODY`; `_NONE_` сервера ядро читает как `NOBODY`.
- **Значения по умолчанию** (ключа нет в `config.user`) — как у веб-клиента MAX, их
  подставляет ядро (`PrivacyConfig`): номер — `CONTACTS`, поиск, звонки и приглашения — `ALL`.
  `AccountSettings.unknown` в приложении такой же.
- **Блокировка.** Пока включён безопасный режим, четыре строки под ним (поиск по номеру,
  звонки, приглашения, контент) не открываются, под секцией: «Отключите безопасный режим, чтобы
  изменить эту настройку». При семейной защите `MANAGEABLE`: «Этой настройкой управляет
  семейная защита», и безопасный режим тоже не переключается. Остальное решает ядро:
  `privacyLocked` из настроек и `isPrivacyReadOnly(key)` — «Эту настройку сейчас нельзя
  изменить». «Информация» блокируется, только если так скажет ядро.
- Безопасный режим — `setPrivacyFlag("SAFE_MODE", …)`: включение ядро шлёт набором
  (`SAFE_MODE`, `SAFE_MODE_NO_PIN`, `CONTENT_LEVEL_ACCESS` и три `CONTACTS`), выключение — двумя
  флагами. Пока он включён, ядро отдаёт для четырёх строк принудительные значения.

## 5. Семейная защита

Строка сразу под паролем показывает `FAMILY_PROTECTION`: `OFF` — «Отключена», `ADMIN` — «Вы
администратор», `MANAGEABLE` — «Профиль под защитой», `UNKNOWN` — «Неизвестно» (сервер прислал
другое; само значение — `familyProtectionRaw`). Мост отдаёт имя перечисления
`FamilyProtection` ядра, приложение берёт его как есть (`FamilyProtection(rawValue:)`).

Бот защиты приходит в `config.server["family-protection-botid"]` (`familyProtectionBotId`).
Если id непустой и это число больше нуля, `PrivacySettingsModel.familyProtectionApp` отдаёт
`BotAppRequest(botId:, chatId: "", title: "Семейная защита")`, строка становится кнопкой и
открывает мини-приложение бота в `MiniAppSheet` через `AppContainer.botAppModel` →
`launchBotApp`. Без бота строка только показывает статус.

## 6. Устройство кода

| Слой | Что |
|---|---|
| Domain | `FamilyProtection` (с `unknown`), `PrivacyKey` (`guarded` — четыре блокируемых ключа), `PrivacyValue`; `AccountSettings`: `searchByPhone`, `incomingCall`, `chatsInvite`, `safeContentOnly`, `familyProtection`, `familyProtectionRaw`, `privacyLocked`, `showReadMark`, `value(for:)` / `set(_:_:)`; протоколы `GhostControls`, `PrivacyControls`, `SelfCheckStore` (`Protocols/PrivacyControls.swift`) |
| Data | `GhostPrivacyCore` (узкий вход в мост, `KMP/CoreGhostPrivacy.swift`), `CoreGhostPrivacyControls` (адаптер, обе стороны), `UserDefaultsSelfCheckStore` и `GhostDefaultsMigration` (`Storage/SelfCheckDefaults.swift`), `UnavailablePrivacyControls` (до сборки зависимостей); события `CoreEvent.Kind.ghostMode` / `.hideReadReceipts` |
| Presentation | `GhostSettingsModel` (переключатели, опрос, текст шапки), `PrivacySettingsModel` (блокировки, выбор с откатом), `PrivacyRow` и `PrivacyOption` (порядок, подписи, значения) |
| App | `SecurityView` (секции), `PrivacyViews.swift` (`PrivacyRowLink`, `PrivacyChoiceView`, `PrivacyPartHeader`, `OwnPresenceLine`), `SettingsView` (строка в шапке, видимость), `AppContainer` (сборка, фон, разовая чистка), `MaxIosCore+Settings` (методы моста и поля `IosAccountSettings`, `extension MaxIosCore: GhostPrivacyCore`) |

Протоколы приложения:

```swift
protocol GhostControls: Sendable {
    func ghostMode() -> Bool
    func setGhostMode(_ enabled: Bool) async
    func hideReadReceipts() -> Bool
    func setHideReadReceipts(_ hidden: Bool) async
    func ghostChanges() -> AsyncStream<GhostState>        // события ядра ghostMode / hideReadReceipts
    func checkOwnPresence() async throws(OrbitleError) -> Contact.Presence
    func localReadMark(chatId: String) -> Int64            // 0 — чат не читали только локально
}

protocol PrivacyControls: Sendable {
    func privacySettings() -> AsyncStream<AccountSettings>
    func setPrivacy(_ key: PrivacyKey, _ value: PrivacyValue) async throws(OrbitleError) -> AccountSettings
    func isPrivacyReadOnly(_ key: PrivacyKey) -> Bool
}
```

## 7. Мост ядра

`CoreGhostPrivacyControls` (OrbitleData) реализует оба протокола поверх `GhostPrivacyCore`;
в приложении это `MaxIosCore` (`MaxIosClient` из `MaxlyCore`). Адаптер ничего не хранит:

| Протокол приложения | Мост `MaxIosClient` |
|---|---|
| `ghostMode()` / `setGhostMode(_:)` | `ghostMode()` / `setGhostMode(enabled:)` |
| `hideReadReceipts()` / `setHideReadReceipts(_:)` | `hideReadReceipts()` / `setHideReadReceipts(enabled:)` |
| `ghostChanges()` | текущие флаги, затем `watchEvents` → `ghostMode` / `hideReadReceipts` (`text` `on` / `off`; незнакомый текст — флаг перечитывается). Подписка открывается раньше чтения флагов |
| `checkOwnPresence()` | `checkOwnPresence(onResult:)` → `IosPresence?` → `CorePresence` → `Contact.Presence`; `nil` — «неизвестно»; ошибка ядра — `OrbitleError` (`CoreMapping`). До входа (`currentUserId()` пуст) мост не зовётся: он ждал бы сессию, а `MaxClient` бросает «not logged in»; ответ — «неизвестно» |
| `localReadMark(chatId:)` | `localReadMarkOf(chatId:)` |
| `setPrivacy(_:_:)` | доступ — `setPrivacy(key:value:)`, флаг — `setPrivacyFlag(key:enabled:)`. `NOBODY` ядро (`PrivacyConfig.payload`) принимает только у `PHONE_NUMBER_PRIVACY`; у `SEARCH_BY_PHONE`, `INCOMING_CALL`, `CHATS_INVITE` — только `ALL` / `CONTACTS`, и списки этих строк `NOBODY` не предлагают. Значение не того вида или `NOBODY` не у номера в ядро не уходит (`invalidRequest`) |
| `isPrivacyReadOnly(_:)` | `isPrivacyReadOnly(key:)` |
| `privacySettings()` | `accountSettings()` (`watchAccountSettings`) |

Отметки о прочтении экран чата шлёт по увиденному ([`read-marks.md`](read-marks.md)) —
`markRead(chatId:messageId:mark:)` → `markReadAt`, который в ядре идёт через
`MaxClient.markRead`: при скрытых отметках сеть не трогается, а ответ — локальный. Местную
отметку (`localReadMark`) `AppContainer` подключает к `ChatRepositoryImpl.setLocalReadMarks`:
своя позиция чата — самая свежая из ответа сервера, пуша и местной, и разделитель
непрочитанных идёт за ней. Счётчики чатов, которые приходят из ядра (список, события
`chat`), уже учитывают локальное прочтение. Прежние `setPhonePrivacy` / `setOnlineHidden` /
`setSafeMode` (`AccountSettingsModel`) в ядре тоже идут через `setPrivacy`.

**Разовая чистка.** До ядра флаги и выбор приватности лежали в `UserDefaults`
(`orbitle.ghost.*`, `orbitle.privacy.local.*`). `GhostDefaultsMigration.run()` при запуске
(`AppContainer.init`) один раз удаляет эти ключи; «Показывать мой онлайн» переезжает на
`maxly.settings.showsOwnPresence`. Отметка выполнения — `maxly.migrations.ghostCore`.

Что ещё открыто:

1. Подтверждение входа по QR шлёт `PING {interactive:true}` — проверить, как это сочетается с
   режимом призрака.
2. `SHOW_READ_MARK` ядро только читает (`showReadMark`), переключателя для него нет.
3. Если сервер не вернёт запись о себе в ответе 35, строка в шапке скрыта — проверить на
   сервере, бывает ли так.
4. Мини-приложение семейной защиты открывается, только если сервер прислал `family-protection-botid`.

## 8. Тесты

- `GhostSettingsTests` (OrbitlePresentation): опрос раз в 15 с на ручных часах
  (`ManualSleeper`), остановка вне экрана и в фоне, запрос при возврате, при переключении
  режима и при включении строки, текст шапки, флаги из события.
- `PrivacySettingsTests`: порядок строк и ключи, подписи и значения вариантов, значение вне
  списка, подтверждение «Никто», имена `FamilyProtection` и `NOBODY`, значения по умолчанию,
  блокировка безопасным режимом, `MANAGEABLE`, `privacyLocked` и `isPrivacyReadOnly`,
  безопасный режим под семейной защитой, выбор с откатом, ошибки, бот семейной защиты
  (`familyApp`: id бота → запрос мини-приложения, пустой или нулевой id → строки-кнопки нет).
- `PrivacyControlsTests` (OrbitleData, фейк моста `GhostPrivacyCore`): флаги уходят в ядро,
  поток флагов из событий (чужие события, незнакомый текст), свой статус (в сети, был(а),
  молчание сервера, ошибка), `setPrivacy` / `setPrivacyFlag` со строками ключей, значение не
  того вида и отказ ядра, `isPrivacyReadOnly` и `localReadMark`, поток настроек;
  `GhostDefaultsTests` — «Показывать мой онлайн» и разовая чистка ключей.
- `ScreenReadMarkTests` (OrbitleData): своя позиция с местной отметкой ядра;
  `ReadMarkFlowTests` (OrbitlePresentation): разделитель по своей позиции. Остальные тесты
  отметки прочтения — в [`read-marks.md`](read-marks.md#5-тесты).

## 9. Проверка на устройстве

1. Режим призрака включён: второй аккаунт не видит «в сети», набор, запись, загрузку и
   стикеры; строка в шапке через 15 с — «был(а) …». Выключен — «в сети» сразу.
2. Отметки выключены: у собеседника сообщения непрочитанные, у себя счётчик обнулён;
   включение назад ничего не отправляет.
3. Строки MAX меняются и совпадают с официальным клиентом; при безопасном режиме четыре строки
   заблокированы; профиль под семейной защитой — тоже.

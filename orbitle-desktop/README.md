# Orbitle для компьютера

Клиент Orbitle для Windows, macOS и Linux: Kotlin и Compose Multiplatform. Рабочий клиент с
тем же набором возможностей, что у Android и iOS; логика и экран звонка общие с Android. Окно устроено как у настольного мессенджера: слева
вкладки, рядом список чатов и открытая переписка.

Сеть, протокол, вход и хранение сессии — в общем ядре
[max-kmp-core](https://github.com/fighxy/max-kmp-core). В сборку входят его исходники для JVM
(`commonMain`, `jvmMain`, `jvmAndroidShared`), ревизия записана в `core.lock`. Клиент
представляется сервису Android-устройством (`DeviceProfile.android` ядра). Сессия лежит в
пространстве `orbitle-desktop` и не пересекается с приложением на телефоне.

## Запуск

Нужны JDK 17+ и ядро в `../.build/max-kmp-core`. Если каталога нет, из корня репозитория:

```powershell
.\scripts\fetch-core.ps1
```

Дальше из `orbitle-desktop`:

```powershell
.\gradlew.bat run
.\gradlew.bat jvmTest
```

Кэш, настройки и черновики — в `~/.orbitle`. Скачанные файлы сохраняются в «Загрузки».
Голосовые, кружки и видео используют `ffmpeg` из PATH. Встроенный проигрыватель (`DesktopVideoPlayer`)
берёт у ffmpeg кадры RGBA (поток PAM, до 960 точек по длинной стороне, 30 кадров в секунду) и звук PCM
для Java Sound; удалённый ролик сначала скачивается в кэш. Без ffmpeg голосовое уходит как WAV, видео
открывается системным проигрывателем, видео истории показывает обложку.

## Что готово


- **Вход:** номер с маской и страной, SMS-код, повтор, облачный пароль, регистрация, восстановление сессии, панель ограничений нового сеанса.
- **Чаты:** закрепление и перестановка закреплённых, папки, превью, черновики, «печатает…», поиск, плашка соединения. Шапка как на iOS (общая с Android, `orbitle-compose/.../ChatListHeader.kt`): поиск и папки капсулами, «таблетка» выбранной папки, истории спрятаны над поиском со стопкой аватаров у заголовка; колесо у верха возвращает поиск и истории, подъём списка уводит поиск, папки остаются.
- **Переписка:** история, ответы, пересылка, фото, видео, голосовые, файлы, контакты, стикеры, звонки, реакции, правка, удаление, комментарии, прочтение, приватный режим. Поиск по чату, звонок, «Участники и жалоба», очистка и удаление — в профиле чата; поле ввода только там, где можно писать; в канале вместо него «Выключить звук» / «Включить звук», вне списка — «Подписаться» / «Вступить». История листается вверх без предела: стор ядра больше не обрезает старые страницы. Разделитель «Непрочитанные сообщения» (чат открывается на нём), превью ссылок, inline-кнопки ботов (ответ бота, ссылки, копирование, мини-приложение) и «Открыть приложение» у ботов с мини-приложением.
- **Истории:** полоса над списком чатов («Ваша история», кольца: сначала непросмотренные), кольца на аватарах личных чатов, в шапке и профиле; просмотр на весь экран (полосы прогресса, касание слева — назад, справа — вперёд, удержание — пауза, Escape или свайп вниз — закрыть, вбок — к соседнему владельцу, удаление своей), публикация фото или видео на сутки всем или контактам (видео в предпросмотре играет без звука по кругу). Видео истории играет встроенный проигрыватель.
- **Клавиатура:** Enter отправляет, Shift+Enter — новая строка (в настройках можно Ctrl+Enter); ↑ в пустом поле — правка своего последнего; Ctrl+↑/↓ — ответ на сообщение выше или ниже; Esc отменяет ответ, правку, закрывает окна и чат; Alt+↑/↓, Ctrl+Tab, Ctrl+PageUp/PageDown — соседний чат; Ctrl+1…9 — папки; Ctrl+0 — «Избранное»; Ctrl+K — поиск по чатам, Ctrl+F — поиск в открытом чате; Ctrl+N — новое сообщение; Ctrl+O — вложение; PageUp/PageDown — лента на экран; Ctrl+End — к последнему; Ctrl+, — настройки; Ctrl+Q — выход. В просмотре фото: ←/→, R — повернуть, Ctrl+S — сохранить. Сочетания работают в любой раскладке (Ctrl+F = Ctrl+А), на macOS вместо Ctrl — ⌘. Звонки: Ctrl+Shift+A — ответить, Ctrl+Shift+H — завершить, Ctrl+D — микрофон, Ctrl+E — камера; Ctrl+Shift+R — записать голосовое или кружок (повторно — отправить, Esc — отменить). Мышь: рука над кнопками, правый клик по чату и звонку — меню, колесо над папками листает их, над шапкой — прячет и возвращает поиск и истории. Список — в «Настройки → Клавиатура» (`ui/keys/Hotkeys.kt`, `KeyboardSettings.kt`).
- **Частота запросов:** после `too.many.requests` фоновые чтения на паузе (15 с, до 2 минут), свежая история 10 секунд не перезапрашивается, общие медиа профиля идут по одной странице.
- **Голосовые и кружки:** кнопка справа — микрофон или камера, короткое нажатие меняет режим, удержание пишет, влево — отмена, вверх — закрепить. Кружок: камера через webrtc-java, звук через Java Sound, ffmpeg собирает квадрат 480×480 H.264/AAC (как у телефона), до минуты, превью кругом над полем.
- **Звонки, как на iOS:** позвонить из профиля чата (звонок и видео), перезвонить из журнала, ответить и отклонить входящий (окно поднимается поверх остальных), групповой звонок по ссылке («Создать звонок», «Присоединиться»), SFU с плитками участников, микрофон, камера (первая или вторая), показ всего экрана, запись для админа, переподключение, плашка свёрнутого звонка, гудки и звонок входящего через Java Sound. WebRTC — `dev.onvoid.webrtc:webrtc-java` с нативной библиотекой своей ОС (`calls/DesktopCallMedia.kt`); без звуковой системы звонок идёт без звука, а не падает. Протокол и экран звонка — общие с Android. Журнал: пропущенные, удаление на сервере, перечитывание после звонка и переподключения.
- **Контакты:** открытие диалога из контакта.
- **Настройки:** профиль, конфиденциальность, чёрный список, устройства, оформление (тема, размер текста, обои «Осень»), клавиатура (клавиша отправки и все горячие клавиши), память, папки, о программе, выход, QR профиля.

## Чем десктоп отличается от телефона

- Список и чат открыты рядом. Escape закрывает верхний экран: профиль, вложенные настройки, выбранный чат.
- Камера есть только для звонков и кружков. Вход по QR — вставка ссылки или картинка с кодом.
- Фото и файлы выбираются системным диалогом. Фото профиля кадрируется в квадрат без поворота EXIF.
- Видео играет встроенный проигрыватель на ffmpeg: в просмотре — пауза касанием, перемотка и время внизу;
  кружок — картинка и звук прямо в ленте с кольцом прогресса. Без ffmpeg видео открывается внешней программой.
- «Поделиться» копирует ссылку в буфер обмена.

## Ghost mode, privacy and activity

The core is pinned to max-kmp-core `1364e91` in `core.lock`. Everything below runs through it.

- **Connection:** the core owns the keepalive and reconnects. It sends `PING` every 29 s (the
  first right after login), answers the server's `PING`, follows a server `RECONNECT` (op 3, only
  to `oneme.ru` hosts) and backs off reconnects from 3 s to 96 s with ±10 % jitter. Neither
  server `PING` nor `RECONNECT` reaches `pushes`; the app has no ping or reconnect code of its own.
- **Login rejection:** when the server refuses the stored token (`ClientState.TokenRejected`),
  the app never shows an empty chat list. `login.token` and `login.blocked`: the core has cleared
  the token, so the app also clears its own session state (chats, caches, last user id, feed
  positions) and goes to the login screen with the notice above the phone number field.
  `login.flood`: the token is kept and nothing is cleared; the app stays signed in and shows the
  saved chat list offline with a banner at the top: "Retry" (log in again with the same token,
  `AuthService.retryLogin`) and "Log out". The banner goes away once the client is online again;
  an open chat behaves as offline meanwhile. The notice shows the server's `title` and
  `localizedMessage` (or `description`) first and falls back to our own Russian text per reason
  (`LoginNotices`, `SessionRejection`, `AuthService.throttled`).
- **Server error texts:** when an error reply carries text for the user, the app shows it:
  `title`, else `localizedMessage` (the core's `MaxError.serverText` /
  `ServerErrorException.displayText`). It reaches the screen through `CoreFailure.serverText`,
  `OrbitleError.Server.text` and `CoreErrors.text(error, fallback)`; login steps, the recovery
  email and reactions do the same. Our own Russian strings are only the fallback when the server
  sent nothing.
- **Ghost mode and hidden read receipts** are two independent core flags (`MaxClient.ghostMode`,
  `MaxClient.hideReadReceipts`). The core stores them, applies them and publishes them in
  `MaxState.ghostMode` / `MaxState.hideReadReceipts`; chats read under hidden receipts are kept
  locally by the core (`MaxState.localReads`). The old local keys `ghostMode.enabled` and
  `ghostMode.hideReadReceipts` are moved into the core once at startup and then deleted
  (`CoreGhostModeRepository.migrate`).
- **Read marks and story views** go only through `client.markRead` and `client.markStorySeen`.
  Sending those opcodes directly is stopped by the core's `OutboundGuard` with
  `OutboundBlockedException`.
- **Own presence:** `client.checkOwnPresence` (opcode 35, always a fresh request). It throws
  before login (the app returns `null` without asking); `null` means the server has no record.
  The own profile asks once a minute (60 s) while it is visible and the app is in the foreground.
- **Privacy:** writes go through `client.setPrivacy(key, value)`. Search by phone, calls and
  chat invites accept only `ALL` or `CONTACTS`; `NOBODY` is allowed only for phone number
  privacy. The Security screen shows the family protection status; while it is `MANAGEABLE` the
  privacy items are read-only.
- **Transport:** TCP + TLS through the core, no WebSocket. Default host `api.oneme.ru`
  (`api2.oneme.ru` is a CNAME of it with a Russian Trusted CA certificate; we keep `api`).
- **App activity** is reported with `client.setInteractive`: active while the window is visible,
  focused and had input within the last 60 s (`WindowActivity`), or while a call is in progress,
  even with the window minimized or unfocused (`AppActivity.desktop`).
- **No read marks in the background:** the window lifecycle is `RESUMED` only while the window is
  shown and focused, `STARTED` otherwise, so a minimized or unfocused window marks nothing read.
- **Read marks** (rule agreed with iOS, constants in `ReadMarkRules`): a message counts as seen
  only when at least 30 % of its height is inside the feed viewport; the top bar, the input field
  and the on-screen keyboard are outside it, and the feed's content padding under overlays does
  not count either (`ReadVisibility`). Only the newest seen message is marked: the mark is sent
  200 ms after the candidate last changed, a newer candidate replaces a pending one, and a mark
  older than the one already sent never goes out. Leaving the screen cancels a pending mark.
- **Unread divider:** it follows the account's own read mark, and the local mark
  (`MaxState.localReads`, kept by the core while read receipts are hidden) wins when it is newer
  than the server mark, so the divider stays put when the server never got ours.

## Устройство

Один модуль, точка входа `app.orbitle.MainKt`.

| Пакет | Что внутри |
|---|---|
| `domain`, `data`, `presentation` | те же модели, репозитории и ViewModel, что у Android |
| `ui` | экраны Compose |
| `platform` | пути, файл настроек, диалоги, буфер, Escape |
| `media` | кэш, загрузка, голос, вложения, внешнее видео |

Логика `presentation` и `data` проверяется `jvmTest`, без эмулятора.

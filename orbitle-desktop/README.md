# Maxly для компьютера

Клиент Maxly для Windows, macOS и Linux: Kotlin и Compose Multiplatform. Рабочий клиент с
тем же набором возможностей, что у Android и iOS; логика и экран звонка общие с Android. Окно устроено как у настольного мессенджера: слева
вкладки, рядом список чатов и открытая переписка.

Сеть, протокол, вход и хранение сессии — в общем ядре
[maxly-core](https://github.com/fighxy/maxly-core). В сборку входят его исходники для JVM
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

Кэш, настройки и черновики — в `~/.maxly`. При первом запуске после переименования, если
`~/.maxly` ещё нет, а `~/.orbitle` есть, старый каталог переносится на новое место (если
переименовать нельзя — копируется), так что вход и настройки сохраняются
(`platform/DataDirMigration.kt`). Скачанные файлы сохраняются в «Загрузки».
Голосовые, кружки и видео используют `ffmpeg` из PATH. Встроенный проигрыватель (`DesktopVideoPlayer`)
берёт у ffmpeg кадры RGBA (поток PAM, до 960 точек по длинной стороне, 30 кадров в секунду) и звук PCM
для Java Sound; удалённый ролик сначала скачивается в кэш. Без ffmpeg голосовое уходит как WAV, видео
открывается системным проигрывателем, видео истории показывает обложку.

## Что готово


- **Вход:** номер с маской и страной, SMS-код, повтор, облачный пароль, регистрация, восстановление сессии, панель ограничений нового сеанса.
- **Чаты:** закрепление и перестановка закреплённых, папки, превью, черновики, «печатает…», поиск, плашка соединения. У диалога с ботом, у которого есть мини-приложение, в строке кнопка «Открыть»: она открывает мини-приложение сразу, остальная строка открывает чат, высота строки не меняется. Шапка как на iOS (общая с Android, `orbitle-compose/.../ChatListHeader.kt`): поиск и папки капсулами, «таблетка» выбранной папки, истории спрятаны над поиском со стопкой аватаров у заголовка; колесо у верха возвращает поиск и истории, подъём списка уводит поиск, папки остаются.
- **Переписка:** история, ответы, пересылка, фото, видео, голосовые, файлы, контакты, стикеры, звонки, реакции, правка, удаление, комментарии, прочтение, приватный режим. Поиск по чату, звонок, «Участники и жалоба», очистка и удаление — в профиле чата; поле ввода только там, где можно писать; в канале вместо него «Выключить звук» / «Включить звук», вне списка — «Подписаться» / «Вступить». История листается вверх без предела: стор ядра больше не обрезает старые страницы. Разделитель «Непрочитанные сообщения» (чат открывается на нём), превью ссылок, inline-кнопки ботов (ответ бота, ссылки, копирование, мини-приложение) и «Открыть приложение» у ботов с мини-приложением. Закреп берётся из чата и пуша 243 (список 240/241 мобильный сервер не знает и не запрашивается): плашка «Закреплённое сообщение 2 из 3» — касание переходит к сообщению и листает к следующему, крестик снимает показанное, «Открепить все» — все; в меню сообщения «Закрепить у всех» / «Закрепить только у меня» в личном чате и «Закрепить и уведомить» / «Закрепить без уведомления» в группе и канале, «Открепить» у закреплённого. Закрепы, своя реакция и профиль, изменённые на другом устройстве, подтягиваются по пушам; готовая расшифровка голосового приходит пушем `TranscriptionReady`; вложение, которое сервер не принял, сразу встаёт «не отправлено» с повтором (ядро сопоставляет отказ с загрузкой по id вложения). Отложенные: долгое нажатие на «Отправить» (или «Отложить» в меню вложений) — «Через час», «Завтра в 9:00» или свой день и время; в том же листе список отложенных чата с «Изменить» (текст и время) и «Отменить», не ушедшие помечены «не отправилось», список правится пушами; отправить отложенное сразу ядро не умеет. Опросы: голос касанием, в опросе с несколькими ответами — отметки и «Голосовать»; закрытый опрос и уже отданный голос без переголосования только показывают итог; счётчики перезапрашиваются (код 306), когда чат на экране, и после голоса — пуша нет.
- **Истории:** полоса над списком чатов («Ваша история», кольца: сначала непросмотренные), кольца на аватарах личных чатов, в шапке и профиле; просмотр на весь экран (полосы прогресса, касание слева — назад, справа — вперёд, удержание — пауза, Escape или свайп вниз — закрыть, вбок — к соседнему владельцу, удаление своей), публикация фото или видео на сутки всем или контактам (видео в предпросмотре играет без звука по кругу). Видео истории играет встроенный проигрыватель. «Мои истории» — свой архив (219, страницы по 30) сеткой, пустой архив предлагает «Создать историю»; пункт виден, только если сервер включил `stories-history`: в настройках после «Избранного» и в меню своего кружка в полосе историй («Открыть мои истории»).
- **Клавиатура:** Enter отправляет, Shift+Enter — новая строка (в настройках можно Ctrl+Enter); ↑ в пустом поле — правка своего последнего; Ctrl+↑/↓ — ответ на сообщение выше или ниже; Esc отменяет ответ, правку, закрывает окна и чат; Alt+↑/↓, Ctrl+Tab, Ctrl+PageUp/PageDown — соседний чат; Ctrl+1…9 — папки; Ctrl+0 — «Избранное»; Ctrl+K — поиск по чатам, Ctrl+F — поиск в открытом чате; Ctrl+N — новое сообщение; Ctrl+O — вложение; Ctrl+V (Shift+Insert) в поле — скриншот или скопированные в проводнике файлы вложениями, текст как обычно; PageUp/PageDown — лента на экран; Ctrl+End — к последнему; Ctrl+, — настройки; Ctrl+Q — выход. В просмотре фото: ←/→, R — повернуть, Ctrl+S — сохранить. Сочетания работают в любой раскладке (Ctrl+F = Ctrl+А), на macOS вместо Ctrl — ⌘. Звонки: Ctrl+Shift+A — ответить, Ctrl+Shift+H — завершить, Ctrl+D — микрофон, Ctrl+E — камера; Ctrl+Shift+R — записать голосовое или кружок (повторно — отправить, Esc — отменить). Мышь: рука над кнопками, правый клик по сообщению, чату и звонку — меню (по отпусканию кнопки), колесо над папками листает их, над шапкой — прячет и возвращает поиск и истории. Список — в «Настройки → Клавиатура» (`ui/keys/Hotkeys.kt`, `KeyboardSettings.kt`).
- **Частота запросов:** после `too.many.requests` фоновые чтения на паузе (15 с, до 2 минут), свежая история 10 секунд не перезапрашивается, общие медиа профиля идут по одной странице.
- **Голосовые и кружки:** кнопка справа — микрофон или камера, короткое нажатие меняет режим, удержание пишет, влево — отмена, вверх — закрепить. Кружок: камера через webrtc-java, звук через Java Sound, ffmpeg собирает квадрат 480×480 H.264/AAC (как у телефона), до минуты, превью кругом над полем.
- **Звонки, как на iOS:** позвонить из профиля чата (звонок и видео), перезвонить из журнала, ответить и отклонить входящий (окно поднимается поверх остальных), групповой звонок по ссылке («Создать звонок», «Присоединиться»), SFU с плитками участников, микрофон, камера (первая или вторая), показ всего экрана, запись для админа, переподключение, плашка свёрнутого звонка, гудки и звонок входящего через Java Sound. WebRTC — `dev.onvoid.webrtc:webrtc-java` с нативной библиотекой своей ОС (`calls/DesktopCallMedia.kt`); без звуковой системы звонок идёт без звука, а не падает. Протокол и экран звонка — общие с Android. Журнал: пропущенные, удаление на сервере, перечитывание после звонка и переподключения; источник — `CALL_HISTORY` 163 (курсор, `reset` заменяет журнал) с пушем 165, при отказе 163 — прежний 79. «Отклонить» входящий шлёт и отбой на сервер (167, `REJECTED`).
- **Контакты:** открытие диалога из контакта.
- **Настройки:** профиль, конфиденциальность, чёрный список, устройства, оформление (тема, размер текста, обои «Осень»), клавиатура (клавиша отправки и все горячие клавиши), память, папки, о программе, выход, QR профиля.
- **Журнал и сбои:** журнал пишется в `~/.maxly/logs/app.log` (до пяти файлов по мегабайту) вместе с выводом `System.out` и `System.err`: у установленной сборки Windows консоли нет. Отчёты — в `~/.maxly/crashes`: необработанное исключение, ошибка корутины, зависание окна (поток окна не отвечает 5 с — в отчёт идут стеки всех потоков с удерживаемыми мониторами, `diagnostics/UiWatchdog.kt`, `ThreadDump.kt`) и запуск, который не дошёл до штатного выхода (процесс сняли из диспетчера задач или он упал в нативном коде; `hs_err_pid*.log` прикладывается). В журнале нет текста переписки. «Настройки → О приложении → Диагностика»: открыть папку журнала, сохранить журнал в «Загрузки», прочитать, скопировать и удалить отчёты.
- **Фото:** в ленте адрес выбирается по ширине после обрезки ячейки и плотности не ниже 2 (на Windows с масштабом 100 % иначе мыльно), просмотр декодирует оригинал целиком — приближение до 5× остаётся чётким. Меню «Прикрепить» выпадает у скрепки, кнопка «Новое сообщение» — маленькая, размером с пункт панели.
- **Окно:** открывается там, где его закрыли, с тем же размером и развёрнутым, если было развёрнуто; если экран с окном отключили — по центру оставшегося (`platform/WindowPlacement.kt`). Листы и меню — слои в том же окне (`ui/components/AppSheet.kt`): отдельное модальное окно ОС на Windows вешало приложение по правому клику в чате. Меню по правой кнопке открывается, когда кнопку отпустили. «Семейная защита» в «Безопасности» открывает мини-приложение бота из конфига (`family-protection-botid`); без бота строка только показывает статус.

## Чем десктоп отличается от телефона

- Список и чат открыты рядом. Escape закрывает верхний экран: профиль, вложенные настройки, выбранный чат.
- Камера есть только для звонков и кружков. Вход по QR — вставка ссылки или картинка с кодом.
- Фото и файлы выбираются системным диалогом. Фото профиля кадрируется в квадрат без поворота EXIF.
- Видео играет встроенный проигрыватель на ffmpeg: в просмотре — пауза касанием, перемотка и время внизу;
  кружок — картинка и звук прямо в ленте с кольцом прогресса. Без ffmpeg видео открывается внешней программой.
- «Поделиться» копирует ссылку в буфер обмена.

## Ghost mode, privacy and activity

The core is pinned to maxly-core `835d443` in `core.lock`. Everything below runs through it.

- **Connection:** the core owns the keepalive and reconnects. It sends `PING` every 29 s (the
  first right after login), answers the server's `PING`, follows a server `RECONNECT` (op 3, only
  to `oneme.ru` hosts) and backs off reconnects from 3 s to 96 s with ±10 % jitter. Neither
  server `PING` nor `RECONNECT` reaches `pushes`; the app has no ping or reconnect code of its own.
- **Images:** avatars ask the core for a square `fn` and photos for a width `fn`: the first step of the ladder that is not smaller than the view size in dp times the screen density (`ImageRequests`). A full-screen viewer and a file on disk keep the original URL. When the server turns on `photo-url-refresh`, an open chat refreshes expired photo URLs with opcode 203 (`MaxClient.refreshPhotoUrls`), at most the server's batch and not more than once a second; the new address replaces the photo in the feed.

- **Bot apps in the list:** a bot dialog with `Chat.hasWebApp` shows «Открыть» on the row. The button opens that bot's mini app immediately; the rest of the row opens the chat. The row height does not change.
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
  `MaxlyError.Server.text` and `CoreErrors.text(error, fallback)`; login steps, the recovery
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

Один модуль, точка входа `app.maxly.MainKt`.

| Пакет | Что внутри |
|---|---|
| `domain`, `data`, `presentation` | те же модели, репозитории и ViewModel, что у Android |
| `ui` | экраны Compose |
| `platform` | пути, файл настроек, диалоги, буфер, Escape |
| `media` | кэш, загрузка, голос, вложения, внешнее видео |

Логика `presentation` и `data` проверяется `jvmTest`, без эмулятора.

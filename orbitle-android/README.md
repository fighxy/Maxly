# Maxly для Android

Нативный Android-клиент Maxly: Kotlin, Jetpack Compose и Material 3. Рабочий клиент с тем же
набором возможностей, что у [iOS](../orbitle-ios/README.md) и компьютера, внешний вид — родной
для Android. Сеть, протокол, вход и хранение сессии — в общем ядре
[maxly-core](https://github.com/fighxy/maxly-core) (Android-цель), клиент представляется
сервису Android-устройством (`DeviceProfile.android` ядра).

## Скачать

Последняя зелёная сборка `main` — в пререлизе `android-latest`, ссылка постоянная:
https://github.com/fighxy/Maxly/releases/download/android-latest/Maxly.apk. Её можно
открыть прямо на телефоне: браузер скачает `.apk`, остаётся разрешить установку из этого
источника. На переходный период тот же файл лежит и под прежним именем `Orbitle.apk`.

**Переход с Orbitle.** У Maxly новый идентификатор приложения (`app.maxly.android`), поэтому
Maxly ставится отдельным приложением рядом со старым Orbitle, а не поверх него. В Maxly нужно
войти заново; после входа старое приложение Orbitle можно удалить.

Сборки подписаны одним ключом, поэтому новая версия Maxly ставится поверх предыдущей без потери входа.
Если в репозитории есть секрет `ORBITLE_KEYSTORE_BASE64` (с `ORBITLE_KEYSTORE_PASSWORD`,
`ORBITLE_KEY_ALIAS`, `ORBITLE_KEY_PASSWORD`), CI подписывает им; иначе — ключом разработки
`signing/orbitle-dev.keystore` (пароли `android`). Ключ разработки лежит в открытом
репозитории, поэтому для раздачи пользователям нужен свой ключ в секретах. Сменить ключ
можно только с переустановкой приложения.

## Что готово

- **Вход:** номер с маской и выбором страны (поиск по названию и коду), SMS-код с
  автоотправкой полного кода и повтором через 30 секунд, устаревший код заменяется новым,
  облачный пароль с подсказкой, регистрация нового аккаунта, восстановление сессии при
  запуске, «Сессия истекла» при отклонённом токене, панель ограничений нового сеанса.
- **Список чатов:** живой стор ядра, закреплённые сверху (закрепить, открепить и
  «Изменить порядок» долгим нажатием, перетаскивание за ручку), папки сервера с бейджами непрочитанных, превью как в iOS («Фотография»,
  «Голосовое сообщение», «Вы:» и имя автора в группах, пересланные, черновики, «печатает…»),
  галочки доставки и прочтения, «без звука», подтверждённые аккаунты, «в сети», поиск по
  загруженным чатам, плашка «Подключение…», потянуть вниз — обновить. У диалога с ботом, у которого есть мини-приложение, в строке кнопка «Открыть»: она открывает мини-приложение сразу, остальная строка открывает чат, высота строки не меняется.
- **Чат:** история из стора ядра с догрузкой старых страниц при прокрутке вверх (заранее, за
  20 строк до верха; без предела — стор ядра больше не обрезает старые страницы; страницу,
  которую листающий ждёт, пауза фоновых чтений не держит, отказ повторяется сам). В канале,
  где писать нельзя, вместо поля ввода «Выключить звук» / «Включить звук», вне списка —
  «Подписаться» / «Вступить»,
  разделители дней, пузыри своих и чужих сообщений с хвостом у последнего в серии, имена и
  аватары авторов в группах, время с «изм.» и галочки (отправляется, доставлено, прочитано,
  не ушло — нажать, чтобы повторить). Ответ с цитатой (нажатие прокручивает к оригиналу),
  пересланные, фото и видео по пропорциям или сеткой, голосовые с дорожкой, файлы, контакты,
  стикеры, звонки («Пропущенный звонок», длительность), служебные сообщения, разметка
  сервера и ссылки. Меню по долгому нажатию: быстрые реакции из каталога сервера, «Ответить»,
  «Копировать», «Изменить», «Пометить непрочитанным» (на сервере, чат закрывается), «Удалить»
  (у себя или у всех), «Закрепить» / «Открепить». Закреп берётся из чата и пуша 243
  (список 240/241 мобильный сервер не знает и не запрашивается), плашка над лентой «Закреплённое сообщение 2 из 3» — касание переходит к сообщению
  и листает к следующему, крестик снимает показанное, «Открепить все» — все. В личном чате
  можно закрепить «только у меня», в группе и канале — без уведомления. Закрепы, своя реакция и
  профиль, изменённые на другом устройстве, подтягиваются по пушам; готовая расшифровка
  голосового приходит пушем `TranscriptionReady`; вложение, которое сервер не принял, сразу встаёт
  «не отправлено» с повтором (ядро сопоставляет отказ с загрузкой по id вложения). Отложенные: долгое нажатие на «Отправить» (или «Отложить» в
  меню вложений) — «Через час», «Завтра в 9:00» или свой день и время; в том же листе список
  отложенных чата с «Изменить» (текст и время) и «Отменить», не ушедшие помечены «не
  отправилось»; список правится пушами. Отправить отложенное сразу ядро не умеет — кнопки
  нет. Опросы: голос касанием, в опросе с несколькими ответами — отметки и «Голосовать»;
  закрытый опрос и уже отданный голос без переголосования только показывают итог. Пуша
  счётчиков нет: они перезапрашиваются (код 306), когда чат на экране, и после голоса. Шапка: «в сети», «был(а) …»,
  «печатает…», число участников или подписчиков; кнопок справа нет — поиск по чату,
  звонок, «Участники и жалоба», очистка и удаление открываются из профиля чата. Поле ввода
  только там, где можно писать: в канале — владельцу и администраторам, в канал из поиска —
  никому. Отметка прочтения, пока чат открыт, кнопка «вниз». Чат с непрочитанными открывается
  на разделителе «Непрочитанные сообщения», он уходит после своего ответа. Превью ссылок
  (`SHARE`) в пузыре. Inline-кнопки ботов под пузырём: нажатие уходит боту (ответ — снекбаром
  или ссылкой), ссылки открываются, «копировать» кладёт текст в буфер, `OPEN_APP` открывает
  мини-приложение поверх чата; у бота с мини-приложением над полем ввода «Открыть приложение».
- **Шапка списка, как на iOS:** поиск капсулой, папки капсулой с бегущей
  «таблеткой» (едет за листанием страниц). Список встаёт на поиск, истории спрятаны над ним,
  у заголовка — стопка их аватаров (нажатие открывает полосу); потягивание у верха открывает
  истории, инерция останавливается на поиске; подъём списка уводит поиск, папки остаются.
  Без «потянуть, чтобы обновить». Общий код — `orbitle-compose/.../ChatListHeader.kt`, логика —
  `ChatListHeaderGeometry` (shared).
- **Истории:** полоса над поиском («Ваша история» с кнопкой новой, затем кольца:
  сначала непросмотренные, потом свежие), кнопка новой истории в шапке, кольца на аватарах личных чатов, в шапке чата и в
  профиле. Просмотр на весь экран: полосы прогресса, фото 5 секунд, видео по длине, касание
  слева — назад, справа — вперёд, удержание — пауза, свайп вниз — закрыть, вбок — к соседнему
  владельцу, продолжение с первой непросмотренной, удаление своей. Публикация фото или видео на
  сутки: всем или только контактам. Опкоды 208, 210, 214–216, 218. «Мои истории» — свой
  архив (219, страницы по 30 до пустого курсора) сеткой; пустой архив предлагает «Создать
  историю» (тот же выбор файла). Пункт виден, только если сервер включил `stories-history`:
  в настройках сразу после «Избранного» и в меню своего кружка в полосе историй (долгое
  нажатие — «Открыть мои истории»).
- **Частота запросов:** после ответа сервера `too.many.requests` фоновые чтения (история,
  комментарии, общие медиа, карточки, реакции, звонки) 15 секунд не уходят на сервер, пауза
  растёт до 2 минут при повторных отказах. Свежая страница истории 10 секунд не
  перезапрашивается, общие медиа профиля идут по одной странице с паузой 0,4 с. Чат с лентой
  в сторе не показывает такую ошибку и сам повторяет загрузку через 20 секунд.
- **Голосовые и кружки, как на iOS:** кнопка справа от пустого поля — микрофон или
  камера, короткое нажатие меняет режим (запоминается), удержание пишет сразу, полоса записи
  появляется через 150 мс; влево — отмена, вверх — закрепить, тогда отправляет та же кнопка.
  Кружок — фронтальная камера CameraX, квадрат по центру, до минуты, превью кругом над полем;
  уходит видеосообщением (`videoType` 1). Логика жеста общая: `RecordingController` (shared).
- **Звонки, как на iOS** (протокол — общий код `orbitle-shared/.../data/calls`, его
  тесты на фейковом сервере ws2 и фейковом WebRTC — `CallSessionTest`, `CallProtocolTest`,
  `CallCenterTest`): позвонить из чата или профиля (звонок и видео), перезвонить из журнала,
  ответить и отклонить входящий, групповой звонок по ссылке («Создать звонок»,
  «Присоединиться»), через сервер (SFU) с плитками участников, говорящим и поднятой рукой,
  микрофон, камера и её смена, громкая связь, показ экрана (MediaProjection), запись для админа,
  переподключение, плашка свёрнутого звонка. WebRTC — `io.github.webrtc-sdk:android`
  (`calls/AndroidCallMedia.kt`). Входящий — полноэкранное уведомление с «Ответить» и
  «Отклонить» и системной мелодией; разговор держит служба переднего плана (микрофон, камера,
  показ экрана), у уха экран гаснет, гудки — тон линии 425 Гц. Экран звонка общий с ПК:
  `orbitle-compose/.../ui/calls`. Журнал: история сервера, «Все» и «Пропущенные», соседние
  звонки одного собеседника одной строкой, бейдж непросмотренных пропущенных, «Удалить из
  истории» на сервере, перечитывается после звонка и после переподключения. Журнал берётся из
  `CALL_HISTORY` 163 (курсор: первый раз всё, потом только изменения, `reset` заменяет журнал)
  и правится пушем 165 без перезапроса; разрыв курсора — снова 163. Если 163 не ответил —
  прежний `VIDEO_CHAT_HISTORY` 79. «Отклонить» входящий шлёт и отбой на сервер (167, `REJECTED`).
- **Контакты:** синхронизация со списком сервера, разделы по буквам (кириллица, латиница,
  «#»), поиск по имени и цифрам номера, «в сети» и «был(а) …», нажатие открывает диалог,
  даже если его ещё нет в списке чатов.
- **Настройки:** шапка профиля со скрытым номером (кнопка-глаз), «Устройства» (сеансы и
  «Завершить другие сеансы»), «Избранное», «Контакты», «Оформление», «О приложении»,
  выход. «Уведомления и звук» — «Скоро». «Семейная защита» в «Безопасности» открывает
  мини-приложение бота из конфига (`family-protection-botid`); без бота строка только
  показывает статус.
- **Оформление:** образец переписки, размер текста семью шагами (14–23 пт, как в iOS),
  тема «Системная / Светлая / Тёмная», обои чата «Осень» (авто, светлые, тёмные, ночь) —
  те же картинки, что в iOS-версии.

## Устройство

Один модуль `app`, одна активность, Navigation Compose, ViewModel + StateFlow.

Пакеты Kotlin — `app.maxly.*`, `applicationId` — `app.maxly.android` (отладочная сборка —
`app.maxly.android.debug`). До переименования он был `app.orbitle.android`, поэтому Maxly
ставится рядом со старым Orbitle, а не поверх него.

| Пакет | Что внутри |
|---|---|
| `domain` | модели UI (`Chat`, `ChatFolder`, `Message` с вложениями, `AuthPhase`, `MaxlyError`) — как `OrbitleDomain` в iOS |
| `data` | мост к ядру: `MaxCoreGateway` (вызовы `MaxClient`, ошибки ядра → `CoreFailure`), `SessionManager` (шаги входа, попытки, выход), `ChatMapping` и `MessageMapping` (чаты и сообщения стора → модели, разбор вложений, цитат, пересылок и реакций), репозитории над `MaxClient.store` |
| `presentation` | логика экранов без Android UI: `AuthViewModel`, `PhoneNumber`, `PhoneCountry`, `ChatListFormatter`, `ChatListViewModel`, `ChatViewModel`, `CallBubbleText`, `ChatContentFormat`, `WaveformLayout` — перенесены из `OrbitlePresentation` iOS-клиента вместе с тестами |
| `ui` | Compose-экраны и тема Material 3 (подсветка кнопок и надписей: графит `#212327` в светлой теме, серебро `#CCD0D6` в тёмной; свои пузыри `#5C6BF5`; тёмный фон `#0C0E14`; палитра аватаров как в iOS) |

Логика `presentation` и `data` проверяется JVM-тестами (`app/src/test`), без эмулятора.

В отладочной сборке есть `DemoActivity` (`app/src/debug`): экраны на выдуманных данных,
чтобы проверить вёрстку без аккаунта (`screen`: `chat`, `calls`, `contacts`, `settings`,
`appearance`; для чата `--es type group`, обои — `--es wallpaper AUTUMN_AUTO`):

```bash
adb shell am start -n app.maxly.android.debug/app.maxly.demo.DemoActivity --es screen chat --es type group
```

## Ядро

Ревизия ядра закреплена в `core.lock` (та же схема, что `orbitle-ios/core.lock`).
`scripts/fetch-core.sh` клонирует эту ревизию в `.build/max-kmp-core`, собирает Android-AAR
модулей `core` и `shared` и кладёт их в `vendor/` (в git не попадает). Приложение
подключает их файлами, поэтому версии Gradle, AGP и Kotlin у приложения и ядра независимы.
Транзитивные зависимости ядра (корутины, kotlinx-serialization, OkHttp) объявлены в
`app/build.gradle.kts`.

Обновить ядро: поменять `revision=` в `core.lock` и снова запустить скрипт. Для работы с
локальной копией: `MAX_KMP_CORE_DIR=~/src/maxly-core bash scripts/fetch-core.sh`.

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
- **App activity** is reported with `client.setInteractive`: active while the app is in the
  foreground and the screen is unlocked, or while a call is in progress, also in the background
  (`AppActivity.android`); the core's 29 s `PING` carries that flag.
- **Read marks** (rule agreed with iOS, constants in `ReadMarkRules`): a message counts as seen
  only when at least 30 % of its height is inside the feed viewport; the top bar, the input field
  and the on-screen keyboard are outside it, and the feed's content padding under overlays does
  not count either (`ReadVisibility`). Only the newest seen message is marked: the mark is sent
  200 ms after the candidate last changed, a newer candidate replaces a pending one, and a mark
  older than the one already sent never goes out. Leaving the screen cancels a pending mark.
- **Unread divider:** it follows the account's own read mark, and the local mark
  (`MaxState.localReads`, kept by the core while read receipts are hidden) wins when it is newer
  than the server mark, so the divider stays put when the server never got ours.

## Сборка

Нужны JDK 17 и Android SDK (платформы 37 и 35, build-tools 37).

```bash
cd orbitle-android
export ANDROID_HOME=~/android-sdk
bash scripts/fetch-core.sh
./gradlew testDebugUnitTest      # JVM-тесты
./gradlew assembleRelease        # app/build/outputs/apk/release/app-release.apk
./gradlew installDebug           # отладочная сборка на подключённый телефон (app.maxly.android.debug)
```

Инструменты: Gradle 9.6, AGP 9.4 (встроенный Kotlin), Kotlin 2.4.20, Compose BOM 2026.09,
Material 3, Coil 3, minSdk 26, targetSdk 37. Релизная сборка ужимается R8; классы ядра
(`com.maxly.**`) не трогаются.

## CI

Workflow «Android» (`.github/workflows/android.yml`) запускается на изменения в
`orbitle-android/**` и в самом workflow: собирает ядро по `core.lock` (с кэшем), гоняет
JVM-тесты, собирает подписанный release-APK, проверяет подпись и на push в `main` заменяет
пререлиз `android-latest` файлом `Maxly.apk` и его копией `Orbitle.apk` на переходный период
(`scripts/publish-latest.sh`). Код версии — номер прогона, поэтому каждая сборка новее предыдущей.

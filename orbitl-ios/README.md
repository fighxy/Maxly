# orbitl-ios

iOS-клиент Orbitl на SwiftUI. Слои описаны в [`docs/architecture.md`](../docs/architecture.md). Komet — карта функций клиента Max ([`docs/komet-reference.md`](../docs/komet-reference.md)), не образец структуры.

## Слои

- `Sources/OrbitlDomain` — модели, протоколы репозиториев, ошибки, разбор ссылок `orbitl://`. Чистый Swift.
- `Sources/OrbitlData` — SwiftData, URLSession, очередь исходящих, синхронизация и сессия. Ядро сюда входит только как протокол `MaxCore`.
- `Sources/OrbitlUI` — цвета, отступы, аватар, строка чата, пузырь сообщения.
- `OrbitlApp` — точка входа, контейнер, навигация и экраны. Это таргет Xcode. `import MaxIos` живёт только в `OrbitlApp/Core/MaxIosCore.swift`.

Профиль устройства остаётся внутри ядра: Android, Pixel 8. Приложение не подставляет данные iPhone.

## Что есть в этом прототипе

Вход по SMS, пароль 2FA, регистрация, восстановление сессии из токена ядра (Keychain `com.max.kmp.default`). Пока сокет поднимается, показывается локальный кэш. Отклонённый токен открывает вход и не стирает базу. Явный выход и вход другим пользователем стирают базу и дисковый кэш медиа.

Список чатов, история страницами по 50, отправка текста через исходящую очередь, пуши ядра (сообщение, правка, удаление, чат, прочтение). Открытый чат отмечается прочитанным. Медиа качаются через URLSession в каталог с лимитом 200 МиБ.

Звонки, истории, стикеры, отправка «печатает», поиск, пуши APNs и QR-вход нового устройства в этот прототип не входят.

## Сборка

Ревизия ядра записана в `core.lock`. На macOS с JDK 17 и Xcode:

```bash
bash scripts/fetch-core.sh
```

Скрипт кладёт статический `Vendor/MaxIos.xcframework` (каталог в `.gitignore`) и не линкует `MaxShared` отдельно: он уже внутри `MaxIos`. Дальше открывается `Orbitl.xcodeproj`, схема `Orbitl`.

Тесты библиотек ядро не требуют:

```bash
swift test --package-path orbitl-ios
```

Они собираются и для macOS 14, чтобы прогон шёл на CI. Само приложение остаётся iOS 17.

На Windows `scripts/fetch-core.ps1` только забирает исходники ядра на ту же ревизию. XCFramework там не собирается.

## CI

Workflow `.github/workflows/ios.yml` на `macos-14` выбирает Xcode 16.2 (образ по умолчанию отдаёт Xcode 15.4 и Swift 5.10) и гоняет `swift test` и сборку приложения. `swift test` вшивает `Tests/OrbitlDataTests/Info.plist` в тестовый бинарник: SwiftData требует `CFBundleName`. Сборка приложения клонирует приватный `fighxy/max-kmp-core`, поэтому в секретах репозитория Orbitl нужен `MAX_KMP_CORE_TOKEN`: PAT с правом чтения `fighxy/max-kmp-core`. Без секрета сборка приложения пропускается с предупреждением, а тесты библиотек идут как обычно. `GITHUB_TOKEN` самого Orbitl к ядру доступа не имеет.

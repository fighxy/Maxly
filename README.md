# Orbitle

Orbitle — клиент мессенджера поверх общего ядра [max-kmp-core](https://github.com/fighxy/max-kmp-core) на Kotlin Multiplatform. Протокол, сеть, хранение сессии и бизнес-логика живут в ядре. Orbitle отвечает только за нативный интерфейс на каждой платформе.

## Платформы

| Каталог | Платформа | UI | Подключение ядра |
|---|---|---|---|
| `orbitle-ios/` | iOS | SwiftUI | статический XCFramework, ревизия в `orbitle-ios/core.lock` |
| `orbitle-android/` | Android | нативный Kotlin | Gradle-зависимость |
| `orbitle-desktop/` | Desktop (JVM) | Compose Multiplatform | напрямую, JVM-артефакт ядра |

iOS-клиент — первый прототип: вход по SMS, пароль и регистрация, список чатов, история, оптимистичная отправка текста, входящие события и каркас кэша медиа. Токен сессии хранит ядро. Каталоги `orbitle-android/` и `orbitle-desktop/` зарезервированы под свои клиенты, общее между платформами только ядро.

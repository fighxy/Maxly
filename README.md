# Orbitl

Orbitl — клиент мессенджера поверх общего ядра [max-kmp-core](https://github.com/fighxy/max-kmp-core) на Kotlin Multiplatform. Протокол, сеть, хранение сессии и бизнес-логика живут в ядре. Orbitl отвечает только за нативный интерфейс на каждой платформе.

## Платформы

| Каталог | Платформа | UI | Подключение ядра |
|---|---|---|---|
| `orbitl-ios/` | iOS | SwiftUI | статический XCFramework, ревизия в `orbitl-ios/core.lock` |
| `orbitl-android/` | Android | нативный Kotlin | Gradle-зависимость |
| `orbitl-desktop/` | Desktop (JVM) | Compose Multiplatform | напрямую, JVM-артефакт ядра |

iOS-клиент — первый прототип: вход по SMS, пароль и регистрация, список чатов, история, оптимистичная отправка текста, входящие события и каркас кэша медиа. Токен сессии хранит ядро. Каталоги `orbitl-android/` и `orbitl-desktop/` зарезервированы под свои клиенты, общее между платформами только ядро.

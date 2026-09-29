# Orbit

Orbit — клиент мессенджера поверх общего ядра [max-kmp-core](https://github.com/fighxy/max-kmp-core) на Kotlin Multiplatform. Протокол, сеть, хранение сессии и бизнес-логика живут в ядре. Orbit отвечает только за нативный интерфейс на каждой платформе.

## Платформы

| Каталог | Платформа | UI | Подключение ядра |
|---|---|---|---|
| `orbit-ios/` | iOS | SwiftUI | зависимость через SPM или CocoaPods (XCFramework) |
| `orbit-android/` | Android | нативный Kotlin | Gradle-зависимость |
| `orbit-desktop/` | Desktop (JVM) | Compose Multiplatform | напрямую, JVM-артефакт ядра |

Каталоги пока пустые. Каждое приложение живёт в своём каталоге и собирается независимо, общее между ними только ядро.

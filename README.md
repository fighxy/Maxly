# Orbitl

Orbitl — клиент мессенджера поверх общего ядра [max-kmp-core](https://github.com/fighxy/max-kmp-core) на Kotlin Multiplatform. Протокол, сеть, хранение сессии и бизнес-логика живут в ядре. Orbitl отвечает только за нативный интерфейс на каждой платформе.

## Платформы

| Каталог | Платформа | UI | Подключение ядра |
|---|---|---|---|
| `orbitl-ios/` | iOS | SwiftUI | зависимость через SPM или CocoaPods (XCFramework) |
| `orbitl-android/` | Android | нативный Kotlin | Gradle-зависимость |
| `orbitl-desktop/` | Desktop (JVM) | Compose Multiplatform | напрямую, JVM-артефакт ядра |

Каталоги пока пустые. Каждое приложение живёт в своём каталоге и собирается независимо, общее между ними только ядро.

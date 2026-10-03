# Orbitle

Orbitle — клиент мессенджера поверх общего ядра [max-kmp-core](https://github.com/fighxy/max-kmp-core) на Kotlin Multiplatform. Протокол, сеть, хранение сессии и бизнес-логика живут в ядре. Orbitle отвечает только за нативный интерфейс на каждой платформе.

## Платформы

| Каталог | Платформа | UI | Подключение ядра |
|---|---|---|---|
| `orbitle-ios/` | iOS | SwiftUI | статический XCFramework, ревизия в `orbitle-ios/core.lock` |
| `orbitle-android/` | Android | нативный Kotlin | Gradle-зависимость |
| `orbitle-desktop/` | Desktop (JVM) | Compose Multiplatform | исходники JVM ядра, ревизия в `orbitle-desktop/core.lock` |

Три клиента повторяют один и тот же функционал. Общее между ними только ядро: токен сессии хранит оно. У десктопа свой каталог `~/.orbitle` и своё пространство сессии `orbitle-desktop`, оно не делит вход с Android.

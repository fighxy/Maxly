# orbitl-ios

iOS-клиент Orbitl на SwiftUI, архитектура описана в [`docs/architecture.md`](../docs/architecture.md).

- `Sources/OrbitlDomain` содержит модели, протоколы репозиториев и ошибки. Это чистый Swift без зависимостей.
- `Sources/OrbitlData` отвечает за SwiftData, URLSession, синхронизацию, сессию и мост к ядру max-kmp-core.
- `Sources/OrbitlUI` это дизайн-система и общие компоненты.
- `OrbitlApp` содержит точку входа, DI-контейнер, навигацию и экраны. Это Xcode-таргет, его экраны импортируют только Domain и UI.

Сейчас всё это заготовки с TODO, реализации пока нет.

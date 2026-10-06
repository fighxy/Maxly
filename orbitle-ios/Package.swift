// swift-tools-version: 6.0
// Локальные пакеты iOS-клиента Orbitle. Приложение (OrbitleApp) собирается
// отдельным Xcode-таргетом и подключает эти библиотеки.
import PackageDescription

let package = Package(
    name: "Orbitle",
    // macOS 14 нужен, чтобы `swift test` собирал SwiftData на CI. Приложение остаётся iOS 17.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OrbitleDomain", targets: ["OrbitleDomain"]),
        .library(name: "OrbitleData", targets: ["OrbitleData"]),
        .library(name: "OrbitleUI", targets: ["OrbitleUI"]),
        .library(name: "OrbitlePresentation", targets: ["OrbitlePresentation"]),
        .library(name: "OrbitleCallMedia", targets: ["OrbitleCallMedia"]),
    ],
    // Lottie (airbnb, бинарная сборка): анимированные стикеры и эмодзи Max (docs/stickers.md).
    // WebRTC (сборка Google WebRTC M154 от stasel, BSD): звук и видео звонков (docs/calls.md).
    dependencies: [
        .package(url: "https://github.com/airbnb/lottie-spm.git", from: "4.5.0"),
        .package(url: "https://github.com/stasel/WebRTC.git", exact: "154.0.0"),
    ],
    targets: [
        .target(name: "OrbitleDomain"),
        // Ядро не линкуется здесь: XCFramework собирает скрипт из core.lock,
        // а вызывает его только таргет приложения (OrbitleApp/Core).
        .target(
            name: "OrbitleData",
            dependencies: ["OrbitleDomain"],
            exclude: ["Storage/README.md"]
        ),
        // Компоненты рисуют готовые строки из ViewModel (например, `ChatListItem`).
        .target(
            name: "OrbitleUI",
            dependencies: ["OrbitleDomain", "OrbitlePresentation", .product(name: "Lottie", package: "lottie-spm")]
        ),
        // ViewModel экранов: чистый Swift поверх протоколов домена, без SwiftUI и ядра.
        // Так логика экранов проходит `swift test` без Xcode-таргета приложения.
        .target(name: "OrbitlePresentation", dependencies: ["OrbitleDomain"]),
        // WebRTC за протоколами `CallMedia`/`CallPeer` из OrbitleData: логика звонка проходит
        // `swift test` с фейковым медиа, а это — настоящие соединение, камера и экран.
        .target(
            name: "OrbitleCallMedia",
            dependencies: ["OrbitleDomain", "OrbitleData", .product(name: "WebRTC", package: "WebRTC")]
        ),
        .testTarget(name: "OrbitleDomainTests", dependencies: ["OrbitleDomain"]),
        .testTarget(
            name: "OrbitleDataTests",
            dependencies: ["OrbitleData", "OrbitlePresentation"],
            exclude: ["Info.plist"]
        ),
        .testTarget(name: "OrbitleUITests", dependencies: ["OrbitleUI"]),
        .testTarget(name: "OrbitlePresentationTests", dependencies: ["OrbitlePresentation"]),
    ]
)

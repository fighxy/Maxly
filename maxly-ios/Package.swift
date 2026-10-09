// swift-tools-version: 6.0
// Локальные пакеты iOS-клиента Maxly. Приложение (MaxlyApp) собирается
// отдельным Xcode-таргетом и подключает эти библиотеки.
import PackageDescription

let package = Package(
    name: "Maxly",
    // macOS 14 нужен, чтобы `swift test` собирал SwiftData на CI. Приложение остаётся iOS 17.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MaxlyDomain", targets: ["MaxlyDomain"]),
        .library(name: "MaxlyData", targets: ["MaxlyData"]),
        .library(name: "MaxlyUI", targets: ["MaxlyUI"]),
        .library(name: "MaxlyPresentation", targets: ["MaxlyPresentation"]),
        .library(name: "MaxlyCallMedia", targets: ["MaxlyCallMedia"]),
    ],
    // Lottie (airbnb, бинарная сборка): анимированные стикеры и эмодзи Max (docs/stickers.md).
    // WebRTC (сборка Google WebRTC M154 от stasel, BSD): звук и видео звонков (docs/calls.md).
    dependencies: [
        .package(url: "https://github.com/airbnb/lottie-spm.git", from: "4.5.0"),
        .package(url: "https://github.com/stasel/WebRTC.git", exact: "154.0.0"),
    ],
    targets: [
        .target(name: "MaxlyDomain"),
        // Ядро не линкуется здесь: XCFramework собирает скрипт из core.lock,
        // а вызывает его только таргет приложения (MaxlyApp/Core).
        .target(
            name: "MaxlyData",
            dependencies: ["MaxlyDomain"],
            exclude: ["Storage/README.md"]
        ),
        // Компоненты рисуют готовые строки из ViewModel (например, `ChatListItem`).
        .target(
            name: "MaxlyUI",
            dependencies: ["MaxlyDomain", "MaxlyPresentation", .product(name: "Lottie", package: "lottie-spm")]
        ),
        // ViewModel экранов: чистый Swift поверх протоколов домена, без SwiftUI и ядра.
        // Так логика экранов проходит `swift test` без Xcode-таргета приложения.
        .target(name: "MaxlyPresentation", dependencies: ["MaxlyDomain"]),
        // WebRTC за протоколами `CallMedia`/`CallPeer` из MaxlyData: логика звонка проходит
        // `swift test` с фейковым медиа, а это — настоящие соединение, камера и экран.
        .target(
            name: "MaxlyCallMedia",
            dependencies: ["MaxlyDomain", "MaxlyData", .product(name: "WebRTC", package: "WebRTC")]
        ),
        .testTarget(name: "MaxlyDomainTests", dependencies: ["MaxlyDomain"]),
        .testTarget(
            name: "MaxlyDataTests",
            dependencies: ["MaxlyData", "MaxlyPresentation"],
            exclude: ["Info.plist"]
        ),
        .testTarget(name: "MaxlyUITests", dependencies: ["MaxlyUI"]),
        .testTarget(name: "MaxlyPresentationTests", dependencies: ["MaxlyPresentation"]),
    ]
)

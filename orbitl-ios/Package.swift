// swift-tools-version: 6.0
// Локальные пакеты iOS-клиента Orbitl. Приложение (OrbitlApp) собирается
// отдельным Xcode-таргетом и подключает эти библиотеки.
import PackageDescription

let package = Package(
    name: "Orbitl",
    // macOS 14 нужен, чтобы `swift test` собирал SwiftData на CI. Приложение остаётся iOS 17.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OrbitlDomain", targets: ["OrbitlDomain"]),
        .library(name: "OrbitlData", targets: ["OrbitlData"]),
        .library(name: "OrbitlUI", targets: ["OrbitlUI"]),
        .library(name: "OrbitlPresentation", targets: ["OrbitlPresentation"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "OrbitlDomain"),
        // Ядро не линкуется здесь: XCFramework собирает скрипт из core.lock,
        // а вызывает его только таргет приложения (OrbitlApp/Core).
        .target(
            name: "OrbitlData",
            dependencies: ["OrbitlDomain"],
            exclude: ["Storage/README.md"]
        ),
        // Компоненты рисуют готовые строки из ViewModel (например, `ChatListItem`).
        .target(name: "OrbitlUI", dependencies: ["OrbitlDomain", "OrbitlPresentation"]),
        // ViewModel экранов: чистый Swift поверх протоколов домена, без SwiftUI и ядра.
        // Так логика экранов проходит `swift test` без Xcode-таргета приложения.
        .target(name: "OrbitlPresentation", dependencies: ["OrbitlDomain"]),
        .testTarget(name: "OrbitlDomainTests", dependencies: ["OrbitlDomain"]),
        .testTarget(
            name: "OrbitlDataTests",
            dependencies: ["OrbitlData"],
            exclude: ["Info.plist"]
        ),
        .testTarget(name: "OrbitlUITests", dependencies: ["OrbitlUI"]),
        .testTarget(name: "OrbitlPresentationTests", dependencies: ["OrbitlPresentation"]),
    ]
)

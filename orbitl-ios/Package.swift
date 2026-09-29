// swift-tools-version: 6.0
// Локальные пакеты iOS-клиента Orbitl. Приложение (OrbitlApp) собирается
// отдельным Xcode-таргетом и подключает эти библиотеки.
import Foundation
import PackageDescription

// SwiftData падает без CFBundleName. `swift test` собирает голый бинарник,
// поэтому CI задаёт ORBITL_SWIFTDATA_PLIST=1 и вшивает plist. Без переменной
// флагов нет: Xcode не любит unsafeFlags у пакета приложения.
let embedSwiftDataPlist = ProcessInfo.processInfo.environment["ORBITL_SWIFTDATA_PLIST"] == "1"
let testInfoPlist = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Tests/OrbitlDataTests/Info.plist")
    .path
let dataTestLinker: [LinkerSetting] = embedSwiftDataPlist
    ? [.unsafeFlags([
        "-Xlinker", "-sectcreate",
        "-Xlinker", "__TEXT",
        "-Xlinker", "__info_plist",
        "-Xlinker", testInfoPlist,
    ])]
    : []

let package = Package(
    name: "Orbitl",
    // macOS 14 нужен, чтобы `swift test` собирал SwiftData на CI. Приложение остаётся iOS 17.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OrbitlDomain", targets: ["OrbitlDomain"]),
        .library(name: "OrbitlData", targets: ["OrbitlData"]),
        .library(name: "OrbitlUI", targets: ["OrbitlUI"]),
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
        .target(name: "OrbitlUI", dependencies: ["OrbitlDomain"]),
        .testTarget(name: "OrbitlDomainTests", dependencies: ["OrbitlDomain"]),
        .testTarget(
            name: "OrbitlDataTests",
            dependencies: ["OrbitlData"],
            exclude: ["Info.plist"],
            linkerSettings: dataTestLinker
        ),
        .testTarget(name: "OrbitlUITests", dependencies: ["OrbitlUI"]),
    ]
)

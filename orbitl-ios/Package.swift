// swift-tools-version: 5.10
// Локальные пакеты iOS-клиента Orbitl. Приложение (OrbitlApp) собирается
// отдельным Xcode-таргетом и подключает эти библиотеки.
import PackageDescription

let package = Package(
    name: "Orbitl",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "OrbitlDomain", targets: ["OrbitlDomain"]),
        .library(name: "OrbitlData", targets: ["OrbitlData"]),
        .library(name: "OrbitlUI", targets: ["OrbitlUI"]),
    ],
    dependencies: [
        // TODO: заглушка. Заменить на реальный адрес SPM-пакета с XCFramework
        // ядра max-kmp-core и зафиксировать версию (см. «Версионирование ядра»).
        .package(url: "https://github.com/fighxy/max-kmp-core-spm.git", exact: "0.1.0"),
    ],
    targets: [
        .target(name: "OrbitlDomain"),
        .target(
            name: "OrbitlData",
            dependencies: [
                "OrbitlDomain",
                .product(name: "MaxCore", package: "max-kmp-core-spm"),
            ]
        ),
        .target(name: "OrbitlUI", dependencies: ["OrbitlDomain"]),
        .testTarget(name: "OrbitlDomainTests", dependencies: ["OrbitlDomain"]),
        .testTarget(name: "OrbitlDataTests", dependencies: ["OrbitlData"]),
        .testTarget(name: "OrbitlUITests", dependencies: ["OrbitlUI"]),
    ]
)

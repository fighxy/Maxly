import org.jetbrains.compose.desktop.application.dsl.TargetFormat
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    kotlin("multiplatform") version "2.1.10"
    kotlin("plugin.compose") version "2.1.10"
    kotlin("plugin.serialization") version "2.1.10"
    id("org.jetbrains.compose") version "1.7.3"
}

// Исходники ядра: по умолчанию .build/max-kmp-core в корне репозитория (ревизия из core.lock),
// MAX_KMP_CORE_DIR — своя локальная копия.
val coreDir = System.getenv("MAX_KMP_CORE_DIR")?.takeIf { it.isNotBlank() }?.let(::file)
    ?: rootProject.file("../.build/max-kmp-core")
if (!coreDir.resolve("core/src/commonMain/kotlin").isDirectory) {
    throw GradleException(
        "Нет ядра в $coreDir. Запустите bash orbitle-desktop/scripts/fetch-core.sh " +
            "(Windows: scripts/fetch-core.ps1) из корня репозитория",
    )
}

/**
 * Нативная часть WebRTC (webrtc-java) под ОС и процессор сборки: установщик каждой ОС
 * собирается на ней самой, поэтому в него попадает только своя библиотека.
 */
val webrtcNatives: String = run {
    val os = System.getProperty("os.name").lowercase()
    val arch = System.getProperty("os.arch").lowercase()
    val cpu = if ("aarch64" in arch || "arm64" in arch) "aarch64" else "x86_64"
    when {
        "win" in os -> "windows-$cpu"
        "mac" in os -> "macos-$cpu"
        else -> "linux-$cpu"
    }
}

/** Ревизия ядра из core.lock: короткий хеш для экрана «О приложении». */
val coreRevision: String = file("core.lock").readLines()
    .firstOrNull { it.startsWith("revision=") }?.substringAfter('=')?.trim()?.take(7)
    ?: throw GradleException("В orbitle-desktop/core.lock нет строки revision=")

// BuildConfig собирается из core.lock и переменных CI при каждой сборке, поэтому не устаревает.
val generateBuildConfig = tasks.register("generateBuildConfig") {
    val outputDir = layout.buildDirectory.dir("generated/buildConfig")
    val versionName = "0.1.0"
    val buildSha = System.getenv("ORBITLE_BUILD_SHA")?.takeIf { it.isNotBlank() } ?: "dev"
    val revision = coreRevision
    inputs.property("versionName", versionName)
    inputs.property("buildSha", buildSha)
    inputs.property("coreRevision", revision)
    outputs.dir(outputDir)
    doLast {
        val target = outputDir.get().file("app/orbitle/BuildConfig.kt").asFile
        target.parentFile.mkdirs()
        target.writeText(
            """
            |package app.orbitle
            |
            |/** Сведения сборки для экрана «О приложении». Файл пишет задача generateBuildConfig из core.lock. */
            |object BuildConfig {
            |    const val VERSION_NAME = "$versionName"
            |    const val BUILD_SHA = "$buildSha"
            |    const val CORE_REVISION = "$revision"
            |}
            |""".trimMargin(),
        )
    }
}

kotlin {
    jvm {
        compilations.configureEach {
            compileTaskProvider.configure {
                compilerOptions.jvmTarget.set(JvmTarget.JVM_17)
            }
        }
    }
    sourceSets {
        val commonMain by getting {
            kotlin.setSrcDirs(
                listOf(
                    coreDir.resolve("core/src/commonMain/kotlin"),
                    coreDir.resolve("shared/src/commonMain/kotlin"),
                ),
            )
            dependencies {
                implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.1")
                implementation("org.jetbrains.kotlinx:kotlinx-serialization-core:1.8.0")
                implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.0")
            }
        }
        val jvmMain by getting {
            kotlin.setSrcDirs(
                listOf(
                    coreDir.resolve("core/src/jvmMain/kotlin"),
                    coreDir.resolve("core/src/jvmAndroidShared/kotlin"),
                    coreDir.resolve("shared/src/jvmMain/kotlin"),
                    // Общий с Android код (domain, data, presentation). Его тесты — в jvmTest ниже и в сборке orbitle-android.
                    layout.projectDirectory.dir("../orbitle-shared/src/main/kotlin"),
                    layout.projectDirectory.dir("../orbitle-compose/src/main/kotlin"),
                    layout.projectDirectory.dir("src/main/kotlin"),
                ),
            )
            kotlin.srcDir(generateBuildConfig)
            resources.srcDir("src/main/resources")
            dependencies {
                implementation("com.squareup.okhttp3:okhttp:4.12.0")
                implementation(compose.desktop.currentOs)
                implementation(compose.material3)
                implementation(compose.materialIconsExtended)
                implementation("org.jetbrains.kotlinx:kotlinx-coroutines-swing:1.10.1")
                implementation("org.jetbrains.androidx.lifecycle:lifecycle-viewmodel-compose:2.8.4")
                implementation("org.jetbrains.androidx.lifecycle:lifecycle-runtime-compose:2.8.4")
                implementation("io.coil-kt.coil3:coil-compose:3.0.4")
                // Lottie 1.1.x собирается с Compose 1.6 и подходит к 1.7. Ветка 2.x требует Compose 1.10.
                implementation("io.github.alexzhirkevich:compottie:1.1.2")
                implementation("io.coil-kt.coil3:coil-network-okhttp:3.0.4")
                implementation("com.google.zxing:core:3.5.3")
                // Встроенный Chromium для мини-приложений. Наборы CEF качаются при первом открытии.
                implementation("dev.datlag:kcef:2024.04.20.4")
                // Звонки: WebRTC (Apache 2.0) с нативной библиотекой своей ОС.
                implementation("dev.onvoid.webrtc:webrtc-java:0.18.0")
                implementation("dev.onvoid.webrtc:webrtc-java:0.18.0:$webrtcNatives")
            }
        }
        val jvmTest by getting {
            kotlin.setSrcDirs(
                listOf(
                    // Тесты общего кода: здесь они проверяют его на версиях библиотек десктопа.
                    layout.projectDirectory.dir("../orbitle-shared/src/test/kotlin"),
                    layout.projectDirectory.dir("src/test/kotlin"),
                ),
            )
            dependencies {
                implementation(kotlin("test-junit"))
                implementation("junit:junit:4.13.2")
                implementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.1")
                implementation("org.jetbrains.kotlinx:kotlinx-coroutines-swing:1.10.1")
            }
        }
    }
}

compose.desktop {
    application {
        mainClass = "app.orbitle.MainKt"
        // KCEF читает внутренние классы AWT. Без этих флагов окно страницы не создаётся.
        jvmArgs(
            "--add-opens=java.desktop/sun.awt=ALL-UNNAMED",
            "--add-opens=java.desktop/java.awt.peer=ALL-UNNAMED",
            "--add-opens=java.desktop/sun.lwawt=ALL-UNNAMED",
            "--add-opens=java.desktop/sun.lwawt.macosx=ALL-UNNAMED",
        )
        nativeDistributions {
            targetFormats(TargetFormat.Msi, TargetFormat.Dmg, TargetFormat.Deb)
            packageName = "Orbitle"
            // Установщик не принимает старший номер 0: версия пакета отдельно от версии клиента.
            packageVersion = "1.0.0"
            // Код продукта MSI считается из имени и версии. Пока версия 1.0.0, Windows видит
            // тот же продукт и пишет, что приложение уже установлено. Номер растёт каждую секунду,
            // старая установка снимается по постоянному upgradeUuid.
            val windowsMsiVersion = run {
                // Секунды с 2026-01-01. Поля MSI: старший до 255, средний до 255, младший до 65535.
                val delta = (System.currentTimeMillis() / 1000 - 1_767_225_600L).coerceAtLeast(1)
                val build = delta % 65536L
                val minor = (delta / 65536L) % 256L
                val major = (1 + delta / (65536L * 256)).coerceAtMost(255)
                "$major.$minor.$build"
            }
            // Только ASCII: WiX собирает .msi в кодовой странице 1252, кириллица в описании ломает packageMsi.
            description = "Orbitle desktop client"
            vendor = "Orbitle"
            // Значки собраны из orbitle-ios AppIcon.png (1024 px): .ico 16–256, .icns, .png 512.
            windows {
                // Ярлык на рабочем столе и в меню «Пуск», установка без прав администратора
                // в профиль пользователя с выбором папки.
                shortcut = true
                menu = true
                menuGroup = "Orbitle"
                perUserInstall = true
                dirChooser = true
                // Постоянный UUID: новая версия .msi обновляет установленную, а не ставится рядом.
                upgradeUuid = "27980db0-5d2d-4976-a4b1-28b2c36ed9b4"
                msiPackageVersion = windowsMsiVersion
                iconFile.set(project.file("icons/orbitle.ico"))
            }
            macOS {
                bundleID = "app.orbitle.desktop"
                iconFile.set(project.file("icons/orbitle.icns"))
                // Без этих строк macOS не даст звонку микрофон и камеру.
                infoPlist {
                    extraKeysRawXml = """
                        <key>NSMicrophoneUsageDescription</key>
                        <string>Orbitle uses the microphone for calls.</string>
                        <key>NSCameraUsageDescription</key>
                        <string>Orbitle uses the camera for video calls.</string>
                    """.trimIndent()
                }
            }
            linux {
                shortcut = true
                menuGroup = "Network;InstantMessaging"
                iconFile.set(project.file("icons/orbitle.png"))
            }
        }
    }
}

// Общие с iOS сценарии ws2 (test-fixtures/calls/ws2), «печатает» (test-fixtures/typing) и «Кем прочитано»
// (test-fixtures/readers), а также разметка, черновики, выбор сообщений,
// участники и имена (test-fixtures/{formatting,drafts,selection,members,names}) — вход тестов общего кода: правка файла перезапускает их.
tasks.withType<Test>().configureEach {
    inputs.dir(layout.projectDirectory.dir("../test-fixtures/calls/ws2"))
        .withPropertyName("ws2Fixtures")
        .withPathSensitivity(PathSensitivity.RELATIVE)
    inputs.dir(layout.projectDirectory.dir("../test-fixtures/typing"))
        .withPropertyName("typingFixtures")
        .withPathSensitivity(PathSensitivity.RELATIVE)
    inputs.dir(layout.projectDirectory.dir("../test-fixtures/readers"))
        .withPropertyName("readersFixtures")
        .withPathSensitivity(PathSensitivity.RELATIVE)
    inputs.dir(layout.projectDirectory.dir("../test-fixtures/formatting"))
        .withPropertyName("formattingFixtures")
        .withPathSensitivity(PathSensitivity.RELATIVE)
    inputs.dir(layout.projectDirectory.dir("../test-fixtures/drafts"))
        .withPropertyName("draftsFixtures")
        .withPathSensitivity(PathSensitivity.RELATIVE)
    inputs.dir(layout.projectDirectory.dir("../test-fixtures/selection"))
        .withPropertyName("selectionFixtures")
        .withPathSensitivity(PathSensitivity.RELATIVE)
    inputs.dir(layout.projectDirectory.dir("../test-fixtures/members"))
        .withPropertyName("membersFixtures")
        .withPathSensitivity(PathSensitivity.RELATIVE)
    inputs.dir(layout.projectDirectory.dir("../test-fixtures/names"))
        .withPropertyName("namesFixtures")
        .withPathSensitivity(PathSensitivity.RELATIVE)
}

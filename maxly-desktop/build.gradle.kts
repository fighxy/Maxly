import org.jetbrains.compose.desktop.application.dsl.TargetFormat
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    kotlin("multiplatform") version "2.4.20"
    kotlin("plugin.compose") version "2.4.20"
    kotlin("plugin.serialization") version "2.4.20"
    id("org.jetbrains.compose") version "1.12.1"
}

// Исходники ядра: по умолчанию .build/max-kmp-core в корне репозитория (ревизия из core.lock),
// MAX_KMP_CORE_DIR — своя локальная копия.
val coreDir = System.getenv("MAX_KMP_CORE_DIR")?.takeIf { it.isNotBlank() }?.let(::file)
    ?: rootProject.file("../.build/max-kmp-core")
if (!coreDir.resolve("core/src/commonMain/kotlin").isDirectory) {
    throw GradleException(
        "Нет ядра в $coreDir. Запустите bash maxly-desktop/scripts/fetch-core.sh " +
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
    ?: throw GradleException("В maxly-desktop/core.lock нет строки revision=")

// BuildConfig собирается из core.lock и переменных CI при каждой сборке, поэтому не устаревает.
val generateBuildConfig = tasks.register("generateBuildConfig") {
    val outputDir = layout.buildDirectory.dir("generated/buildConfig")
    val versionName = "0.1.0"
    val buildSha = System.getenv("MAXLY_BUILD_SHA")?.takeIf { it.isNotBlank() } ?: "dev"
    val revision = coreRevision
    inputs.property("versionName", versionName)
    inputs.property("buildSha", buildSha)
    inputs.property("coreRevision", revision)
    outputs.dir(outputDir)
    doLast {
        val target = outputDir.get().file("app/maxly/BuildConfig.kt").asFile
        target.parentFile.mkdirs()
        target.writeText(
            """
            |package app.maxly
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
        getByName("commonMain") {
            kotlin.setSrcDirs(
                listOf(
                    coreDir.resolve("core/src/commonMain/kotlin"),
                    coreDir.resolve("shared/src/commonMain/kotlin"),
                ),
            )
            dependencies {
                implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.11.0")
                implementation("org.jetbrains.kotlinx:kotlinx-serialization-core:1.11.0")
                implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")
            }
        }
        getByName("jvmMain") {
            kotlin.setSrcDirs(
                listOf(
                    coreDir.resolve("core/src/jvmMain/kotlin"),
                    coreDir.resolve("core/src/jvmAndroidShared/kotlin"),
                    coreDir.resolve("shared/src/jvmMain/kotlin"),
                    // Общий с Android код (domain, data, presentation). Его тесты — в jvmTest ниже и в сборке maxly-android.
                    layout.projectDirectory.dir("../maxly-shared/src/main/kotlin"),
                    layout.projectDirectory.dir("../maxly-compose/src/main/kotlin"),
                    layout.projectDirectory.dir("src/main/kotlin"),
                ),
            )
            kotlin.srcDir(generateBuildConfig)
            resources.srcDir("src/main/resources")
            dependencies {
                implementation("com.squareup.okhttp3:okhttp:4.12.0")
                implementation(compose.desktop.currentOs)
                // Версия Material3 у плагина 1.12 больше не совпадает с compose.material3 (там осталась 1.9.0).
                implementation("org.jetbrains.compose.material3:material3:1.12.0-alpha03")
                implementation("org.jetbrains.compose.material:material-icons-extended:1.7.3")
                implementation("org.jetbrains.kotlinx:kotlinx-coroutines-swing:1.11.0")
                implementation("org.jetbrains.androidx.lifecycle:lifecycle-viewmodel-compose:2.11.0")
                implementation("org.jetbrains.androidx.lifecycle:lifecycle-runtime-compose:2.11.0")
                implementation("io.coil-kt.coil3:coil-compose:3.6.3")
                // Compottie 2.3 собран под Compose 1.12.
                implementation("io.github.alexzhirkevich:compottie:2.3.1")
                implementation("dev.chrisbanes.haze:haze:2.0.1")
                implementation("dev.chrisbanes.haze:haze-blur:2.0.1")
                implementation("dev.chrisbanes.haze:haze-blur-materials:2.0.1")
                implementation("com.mohamedrejeb.calf:calf-file-picker:0.14.0")
                implementation("io.coil-kt.coil3:coil-network-okhttp:3.6.3")
                implementation("com.google.zxing:core:3.5.3")
                // Встроенный Chromium для мини-приложений. Наборы CEF качаются при первом открытии.
                implementation("dev.datlag:kcef:2024.04.20.4")
                // Звонки: WebRTC (Apache 2.0) с нативной библиотекой своей ОС.
                implementation("dev.onvoid.webrtc:webrtc-java:0.18.0")
                implementation("dev.onvoid.webrtc:webrtc-java:0.18.0:$webrtcNatives")
            }
        }
        getByName("jvmTest") {
            kotlin.setSrcDirs(
                listOf(
                    // Тесты общего кода: здесь они проверяют его на версиях библиотек десктопа.
                    layout.projectDirectory.dir("../maxly-shared/src/test/kotlin"),
                    layout.projectDirectory.dir("src/test/kotlin"),
                ),
            )
            dependencies {
                implementation(kotlin("test-junit"))
                implementation("junit:junit:4.13.2")
                implementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.11.0")
                implementation("org.jetbrains.kotlinx:kotlinx-coroutines-swing:1.11.0")
                // Экранные тесты без окна: лист и правый клик мыши.
                @OptIn(org.jetbrains.compose.ExperimentalComposeLibrary::class)
                implementation(compose.uiTest)
            }
        }
    }
}

compose.desktop {
    application {
        mainClass = "app.maxly.MainKt"
        // KCEF читает внутренние классы AWT. Без этих флагов окно страницы не создаётся.
        jvmArgs(
            "--add-opens=java.desktop/sun.awt=ALL-UNNAMED",
            "--add-opens=java.desktop/java.awt.peer=ALL-UNNAMED",
            "--add-opens=java.desktop/sun.lwawt=ALL-UNNAMED",
            "--add-opens=java.desktop/sun.lwawt.macosx=ALL-UNNAMED",
        )
        nativeDistributions {
            targetFormats(TargetFormat.Msi, TargetFormat.Dmg, TargetFormat.Deb)
            // Модули JDK сверх набора плагина (java.base, java.desktop, java.logging, jdk.crypto.ec) —
            // по suggestRuntimeModules. Без них установленная сборка падает там, где запуск из IDE
            // работает: jdk.unsupported — sun.misc.Unsafe для библиотек, java.management — стеки
            // потоков с блокировками в отчёте о зависании окна.
            modules("java.instrument", "java.management", "java.prefs", "java.scripting", "jdk.unsupported")
            packageName = "Maxly"
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
            description = "Maxly desktop client"
            vendor = "Maxly"
            // Значки собраны из docs/brand/maxly-logo-black.png: .ico 16–256, .icns до 1024, .png 512.
            windows {
                // Ярлык на рабочем столе и в меню «Пуск», установка без прав администратора
                // в профиль пользователя с выбором папки.
                shortcut = true
                menu = true
                menuGroup = "Maxly"
                perUserInstall = true
                dirChooser = true
                // Постоянный UUID: новая версия .msi обновляет установленную, а не ставится рядом.
                upgradeUuid = "27980db0-5d2d-4976-a4b1-28b2c36ed9b4"
                msiPackageVersion = windowsMsiVersion
                iconFile.set(project.file("icons/maxly.ico"))
            }
            macOS {
                bundleID = "app.maxly.desktop"
                iconFile.set(project.file("icons/maxly.icns"))
                // Без этих строк macOS не даст звонку микрофон и камеру.
                infoPlist {
                    extraKeysRawXml = """
                        <key>NSMicrophoneUsageDescription</key>
                        <string>Maxly uses the microphone for calls.</string>
                        <key>NSCameraUsageDescription</key>
                        <string>Maxly uses the camera for video calls.</string>
                    """.trimIndent()
                }
            }
            linux {
                packageName = "maxly"
                shortcut = true
                menuGroup = "Network;InstantMessaging"
                iconFile.set(project.file("icons/maxly.png"))
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

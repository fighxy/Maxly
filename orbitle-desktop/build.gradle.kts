import org.jetbrains.compose.desktop.application.dsl.TargetFormat
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    kotlin("multiplatform") version "2.1.10"
    kotlin("plugin.compose") version "2.1.10"
    kotlin("plugin.serialization") version "2.1.10"
    id("org.jetbrains.compose") version "1.7.3"
}

val coreDir = rootProject.file("../.build/max-kmp-core")
if (!coreDir.resolve("core/src/commonMain/kotlin").isDirectory) {
    throw GradleException("Нет ядра в $coreDir. Запустите scripts/fetch-core.ps1 из корня репозитория")
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
                    layout.projectDirectory.dir("src/main/kotlin"),
                ),
            )
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
                implementation("io.coil-kt.coil3:coil-network-okhttp:3.0.4")
                implementation("com.google.zxing:core:3.5.3")
                // Встроенный Chromium для мини-приложений. Наборы CEF качаются при первом открытии.
                implementation("dev.datlag:kcef:2024.04.20.4")
            }
        }
        val jvmTest by getting {
            kotlin.setSrcDirs(listOf(layout.projectDirectory.dir("src/test/kotlin")))
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
            description = "Orbitle для компьютера"
            vendor = "Orbitle"
        }
    }
}

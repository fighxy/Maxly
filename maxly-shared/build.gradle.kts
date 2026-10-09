// Общий код Android и десктопа: domain, data, presentation и их тесты.
// В сборке maxly-android это Android-библиотека :shared; десктоп собирает те же исходники
// в своей JVM-цели (см. maxly-desktop/build.gradle.kts).
plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "app.maxly.shared"
    compileSdk {
        version = release(37) {
            minorApiLevel = 1
        }
    }

    defaultConfig {
        minSdk = 26
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

kotlin {
    jvmToolchain(17)
}

// AAR ядра подключает приложение. Библиотеке они нужны только для компиляции и тестов:
// локальный AAR нельзя упаковать в другой AAR.
val coreAars = listOf("vendor/max-core.aar", "vendor/max-shared.aar").map { rootProject.file(it) }
if (coreAars.any { !it.exists() }) {
    throw GradleException("Нет AAR ядра в maxly-android/vendor: запустите bash maxly-android/scripts/fetch-core.sh")
}

dependencies {
    compileOnly(files(coreAars))
    testImplementation(files(coreAars))

    api(libs.androidx.lifecycle.viewmodel)
    api(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.serialization.json)
    // Сокет ws2 сервера звонков.
    implementation(libs.okhttp)
    implementation(libs.zxing.core)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.okhttp)
}

// Общие с iOS сценарии ws2 (test-fixtures/calls/ws2), «печатает» (test-fixtures/typing) и «Кем прочитано»
// (test-fixtures/readers), а также разметка, черновики, выбор сообщений,
// участники и имена (test-fixtures/{formatting,drafts,selection,members,names}) — вход тестов: правка файла перезапускает их.
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

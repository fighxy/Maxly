// Общий код Android и десктопа: domain, data, presentation и их тесты.
// В сборке orbitle-android это Android-библиотека :shared; десктоп собирает те же исходники
// в своей JVM-цели (см. orbitle-desktop/build.gradle.kts).
plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "app.orbitle.shared"
    compileSdk = 37

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
    throw GradleException("Нет AAR ядра в orbitle-android/vendor: запустите bash orbitle-android/scripts/fetch-core.sh")
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

// Общие с iOS сценарии ws2 (test-fixtures/calls/ws2) и «печатает» (test-fixtures/typing) — вход тестов:
// правка файла перезапускает их.
tasks.withType<Test>().configureEach {
    inputs.dir(layout.projectDirectory.dir("../test-fixtures/calls/ws2"))
        .withPropertyName("ws2Fixtures")
        .withPathSensitivity(PathSensitivity.RELATIVE)
    inputs.dir(layout.projectDirectory.dir("../test-fixtures/typing"))
        .withPropertyName("typingFixtures")
        .withPathSensitivity(PathSensitivity.RELATIVE)
}

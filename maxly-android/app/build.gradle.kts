plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.compose.compiler)
}

// Подпись: в CI ключ берётся из секретов (переменные MAXLY_KEYSTORE_*), иначе — общий ключ разработки
// из репозитория, чтобы сборки ставились поверх друг друга.
val keystorePath = System.getenv("MAXLY_KEYSTORE_FILE")?.takeIf { it.isNotBlank() }
val versionCodeOverride = System.getenv("MAXLY_VERSION_CODE")?.toIntOrNull()

android {
    namespace = "app.maxly"
    compileSdk {
        version = release(37) {
            minorApiLevel = 1
        }
    }

    defaultConfig {
        applicationId = "app.maxly.android"
        minSdk = 26
        targetSdk = 37
        versionCode = versionCodeOverride ?: 1
        versionName = "0.1.0"
        buildConfigField("String", "CORE_REVISION", "\"${coreRevision()}\"")
        buildConfigField("String", "BUILD_SHA", "\"${System.getenv("MAXLY_BUILD_SHA") ?: "dev"}\"")
    }

    signingConfigs {
        create("maxly") {
            if (keystorePath != null) {
                storeFile = file(keystorePath)
                storePassword = System.getenv("MAXLY_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("MAXLY_KEY_ALIAS")
                keyPassword = System.getenv("MAXLY_KEY_PASSWORD")
            } else {
                storeFile = rootProject.file("signing/maxly-dev.keystore")
                storePassword = "android"
                keyAlias = "maxly"
                keyPassword = "android"
            }
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("maxly")
            applicationIdSuffix = ".debug"
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig = signingConfigs.getByName("maxly")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    sourceSets["main"].kotlin.srcDir("../../maxly-compose/src/main/kotlin")

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }

    packaging {
        resources.excludes += setOf("/META-INF/{AL2.0,LGPL2.1}", "/META-INF/versions/9/OSGI-INF/MANIFEST.MF")
    }
}

kotlin {
    jvmToolchain(17)
}

fun coreRevision(): String {
    val lock = rootProject.file("core.lock")
    if (!lock.exists()) return "unknown"
    return lock.readLines().firstOrNull { it.startsWith("revision=") }?.substringAfter('=')?.take(7) ?: "unknown"
}

val coreAars = listOf("../vendor/max-core.aar", "../vendor/max-shared.aar")
if (coreAars.any { !file(it).exists() }) {
    throw GradleException("Нет AAR ядра в maxly-android/vendor: запустите bash maxly-android/scripts/fetch-core.sh")
}

dependencies {
    implementation(project(":shared"))
    // Ядро maxly-core (Android-цель), собранное scripts/fetch-core-android.sh по core.lock.
    implementation(files(coreAars))
    // Зависимости ядра: AAR-файлы не несут POM, поэтому их объявляет приложение.
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.okhttp)

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.splashscreen)
    implementation(libs.androidx.webkit)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.process)
    implementation(libs.androidx.navigation.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons)
    implementation(libs.compose.material3.adaptive.navigation.suite)
    implementation(libs.compose.adaptive)
    implementation(libs.compose.adaptive.layout)
    implementation(libs.compose.adaptive.navigation)
    implementation(libs.coil.compose)
    implementation(libs.compottie)
    implementation(libs.coil.network.okhttp)
    implementation(libs.media3.transformer)
    implementation(libs.media3.exoplayer)
    implementation(libs.media3.ui)
    implementation(libs.media3.ui.compose)
    // QR-коды профиля и приглашения.
    implementation(libs.zxing.core)
    // Сканер QR-кода входа на другом устройстве.
    implementation(libs.camera.camera2)
    implementation(libs.camera.lifecycle)
    implementation(libs.camera.view)
    // Кружки: запись видео камерой.
    implementation(libs.camera.video)
    // Звонки: WebRTC (BSD), сборка webrtc-sdk с аппаратными кодеками.
    implementation(libs.webrtc.android)
    debugImplementation(libs.compose.ui.tooling)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}

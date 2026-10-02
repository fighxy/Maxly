plugins {
    alias(libs.plugins.android.application) apply false
    // Встроенный Kotlin AGP 9 берёт эту версию Kotlin Gradle Plugin.
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.compose.compiler) apply false
}

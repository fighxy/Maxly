pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        // JOGL для встроенного Chromium (KCEF): этих артефактов нет в Maven Central.
        maven("https://jogamp.org/deployment/maven")
    }
}

rootProject.name = "orbitle-desktop"

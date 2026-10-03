pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "orbitle-android"
include(":app")
// Общий для Android и десктопа код: модели, слой данных над ядром и ViewModel.
include(":shared")
project(":shared").projectDir = file("../orbitle-shared")

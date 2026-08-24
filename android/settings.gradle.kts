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
        // Parse-SDK-Android is published to JitPack, not Maven Central.
        maven("https://jitpack.io")
    }
}

rootProject.name = "MMCoach"
include(":app")

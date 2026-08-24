plugins {
    alias(libs.plugins.android.application)
    // AGP 9's built-in Kotlin support (android.builtInKotlin, default true)
    // replaces the standalone org.jetbrains.kotlin.android plugin -- applying
    // both registers the "kotlin" extension twice. The Compose compiler
    // plugin is still separate and still required.
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "dev.benderapps.mmcoach"
    compileSdk = 36

    defaultConfig {
        applicationId = "dev.benderapps.mmcoach"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.navigation.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons.extended)
    implementation(libs.parse.sdk.android)
    debugImplementation(libs.androidx.ui.tooling)
    implementation(libs.androidx.ui.tooling.preview)
}

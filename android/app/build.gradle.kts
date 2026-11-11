plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.bnwise.cleanleaf"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.bnwise.cleanleaf"
        minSdk = 24
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // AGP rejects ndk.abiFilters alongside the ABI splits that --split-per-abi adds.
        if (!project.hasProperty("split-per-abi")) {
            ndk { abiFilters += listOf("armeabi-v7a", "arm64-v8a") }
        }
    }

    // T-003: ORG_GRADLE_PROJECT_clLegacyJni=true stores native libs compressed.
    packaging {
        jniLibs { useLegacyPackaging = project.findProperty("clLegacyJni") == "true" }
    }

    buildTypes {
        release {
            // Debug signing until the release key exists (decisions.md D-05).
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // T-003 candidate C.
    implementation("org.opencv:opencv:4.13.0")
}

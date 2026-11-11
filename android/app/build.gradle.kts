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
        // Probe/bench builds install beside the real app instead of replacing it.
        if (project.hasProperty("probe")) applicationIdSuffix = ".probe"
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

    // decisions.md D-33: native libs stored compressed for the sideloaded APK.
    packaging {
        jniLibs { useLegacyPackaging = true }
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
    // decisions.md D-12.
    val camerax = "1.6.2"
    implementation("androidx.camera:camera-core:$camerax")
    implementation("androidx.camera:camera-camera2:$camerax")
    implementation("androidx.camera:camera-lifecycle:$camerax")
    implementation("androidx.concurrent:concurrent-futures-ktx:1.1.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    // decisions.md D-02a: optional Google scan engine, package mlkit/.
    implementation("com.google.android.gms:play-services-mlkit-document-scanner:16.0.0")
    // decisions.md D-13a: Tesseract OCR, package ocr/ (keep rules in proguard-rules.pro).
    implementation("cz.adaptech.tesseract4android:tesseract4android:4.9.0")
}

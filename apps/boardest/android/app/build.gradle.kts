plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "jiwho.boardest.board"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    val isCloud = (project.hasProperty("isCloud") && project.property("isCloud") == "true") ||
                  (project.hasProperty("dart-defines") && (project.property("dart-defines") as String).contains("BC_CLOUD_MODE%3Dtrue"))

    defaultConfig {
        applicationId = if (isCloud) "jiwho.boardest.cloud" else "jiwho.boardest.board"
        manifestPlaceholders["appLabel"] = if (isCloud) "Boardest Cloud" else "Boardest Class"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        ndk {
            abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a", "x86_64"))
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = "boardest"
            keyPassword = "Boardest2026!"
            storeFile = file("boardest_release.keystore")
            storePassword = "Boardest2026!"
            enableV1Signing = true
            enableV2Signing = true
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

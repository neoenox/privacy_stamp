import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load release signing credentials from android/key.properties (git-ignored).
// A normal release task must have the production upload key. CI may opt in to
// a non-distributable debug-signed release smoke artifact explicitly.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
val allowDebugReleaseSigning =
    System.getenv("PRIVACY_STAMP_ALLOW_DEBUG_RELEASE_SIGNING") == "1"
val releaseTaskRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
if (hasReleaseKey) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

if (releaseTaskRequested && !hasReleaseKey && !allowDebugReleaseSigning) {
    throw GradleException(
        "Release signing key is missing. Configure android/key.properties " +
            "with the production upload key. Debug-signed release smoke builds " +
            "must explicitly set PRIVACY_STAMP_ALLOW_DEBUG_RELEASE_SIGNING=1."
    )
}

android {
    namespace = "com.privacy_stamp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Formal application ID for Google Play (com.privacy_stamp).
        applicationId = "com.privacy_stamp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = when {
                hasReleaseKey -> signingConfigs.getByName("release")
                allowDebugReleaseSigning -> signingConfigs.getByName("debug")
                else -> null
            }
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
    // The Flutter plugin exposes all script enums, but this app selects
    // TextRecognitionScript.japanese. Bundle the matching on-device model.
    implementation("com.google.mlkit:text-recognition-japanese:16.0.1")
}

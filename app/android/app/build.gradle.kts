import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Generates the Firebase resources from `google-services.json` (FCM push).
    id("com.google.gms.google-services")
    // R8 mapping upload + native crash reporting for Crashlytics.
    id("com.google.firebase.crashlytics")
}

// Release signing for the published MV2 app.
//
// `key.properties` is NOT committed (it holds the upload key's passwords); CI
// decodes `KEYSTORE_BASE64` → `android/app/upload-keystore.jks` and writes the
// properties file before running the build. Without that file the module falls
// back to the debug key so `flutter run --release` keeps working locally.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val hasReleaseKeystore = keystorePropertiesFile.exists() &&
    keystoreProperties["storeFile"] != null

android {
    // Published identity of the existing MV2 app. This must NOT change: the
    // Flutter rewrite ships as an *upgrade* of the MAUI client (same Play/App
    // Store record, same Firebase project), not as a new app.
    namespace = "tech.zb.v2ex.maui.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "tech.zb.v2ex.maui.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Only created when `key.properties` exists, so a fresh clone without
        // the upload key still configures cleanly.
        if (hasReleaseKeystore) {
            create("mv2Upload") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // The published MV2 app's upload key. An update signed with any
            // other key is rejected by Play.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("mv2Upload")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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

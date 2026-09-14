pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
    // Reads `android/app/google-services.json`, so `Firebase.initializeApp()`
    // picks up project `v2ex-maui2` with no Dart-side config.
    id("com.google.gms.google-services") version "4.5.0" apply false
    // Uploads the R8 mapping file and turns native crashes into Crashlytics
    // reports. Without it only Dart-side crashes are reported on Android.
    id("com.google.firebase.crashlytics") version "3.0.6" apply false
}

include(":app")

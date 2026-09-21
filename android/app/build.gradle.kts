import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// android/key.properties is written by release.yml from the repository secrets
// and is never committed; see README "Releasing".
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "de.vorsorgereminder.vorsorgereminder"
    // permission_handler's Android side is built against API 37 and refuses
    // to be compiled into an app targeting less, whatever Flutter's default is.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time on API levels that predate
        // it; without desugaring the release build fails to link.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "de.vorsorgereminder.vorsorgereminder"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Written by release.sh in the same run as pubspec.yaml, so the two
        // cannot disagree about what a tag contains. When using split APKs,
        // 1000 * ABI_VERSION is added on top of this by Flutter.
        versionCode = 3
        versionName = "0.2.1"
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            // Without a keystore the build falls back to the debug keys so
            // `flutter run --release` keeps working; release.yml marks such a
            // build a prerelease rather than letting it pass for a real one.
            signingConfig = signingConfigs.getByName(
                if (keystoreProperties.isEmpty) "debug" else "release",
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

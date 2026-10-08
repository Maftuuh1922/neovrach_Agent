import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Fixed Neovarch signing key (dev/debug key, committed on purpose) so every
// APK — debug and release — carries the same certificate and installs over
// the previous one. Config lives in android/key.properties; if it or the
// keystore is missing, the build falls back to the default debug key.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}
val neovarchStoreFile: File? = keystoreProperties.getProperty("storeFile")
    ?.let { file(it) }
    ?.takeIf { it.exists() }
val hasNeovarchSigning = neovarchStoreFile != null &&
    keystoreProperties.getProperty("keyAlias") != null

android {
    namespace = "com.neovarch.agent"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.neovarch.agent"
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
        if (hasNeovarchSigning) {
            create("neovarch") {
                storeFile = neovarchStoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        val appSigning = if (hasNeovarchSigning) {
            signingConfigs.getByName("neovarch")
        } else {
            signingConfigs.getByName("debug")
        }
        debug {
            signingConfig = appSigning
        }
        release {
            signingConfig = appSigning
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

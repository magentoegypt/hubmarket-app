import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is read from android/key.properties (git-ignored). When that
// file is absent the build falls back to the debug key, so the repo still builds
// without any secrets present.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasReleaseSigning) FileInputStream(keystorePropertiesFile).use { load(it) }
}

android {
    // Internal code package (R/BuildConfig + MainActivity). Left unchanged to
    // avoid moving Kotlin sources; the store/runtime id is `applicationId` below.
    namespace = "com.hubmarket.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications (uses java.time APIs on
        // older API levels). See https://developer.android.com/studio/write/java8-support.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.hubmarket.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // dev / staging / prod so all three can coexist on one device. Each id must
    // be registered in the Firebase project for FCM (com.hubmarket.app[.dev|.staging]).
    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
        }
        create("staging") {
            dimension = "env"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-staging"
        }
        create("prod") {
            dimension = "env"
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
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
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                // No keystore yet — debug key so `flutter run --release` works.
                signingConfigs.getByName("debug")
            }
        }
    }
}

// Apply the Firebase Google Services plugin only when the config is present, so
// the app builds without FCM until google-services.json is added.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

dependencies {
    // Backports java.time etc. for flutter_local_notifications on older API levels.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // N-Genius card payments (hubmarket/payments channel). Latest stable at
    // integration time; docs/decisions/payments.md pinned 5.0.1 before the
    // SDK deprecated CardPaymentRequest in favour of PaymentsRequest.
    implementation("com.github.network-international.payment-sdk-android:payment-sdk:5.2.3")

    // Samsung Pay (hubmarket/payments channel, wallet=samsungpay). Already reachable
    // through payment-sdk's apiElements, but declared explicitly so the version is
    // pinned where it is actually used. Bundles Samsung's own samsungpay_2.22.00.jar.
    implementation("com.github.network-international.payment-sdk-android:payment-sdk-samsungpay:5.2.3")

    // payment.sdk.android.core.Order + CoroutinesGatewayHttpClient, which
    // SamsungPaySession builds and passes to SamsungPayClient. The SDK publishes
    // payment-sdk-core in runtimeElements ONLY (checked in the Gradle module
    // metadata), so without this line those types are on the runtime classpath
    // but invisible to the Kotlin compiler.
    implementation("com.github.network-international.payment-sdk-android:payment-sdk-core:5.2.3")

    // JVM unit tests for SamsungPaySession's pure helpers (no device, no SDK
    // setup). `org.json` is needed because android.jar's JSONObject is a stub
    // that throws "not mocked" under plain unit tests.
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

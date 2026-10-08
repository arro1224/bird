import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val releasePropertiesFile = rootProject.file("key.properties")
val releaseProperties = Properties().apply {
    if (releasePropertiesFile.exists()) {
        releasePropertiesFile.inputStream().use(::load)
    }
}

fun releaseCredential(propertyName: String, environmentName: String): String? =
    releaseProperties.getProperty(propertyName)?.trim()?.takeIf(String::isNotEmpty)
        ?: System.getenv(environmentName)?.trim()?.takeIf(String::isNotEmpty)

val releaseStoreFile = releaseCredential("storeFile", "AVES_RELEASE_STORE_FILE")
val releaseStorePassword = releaseCredential("storePassword", "AVES_RELEASE_STORE_PASSWORD")
val releaseKeyAlias = releaseCredential("keyAlias", "AVES_RELEASE_KEY_ALIAS")
val releaseKeyPassword = releaseCredential("keyPassword", "AVES_RELEASE_KEY_PASSWORD")
val hasAnyReleaseCredential = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).any { it != null }
val hasCompleteReleaseCredentials = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { it != null }

fun diagnosticSha(environmentName: String, expectedLength: Int): String {
    val value = System.getenv(environmentName)?.trim()?.lowercase()
    return if (value != null && value.length == expectedLength && value.all { it in '0'..'9' || it in 'a'..'f' }) {
        value
    } else {
        "unknown"
    }
}

val diagnosticGitSha = diagnosticSha("AVES_GIT_SHA", 40).let { configured ->
    if (configured != "unknown") {
        configured
    } else {
        runCatching {
            providers.exec {
                commandLine("git", "rev-parse", "HEAD")
            }.standardOutput.asText.get().trim().lowercase()
        }.getOrNull()?.takeIf { value ->
            value.length == 40 && value.all { it in '0'..'9' || it in 'a'..'f' }
        } ?: "unknown"
    }
}
val diagnosticApkSha = diagnosticSha("AVES_APK_SHA256", 64)

if (hasAnyReleaseCredential && !hasCompleteReleaseCredentials) {
    throw GradleException(
        "Release signing is only partially configured. " +
            "Provide storeFile, storePassword, keyAlias and keyPassword together.",
    )
}

android {
    namespace = "deckers.thibault.aves"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
        resValues = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "deckers.thibault.aves"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        buildConfigField("String", "GIT_SHA", "\"$diagnosticGitSha\"")
        buildConfigField("String", "APK_SHA256", "\"$diagnosticApkSha\"")
        buildConfigField("String", "BLE_SCAN_PERMISSION_POLICY", "\"never_for_location\"")
        buildConfigField("boolean", "BLE_SCAN_STRATEGY_FALLBACK_ENABLED", "false")
    }

    flavorDimensions += "app"
    productFlavors {
        create("bird") {
            dimension = "app"
            applicationId = "deckers.thibault.aves.bird"
            buildConfigField("boolean", "BLE_SCAN_STRATEGY_FALLBACK_ENABLED", "true")
        }
        create("birdSim") {
            dimension = "app"
            applicationId = "deckers.thibault.aves.bird.sim"
            resValue("string", "app_name", "拍鸟伴侣（模拟）")
        }
        create("birdScanA") {
            dimension = "app"
            applicationId = "deckers.thibault.aves.bird.scan.a"
            resValue("string", "app_name", "BirdBox 扫描 A")
            buildConfigField("boolean", "BLE_SCAN_STRATEGY_FALLBACK_ENABLED", "true")
        }
        create("birdScanB") {
            dimension = "app"
            applicationId = "deckers.thibault.aves.bird.scan.b"
            resValue("string", "app_name", "BirdBox 扫描 B")
            buildConfigField("String", "BLE_SCAN_PERMISSION_POLICY", "\"full_scan\"")
            buildConfigField("boolean", "BLE_SCAN_STRATEGY_FALLBACK_ENABLED", "true")
        }
    }

    signingConfigs {
        if (hasCompleteReleaseCredentials) {
            create("release") {
                storeFile = rootProject.file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
            isShrinkResources = false
            if (hasCompleteReleaseCredentials) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

androidComponents {
    beforeVariants(selector()) { variantBuilder ->
        val appFlavor = variantBuilder.productFlavors
            .firstOrNull { (dimension, _) -> dimension == "app" }
            ?.second
        if (appFlavor != "bird" && variantBuilder.buildType != "debug") {
            variantBuilder.enable = false
        }
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
}

flutter {
    source = "../.."
}

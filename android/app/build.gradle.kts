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
    }

    flavorDimensions += "app"
    productFlavors {
        create("bird") {
            dimension = "app"
            applicationIdSuffix = ".bird"
        }
        create("birdV1") {
            dimension = "app"
            applicationIdSuffix = ".bird.v1"
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

dependencies {
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
}

flutter {
    source = "../.."
}

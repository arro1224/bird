import java.util.Properties
import java.security.MessageDigest
import java.time.Instant

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

fun sourceGit(vararg args: String): String = providers.exec {
    workingDir(rootProject.projectDir.parentFile)
    commandLine(listOf("git") + args)
}.standardOutput.asText.get().trimEnd('\n', '\r')
fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
    .digest(bytes).joinToString("") { "%02x".format(it.toInt() and 255) }
val diagnosticGitSha = sourceGit("rev-parse", "HEAD").lowercase()
require(diagnosticGitSha.matches(Regex("[0-9a-f]{40}"))) { "Cannot determine actual Git HEAD" }
val configuredGit = System.getenv("AVES_GIT_SHA")?.trim()?.lowercase()
require(configuredGit == null || configuredGit == diagnosticGitSha) { "AVES_GIT_SHA differs from actual Git HEAD" }
val diagnosticDirty = sourceGit("status", "--porcelain").isNotEmpty()
val sourcePaths = sourceGit("-c", "core.quotepath=false", "ls-files", "--cached", "--others", "--exclude-standard")
    .lineSequence().filter { it.isNotEmpty() && !it.matches(Regex("^(docs|doc|\\.run)/.*")) && !it.endsWith("/README.md") && it != "README.md" }
    .distinct().sorted().toList()
val fingerprintInput = sourcePaths.joinToString("", transform = { path ->
    val file = rootProject.projectDir.parentFile.resolve(path)
    path + "\t" + (if (file.isFile) sha256(file.readBytes()) else "<deleted>") + "\n"
})
val diagnosticFingerprint = sha256(fingerprintInput.toByteArray(Charsets.UTF_8))
val configuredFingerprint = System.getenv("AVES_SOURCE_FINGERPRINT")?.trim()
require(configuredFingerprint == null || configuredFingerprint == diagnosticFingerprint) { "Source fingerprint differs from build manifest" }
val diagnosticBuildId = System.getenv("AVES_BUILD_ID")?.trim()
    ?: "ble-" + Instant.now().toEpochMilli() + "-" + diagnosticFingerprint.take(12)
require(diagnosticBuildId.matches(Regex("[A-Za-z0-9._-]{1,100}"))) { "Invalid build ID" }
// A final APK cannot embed its own final hash. Read installed APK bytes at runtime.
val diagnosticApkSha = "unknown"

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
        buildConfigField("boolean", "BUILD_DIRTY", diagnosticDirty.toString())
        buildConfigField("String", "BUILD_ID", "\"$diagnosticBuildId\"")
        buildConfigField("String", "SOURCE_FINGERPRINT", "\"$diagnosticFingerprint\"")
        buildConfigField("int", "SOURCE_FILE_COUNT", sourcePaths.size.toString())
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
    constraints {
        debugImplementation("androidx.test:runner:1.6.2") {
            because("Align Flutter integration-test runtime with the instrumentation runner")
        }
    }
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
}

flutter {
    source = "../.."
}

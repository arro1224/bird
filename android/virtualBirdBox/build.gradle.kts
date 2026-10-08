plugins {
    id("com.android.application")
}

val manualInstallBuild = providers.gradleProperty("virtualBirdBoxManualInstall")
    .map(String::toBoolean)
    .orElse(false)

android {
    namespace = "deckers.thibault.aves.virtualbirdbox"
    compileSdk = 37

    defaultConfig {
        applicationId = "deckers.thibault.aves.virtualbirdbox"
        // The virtual box uses BLE advertising/GATT-server APIs introduced in API 21.
        // Android 12+ still receives its runtime Nearby devices permission flow in
        // VirtualBirdBoxActivity; pre-S devices use the legacy manifest permissions.
        minSdk = 21
        targetSdk = 37
        versionCode = 1
        versionName = "ble11"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // The normal virtual-box build remains ADB/test-only. A temporary manual
        // install build is produced only with -PvirtualBirdBoxManualInstall=true
        // for vendor ROMs that block ADB installation.
        manifestPlaceholders["virtualBirdBoxTestOnly"] = (!manualInstallBuild.get()).toString()
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildTypes {
        getByName("debug") {
            applicationIdSuffix = ".debug"
        }
    }
}

androidComponents {
    beforeVariants(selector().withBuildType("release")) { variantBuilder ->
        variantBuilder.enable = false
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}

plugins {
    id("com.android.application")
}

android {
    namespace = "deckers.thibault.aves.virtualbirdbox"
    compileSdk = 37

    defaultConfig {
        applicationId = "deckers.thibault.aves.virtualbirdbox"
        minSdk = 31
        targetSdk = 37
        versionCode = 1
        versionName = "ble11"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
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

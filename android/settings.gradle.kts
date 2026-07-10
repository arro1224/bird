pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/central")
        maven("https://maven.aliyun.com/repository/gradle-plugin")
        maven("https://maven.aliyun.com/repository/public")
        maven("https://storage.flutter-io.cn/download.flutter.io")
        maven("https://storage.googleapis.com/download.flutter.io")
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/central")
        maven("https://maven.aliyun.com/repository/public")
        maven("https://storage.flutter-io.cn/download.flutter.io")
        maven("https://storage.googleapis.com/download.flutter.io")
        google()
        mavenCentral()
        maven("https://jitpack.io") {
            content {
                includeGroup("com.github.deckerst")
                includeGroup("com.github.deckerst.mp4parser")
            }
        }
        maven("https://s3.amazonaws.com/repo.commonsware.com") {
            content {
                excludeGroupByRegex("com\\.github\\.deckerst.*")
            }
        }
    }
}

// Settings plugins (`Plugin<Settings>`) must be applied in the settings script.
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"

    // provide a repository to download additional JDKs
    // e.g. for java/kotlin `jvmToolchain` defined in build scripts
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"

    // define versions (Gradle version catalog cannot be referenced here)
    id("com.android.application") version "9.2.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.21" apply false
}

include(":app")
include(":exifinterface")

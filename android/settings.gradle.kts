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
    // 与 Flutter 3.50 模板对齐：AGP 9.3.1 / Kotlin 2.4.20。
    // Flutter 3.50 的依赖校验下限是 Gradle 9.3.1、AGP 9.1.1、Kotlin 2.4.10，
    // 低于下限会直接构建失败（v1.5.14 就挂在 Gradle 9.1.0 上）。
    id("com.android.application") version "9.3.1" apply false
    id("org.jetbrains.kotlin.android") version "2.4.20" apply false
}

include(":app")

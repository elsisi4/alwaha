plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.alwaha_pricing"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.alwaha_pricing"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // تفعيل ميزات البناء للموارد المخصصة (لحل مشكلة Product Flavor contains custom resource values)
    buildFeatures {
        resValues = true
    }

    flavorDimensions += "app"
    productFlavors {
        create("distributor") {
            dimension = "app"
            applicationId = "com.alwaha.distributor"
            resValue("string", "app_name", "الواحة - المندوب")
        }
        create("admin") {
            dimension = "app"
            applicationId = "com.alwaha.admin"
            resValue("string", "app_name", "الواحة - الإدارة")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
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
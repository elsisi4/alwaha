import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// مفتاح التوقيع الرسمي: يُقرأ من android/key.properties (ينشئه سير العمل على GitHub
// من الـ Secrets، أو تنشئه أنت محليًا). بدونه يُوقَّع الملف بمفتاح التجربة.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
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

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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

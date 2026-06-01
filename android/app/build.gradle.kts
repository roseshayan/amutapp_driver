plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 👈 اضافه کردن این دو ایمپورت برای شناختن فرمت فایل کلید امضا حیاتی است
import java.io.FileInputStream
        import java.util.Properties

        android {
            namespace = "com.amutapp.driver.amutbar_driver"
            compileSdk = flutter.compileSdkVersion
            ndkVersion = flutter.ndkVersion

            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }

            defaultConfig {
                applicationId = "com.amutapp.driver.amutbar_driver"
                minSdk = flutter.minSdkVersion
                targetSdk = flutter.targetSdkVersion
                versionCode = flutter.versionCode
                versionName = flutter.versionName
            }

            // 👈 اضافه کردن این بخش برای لود کردن مشخصات کلید امضا از فایل key.properties
            val keystoreProperties = Properties()
            val keystorePropertiesFile = rootProject.file("key.properties")
            if (keystorePropertiesFile.exists()) {
                keystoreProperties.load(FileInputStream(keystorePropertiesFile))
            }

            signingConfigs {
                create("release") {
                    keyAlias = keystoreProperties["keyAlias"] as String?
                    keyPassword = keystoreProperties["keyPassword"] as String?
                    storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                    storePassword = keystoreProperties["storePassword"] as String?
                }
            }

            buildTypes {
                release {
                    // 👈 در کاتلین باید از متد getByName یا انتساب مستقیم با علامت مساوی استفاده شود
                    signingConfig = signingConfigs.getByName("release")

                    // 👈 در کاتلین باید قبل از مقدار true حتماً علامت مساوی (=) بگذارید
                    isMinifyEnabled = true
                    isShrinkResources = true

                    // 👈 استفاده از کوتیشن دوتایی ("") به جای تک کوتیشن ('') و پرانتز برای proguardFiles
                    proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
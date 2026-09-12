import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun mapsApiKey(): String {
    val local = Properties()
    val localFile = rootProject.file("local.properties")
    if (localFile.exists()) {
        localFile.inputStream().use { local.load(it) }
    }
    val fromLocal = local.getProperty("GOOGLE_MAPS_API_KEY")?.trim().orEmpty()
    if (fromLocal.isNotEmpty()) return fromLocal

    val envFile = rootProject.file("../.env")
    if (envFile.exists()) {
        envFile.readLines().forEach { line ->
            val trimmed = line.trim()
            if (trimmed.startsWith("GOOGLE_MAPS_API_KEY=")) {
                return trimmed.substringAfter("=").trim().trim('"', '\'')
            }
        }
    }
    return System.getenv("GOOGLE_MAPS_API_KEY")?.trim().orEmpty()
}

android {
    namespace = "com.hotpotchef.app"
    
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.hotpotchef.app"
        minSdk = flutter.minSdkVersion
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = mapsApiKey()
    }

    flavorDimensions += "storefront"
    productFlavors {
        create("diner") {
            dimension = "storefront"
            applicationId = "com.hotpotchef.app"
            resValue("string", "app_name", "HotPotChef")
        }
        create("partner") {
            dimension = "storefront"
            applicationId = "com.hotpotchef.partner"
            resValue("string", "app_name", "HotPotChef Partner")
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile")!!)
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                throw GradleException(
                    "Release builds need android/key.properties and an upload .jks. Debug signing is not allowed for Play/APK release."
                )
            }
            
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")
        }
    }
}

androidComponents {
    // Customer APK never scans FSSAI; drop ML Kit native OCR (~10 MB per ABI).
    onVariants(selector().withFlavor("storefront", "diner")) { variant ->
        variant.packaging.jniLibs.excludes.add("**/libmlkit*.so")
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

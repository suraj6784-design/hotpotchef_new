import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

fun loadGoogleMapsApiKey(): String {
    val fromEnv = System.getenv("GOOGLE_MAPS_API_KEY")?.trim().orEmpty()
    if (fromEnv.isNotEmpty()) return fromEnv

    val localProperties = Properties()
    val localFile = rootProject.file("local.properties")
    if (localFile.exists()) {
        localFile.inputStream().use { localProperties.load(it) }
        val fromLocal = localProperties.getProperty("GOOGLE_MAPS_API_KEY")?.trim().orEmpty()
        if (fromLocal.isNotEmpty()) return fromLocal
    }

    val dotenvFile = rootProject.file("../.env")
    if (dotenvFile.exists()) {
        for (raw in dotenvFile.readLines()) {
            val line = raw.trim()
            if (line.isEmpty() || line.startsWith("#")) continue
            val eq = line.indexOf('=')
            if (eq <= 0) continue
            val key = line.substring(0, eq).trim()
            if (key != "GOOGLE_MAPS_API_KEY") continue
            var value = line.substring(eq + 1).trim()
            if ((value.startsWith("\"") && value.endsWith("\"")) ||
                (value.startsWith("'") && value.endsWith("'"))
            ) {
                value = value.substring(1, value.length - 1)
            }
            if (value.isNotEmpty()) return value
        }
    }

    return "YOUR_GOOGLE_MAPS_API_KEY"
}

android {
    namespace = "com.hotpotchef.app"
    
    // 🌟 FIX: Force compileSdk to 37 to support flutter_secure_storage
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.hotpotchef.app"
        minSdk = flutter.minSdkVersion
        
        // 🌟 FIX: Force targetSdk to 37 to align with compileSdk
        targetSdk = 37
        
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = loadGoogleMapsApiKey()
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("debug")
            
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")
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
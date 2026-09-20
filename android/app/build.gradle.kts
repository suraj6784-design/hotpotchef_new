import com.flutter.gradle.tasks.FlutterTask
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

/** Base64-encodes one `KEY=value` dart-define the same way the Flutter tool does. */
fun encodeDartDefine(entry: String): String =
    Base64.getEncoder().encodeToString(entry.toByteArray(Charsets.UTF_8))

fun decodeDartDefines(encodedList: String?): List<String> {
    if (encodedList.isNullOrBlank()) return emptyList()
    return encodedList.split(',').mapNotNull { token ->
        val trimmed = token.trim()
        if (trimmed.isEmpty()) return@mapNotNull null
        try {
            String(Base64.getDecoder().decode(trimmed), Charsets.UTF_8)
        } catch (_: IllegalArgumentException) {
            trimmed
        }
    }
}

fun dartDefinesContainKey(encodedList: String?, key: String): Boolean =
    decodeDartDefines(encodedList).any { it.startsWith("$key=") }

/**
 * Ensures diner/partner Android flavors compile Dart with `APP_FLAVOR=<flavor>`.
 * Leaves an explicit CLI `--dart-define=APP_FLAVOR=...` in place.
 */
fun withStorefrontDartDefine(existing: String?, flavorName: String?): String? {
    val flavor = flavorName?.trim().orEmpty()
    if (flavor != "diner" && flavor != "partner") return existing
    if (dartDefinesContainKey(existing, "APP_FLAVOR")) return existing
    val encoded = encodeDartDefine("APP_FLAVOR=$flavor")
    return if (existing.isNullOrBlank()) encoded else "$existing,$encoded"
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
            firebaseCrashlytics {
                mappingFileUploadEnabled = true
            }
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

// `--flavor partner` already sets FLUTTER_APP_FLAVOR. Also inject APP_FLAVOR so
// kAppStorefront cannot silently default to diner when the CLI omits the extra define.
tasks.withType<FlutterTask>().configureEach {
    dartDefines = withStorefrontDartDefine(dartDefines, flavor)
    doFirst {
        val flavorName = flavor?.trim().orEmpty()
        if (flavorName != "diner" && flavorName != "partner") {
            return@doFirst
        }
        val decoded = decodeDartDefines(dartDefines)
        if (decoded.none { it == "APP_FLAVOR=$flavorName" }) {
            throw GradleException(
                "$name: storefront flavor '$flavorName' must compile with " +
                    "APP_FLAVOR=$flavorName. Got dart-defines: $decoded"
            )
        }
    }
}

tasks.register("assertStorefrontFlavorDefines") {
    group = "verification"
    description =
        "Fail if diner/partner flavors would not inject APP_FLAVOR dart-defines."
    doLast {
        val partner = withStorefrontDartDefine(null, "partner")
        val diner = withStorefrontDartDefine(null, "diner")
        check(decodeDartDefines(partner) == listOf("APP_FLAVOR=partner")) {
            "partner flavor must encode APP_FLAVOR=partner, got ${decodeDartDefines(partner)}"
        }
        check(decodeDartDefines(diner) == listOf("APP_FLAVOR=diner")) {
            "diner flavor must encode APP_FLAVOR=diner, got ${decodeDartDefines(diner)}"
        }
        val alreadySet = encodeDartDefine("APP_FLAVOR=diner")
        check(withStorefrontDartDefine(alreadySet, "partner") == alreadySet) {
            "explicit APP_FLAVOR dart-define must not be overwritten"
        }
        android.productFlavors.getByName("diner")
        android.productFlavors.getByName("partner")
        tasks.withType<FlutterTask>().forEach { task ->
            val flavorName = task.flavor?.trim().orEmpty()
            if (flavorName != "diner" && flavorName != "partner") return@forEach
            check(decodeDartDefines(task.dartDefines).any { it == "APP_FLAVOR=$flavorName" }) {
                "${task.name} is missing APP_FLAVOR=$flavorName (got ${decodeDartDefines(task.dartDefines)})"
            }
        }
        logger.lifecycle("Storefront dart-defines: diner=APP_FLAVOR=diner, partner=APP_FLAVOR=partner")
    }
}

tasks.matching { it.name == "check" }.configureEach {
    dependsOn("assertStorefrontFlavorDefines")
}

fun keytoolFingerprints(storeFile: File, alias: String, storePassword: String, keyPassword: String): String {
    val proc = ProcessBuilder(
        "keytool",
        "-list",
        "-v",
        "-keystore", storeFile.absolutePath,
        "-alias", alias,
        "-storepass", storePassword,
        "-keypass", keyPassword,
    ).redirectErrorStream(true).start()
    val text = proc.inputStream.bufferedReader().readText()
    proc.waitFor()
    val sha1 = Regex("SHA1:\\s*([0-9A-Fa-f:]+)").find(text)?.groupValues?.get(1).orEmpty()
    val sha256 = Regex("SHA256:\\s*([0-9A-Fa-f:]+)").find(text)?.groupValues?.get(1).orEmpty()
    return "    SHA-1  $sha1\n    SHA-256 $sha256"
}

tasks.register("printMapsKeyAndroidApps") {
    group = "verification"
    description = "Print package names and signing SHA values for Maps API key Android restrictions."
    doLast {
        println("Restrict GOOGLE_MAPS_API_KEY in Google Cloud to these Android apps:")
        println("  com.hotpotchef.app")
        println("  com.hotpotchef.partner")
        println("Allowed APIs: Maps SDK for Android, Places API, Geocoding API")
        val debugStore = File(System.getProperty("user.home"), ".android/debug.keystore")
        if (debugStore.exists()) {
            println("Debug keystore:")
            println(keytoolFingerprints(debugStore, "androiddebugkey", "android", "android"))
        }
        if (keystorePropertiesFile.exists()) {
            val store = file(keystoreProperties.getProperty("storeFile")!!)
            val alias = keystoreProperties.getProperty("keyAlias").orEmpty()
            val storePass = keystoreProperties.getProperty("storePassword").orEmpty()
            val keyPass = keystoreProperties.getProperty("keyPassword").orEmpty()
            if (store.exists() && alias.isNotEmpty()) {
                println("Release upload keystore (${store.name}):")
                println(keytoolFingerprints(store, alias, storePass, keyPass))
            }
        }
        val googleServices = file("google-services.json")
        if (googleServices.exists()) {
            @Suppress("UNCHECKED_CAST")
            val root = groovy.json.JsonSlurper().parse(googleServices) as Map<String, Any>
            val clients = root["client"] as List<Map<String, Any>>
            val ids = clients.associate { client ->
                val info = client["client_info"] as Map<String, Any>
                val pkg = (info["android_client_info"] as Map<String, Any>)["package_name"] as String
                pkg to (info["mobilesdk_app_id"] as String)
            }
            val dinerId = ids["com.hotpotchef.app"]
            val partnerId = ids["com.hotpotchef.partner"]
            if (dinerId == null || partnerId == null) {
                logger.warn("google-services.json is missing diner or partner Android client entries.")
            } else if (dinerId == partnerId) {
                logger.warn(
                    "google-services.json clones the diner Firebase Android app id onto com.hotpotchef.partner. Register a distinct Android app in Firebase project hotpotchef-c53fa, then replace android/app/google-services.json."
                )
            } else {
                println("Firebase Android apps are distinct:")
                println("  diner   $dinerId")
                println("  partner $partnerId")
            }
        }
    }
}


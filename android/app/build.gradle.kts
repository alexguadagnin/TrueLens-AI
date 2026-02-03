plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.true_lens_ai_v2"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDir("src/main/jniLibs")
        }
    }

    defaultConfig {
        applicationId = "com.example.true_lens_ai_v2"
        minSdk = flutter.minSdkVersion 
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            
            isMinifyEnabled = true // Abilita la riduzione del codice
            isShrinkResources = true // (Opzionale) Riduce le risorse
            
            // Collega il file delle regole
            proguardFiles(
                getDefaultProguardFile("proguard-android.txt"),
                "proguard-rules.pro"
            )
            // -----------------------------
        }
    }
}

flutter {
    source = "../.."
}

// --- TOOLCHAIN JAVA 17 (SOLUZIONE DEFINITIVA) ---
java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(17))
    }
}
// -----------------------------------------------

dependencies {
    // Qui aggiungiamo le dipendenze se servono fix manuali, ma per ora lascia vuoto o standard
}

// 1. Applica il plugin
apply(from = "../../rust_builder/cargokit/gradle/plugin.gradle")

// 2. Configura le proprietà (Sintassi speciale per Kotlin DSL che parla con Groovy)
// Questo risolve l'errore "null object"
try {
    val cargokit = extensions.getByName("cargokit") as groovy.lang.GroovyObject
    // La cartella dove sta il file Cargo.toml
    cargokit.setProperty("manifestDir", "../../rust")  
    // Il nome esatto che c'è dentro Cargo.toml sotto [lib]
    cargokit.setProperty("libname", "rust_lib_true_lens_ai_v2") 
} catch (e: Exception) {
    println("Attenzione: Impossibile configurare Cargokit: $e")
}

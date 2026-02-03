buildscript {
    repositories {
        google()        
        mavenCentral()
    }
    dependencies {
        // Il plugin per i servizi Google (Firebase, Login, ecc.)
        classpath("com.google.gms:google-services:4.4.2")
    }
}

import org.jetbrains.kotlin.gradle.tasks.KotlinCompile
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// --- FIX PERCORSO BUILD (Basato sulla tua scoperta StackOverflow) ---
// Usiamo la nuova API "layout" per dire a Gradle di mettere l'output
// nella cartella "build" che sta nella root del progetto Flutter (../build)
val newBuildDir = rootProject.layout.projectDirectory.dir("../build")
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

// --- FIX JAVA 17 ---
subprojects {
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = "17"
        targetCompatibility = "17"
    }

    tasks.withType<KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

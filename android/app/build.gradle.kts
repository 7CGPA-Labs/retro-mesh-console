import java.net.URI
import java.io.FileOutputStream
import java.util.zip.ZipInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "dev.seven_cgpalabs.mojosnap"
    compileSdk = 34

    defaultConfig {
        applicationId = "dev.seven_cgpalabs.mojosnap"
        minSdk = 30
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
        
        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    kotlinOptions {
        jvmTarget = "1.8"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.11"
    }
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("androidx.activity:activity-compose:1.8.2")
    implementation(platform("androidx.compose:compose-bom:2024.02.02"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    
    // Media Router / Miracast
    // (Removed because Native Android DisplayManager handles Miracast)

    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.5.1")
}

tasks.register("downloadCores") {
    val cores = listOf(
        "pcsx_rearmed",
        "gambatte",
        "mgba",
        "dosbox_pure",
        "fceumm",
        "genesis_plus_gx",
        "snes9x"
    )
    val baseUrl = "https://buildbot.libretro.com/nightly/android/latest/arm64-v8a"
    val ext = "_libretro_android.so"
    val jniLibsDir = file("src/main/jniLibs/arm64-v8a")
    
    outputs.dir(jniLibsDir)
    
    doLast {
        if (!jniLibsDir.exists()) {
            jniLibsDir.mkdirs()
        }
        
        for (core in cores) {
            val originalSoName = "${core}${ext}"
            val destSoName = "lib${core}${ext}"
            val soFile = file("${jniLibsDir.absolutePath}/${destSoName}")
            if (!soFile.exists()) {
                println("Downloading ${core}...")
                val zipUrl = URI("${baseUrl}/${originalSoName}.zip").toURL()
                try {
                    zipUrl.openStream().use { input ->
                        ZipInputStream(input).use { zis ->
                            var entry = zis.nextEntry
                            while (entry != null) {
                                if (entry.name == originalSoName) {
                                    FileOutputStream(soFile).use { out ->
                                        zis.copyTo(out)
                                    }
                                }
                                entry = zis.nextEntry
                            }
                        }
                    }
                    println("Extracted ${destSoName}")
                } catch (e: Exception) {
                    println("Failed to download ${core}: ${e.message}")
                }
            }
        }
    }
}

tasks.named("preBuild") {
    dependsOn("downloadCores")
}

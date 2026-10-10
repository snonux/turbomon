group = "org.buetow.turbomon"
version = "0.1.0"

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "org.buetow.turbomon.platform"
    compileSdk = 36
    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
    }
    // The Shizuku shell runs behind an AIDL interface (IShellService.aidl).
    buildFeatures { aidl = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = JavaVersion.VERSION_17.toString() }
}

dependencies {
    // Shizuku (Apache-2.0, Maven Central): optional ADB-shell rights for the
    // process list, /proc/stat, GPU and disk I/O. Nothing uses it unless the
    // user installs Shizuku and grants TurboMon access.
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")
    // FileProvider for sharing snapshot files.
    implementation("androidx.core:core-ktx:1.13.1")
    testImplementation("junit:junit:4.13.2")
}

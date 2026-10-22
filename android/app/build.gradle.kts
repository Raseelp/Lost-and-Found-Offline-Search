import java.util.Properties
import java.io.FileInputStream


// What this build was made from, shown in Settings: the short commit hash (with a "+" when the working tree had
// changes that were not committed) and the date of that commit. "unknown" when git is not there.
fun git(vararg args: String): String = try {
    val process = ProcessBuilder(listOf("git") + args)
        .directory(rootProject.projectDir.parentFile)
        .redirectErrorStream(true)
        .start()
    val text = process.inputStream.bufferedReader().readText().trim()
    if (process.waitFor() == 0) text else ""
} catch (e: Exception) {
    ""
}
val gitCommit: String = git("rev-parse", "--short=7", "HEAD").ifEmpty { "unknown" } +
    if (git("status", "--porcelain").isNotEmpty()) "+" else ""
val gitCommitDate: String = git("log", "-1", "--format=%cs").ifEmpty { "unknown" }

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.raseel.lostandfound"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    buildFeatures {
        buildConfig = true
    }

    packaging {
        jniLibs {
            // ONNX Runtime carries its own copy of the C++ runtime.
            pickFirsts += "**/libc++_shared.so"
        }
    }

    defaultConfig {
        applicationId = "dev.raseel.lostandfound"
        // 24, not 23: ONNX Runtime needs at least Android 7.0.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Fallback for the "profile" build type, which Flutter adds
        // automatically and doesn't get its own override below.
        buildConfigField("String", "MODEL_BASE_URL", "\"http://10.0.2.2:8000\"")
        buildConfigField("String", "GIT_COMMIT", "\"$gitCommit\"")
        buildConfigField("String", "GIT_COMMIT_DATE", "\"$gitCommitDate\"")
    }
    signingConfigs {
        create("release") {
            val keystorePropertiesFile = rootProject.file("key.properties")
            val keystoreProperties = Properties().apply {
                load(FileInputStream(keystorePropertiesFile))
            }

            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
        }
    }


    buildTypes {
        debug {
            // A second app next to the real one (same name in the code, its own data): installing a debug build can
            // never replace - or, with a different signing key, uninstall and wipe - the app that is in use.
            applicationIdSuffix = ".debug"
            // model_host/serve.py - run `adb reverse tcp:8000 tcp:8000` first.
            buildConfigField("String", "MODEL_BASE_URL", "\"http://127.0.0.1:8000\"")
        }
        release {
            signingConfig = signingConfigs.getByName("release")

            isMinifyEnabled = false
            isShrinkResources = false

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                file("proguard-rules.pro")
            )

            // Matches the "models-v1" GitHub Release tag - see model_host/README.md. The release holds the MobileCLIP-S0
            // files this version downloads, and still the CLIP ViT-B/32 files that older versions download.
            buildConfigField(
                "String",
                "MODEL_BASE_URL",
                "\"https://github.com/Raseelp/Lost-and-Found-Offline-Search/releases/download/models-v1\""
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.documentfile:documentfile:1.0.1")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.exifinterface:exifinterface:1.3.7")
    implementation("androidx.work:work-runtime-ktx:2.11.2")
    // CLIP (search/indexing) and face detection/recognition all run through
    // this - PyTorch Mobile (and the soloader it needed) was dropped once
    // CLIP moved to ONNX too, since nothing else in the app still used it.
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.22.0")

    // Runs on the computer, not the phone: checks the zip writer (see export/ZipPartWriter.kt).
    testImplementation("junit:junit:4.13.2")
}

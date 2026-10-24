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
    // 36 (Android 16), above Flutter's default: the scan notification uses Android 16's progress style and asks for
    // the status bar chip (see ScanNotification).
    compileSdk = 36
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

        // Every build type downloads the search model from the "models-v1" GitHub Release tag - see
        // model_host/README.md. The release holds the MobileCLIP-S0 files this version downloads, and still the CLIP
        // ViT-B/32 files that older versions download.
        buildConfigField(
            "String",
            "MODEL_BASE_URL",
            "\"https://github.com/Raseelp/Lost-and-Found-Offline-Search/releases/download/models-v1\""
        )
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
        }
        release {
            signingConfig = signingConfigs.getByName("release")

            isMinifyEnabled = false
            isShrinkResources = false

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                file("proguard-rules.pro")
            )
        }
        // A release build (compiled ahead of time, so it runs at full speed) that is a third app next to the real
        // one, with its own data, like debug: for trying a change at real speed without replacing the app in use.
        // Signed with the debug key, never the release key. Build it with `./gradlew assemblePreview` in android/.
        create("preview") {
            initWith(getByName("release"))
            signingConfig = signingConfigs.getByName("debug")
            // Nothing is shrunk (as in release), so no ProGuard files: and the copy of this build type that Flutter
            // gives each plugin must not point at the app's own.
            proguardFiles.clear()
            // The plugins have no build type of this name: they are built as for release.
            matchingFallbacks += listOf("release")
        }
    }
}

// The preview's own app id. Not set on the build type: Flutter copies the app's build types into each plugin, and a
// plugin (a library) may not have one.
androidComponents {
    onVariants(selector().withBuildType("preview")) { variant ->
        variant.applicationId.set("dev.raseel.lostandfound.preview")
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

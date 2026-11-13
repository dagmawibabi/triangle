import com.android.build.api.variant.ApplicationAndroidComponentsExtension
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.FileSystemOperations
import org.gradle.api.tasks.InputDirectory
import org.gradle.api.tasks.Optional
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.TaskAction
import javax.inject.Inject

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.teleai"
    // flutter_local_notifications 23 and androidx.core 1.19 need 37 (Flutter
    // 3.50 defaults to 36). Only the compile SDK; minSdk/targetSdk unchanged.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications uses java.time on older Androids.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.teleai"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // Background removal for the image tools, on the phone (the model comes
    // through Google Play services on first use).
    implementation("com.google.android.gms:play-services-mlkit-subject-segmentation:16.0.0-beta1")
}

/**
 * Flutter 3.47.0 still copies flutter_assets into mergeAssets.outputDir after the
 * merge. AGP 9.1 packages declared asset sources instead, so the MaterialIcons
 * font never reaches the APK and icon glyphs fall back to CJK characters.
 *
 * Register the compiled flutter_assets folder as a generated assets source so
 * AGP actually packs it. Later Flutter SDKs do this in the plugin itself.
 */
abstract class StageFlutterAssetsTask : DefaultTask() {
    @get:Optional
    @get:InputDirectory
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val intermediateDir: DirectoryProperty

    @get:OutputDirectory
    abstract val destinationDir: DirectoryProperty

    @get:Inject
    abstract val fileSystemOperations: FileSystemOperations

    @TaskAction
    fun copy() {
        fileSystemOperations.sync {
            into(destinationDir)
            if (intermediateDir.isPresent) {
                from(intermediateDir.dir("flutter_assets")) {
                    into("flutter_assets")
                }
            }
        }
    }
}

fun String.asGradleSuffix(): String = replaceFirstChar { it.uppercase() }

extensions.configure<ApplicationAndroidComponentsExtension> {
    onVariants { variant ->
        val compileTaskName = "compileFlutterBuild${variant.name.asGradleSuffix()}"
        val stageTask =
            tasks.register<StageFlutterAssetsTask>(
                "stageFlutterAssets${variant.name.asGradleSuffix()}",
            ) {
                dependsOn(tasks.matching { it.name == compileTaskName })
                intermediateDir.set(
                    layout.buildDirectory.dir("intermediates/flutter/${variant.name}"),
                )
            }
        val assets =
            variant.sources.assets
                ?: error("AGP did not expose an assets source set for ${variant.name}")
        assets.addGeneratedSourceDirectory(
            stageTask,
            StageFlutterAssetsTask::destinationDir,
        )
    }
}

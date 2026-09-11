import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Signature de version release : lit android/key.properties (jamais commité,
// voir .gitignore) pour signer l'app avec la vraie clé d'upload plutôt
// qu'avec la clé de débogage — nécessaire pour la Play Console.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.margauxsilva.exercise_kitchen"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.margauxsilva.exercise_kitchen"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            // Signature réelle (clé "upload"), voir keystoreProperties ci-dessus.
            signingConfig = signingConfigs.getByName("release")
            // Activé le 11 septembre 2026 (avertissement Play Console "Améliorez
            // la mémoire et les performances de votre appli avec l'optimisation
            // R8" sur le tableau de bord des releases) : le R8/tree-shaking Dart
            // de Flutter est déjà actif par défaut en release, mais PAS le
            // minify/shrink côté Gradle (bytecode Java/Kotlin des plugins), qui
            // est ce que Play Console mesure ici — d'où l'activation explicite
            // ci-dessous. Règles de conservation nécessaires (Firebase,
            // flutter_secure_storage, local_auth) dans proguard-rules.pro.
            // IMPORTANT : à tester en conditions réelles (build --release, pas
            // debug/profile) sur connexion, biométrie, notifications et photos
            // avant publication, le R8 pouvant casser du code utilisant la
            // réflexion s'il manque une règle de conservation.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}
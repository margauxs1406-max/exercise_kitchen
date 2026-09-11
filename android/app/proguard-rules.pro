# Règles de conservation R8 — activé le 11 septembre 2026 (avertissement Play
# Console "Améliorez la mémoire et les performances de votre appli avec
# l'optimisation R8" sur le tableau de bord des releases, voir build.gradle.kts).
#
# Le Flutter engine (io.flutter.embedding, plugin registrant généré...) est
# déjà couvert par les consumer-rules embarquées dans le plugin Gradle Flutter
# — pas besoin de règles manuelles pour ça.
#
# Les règles ci-dessous couvrent les dépendances du projet qui utilisent de la
# réflexion et pourraient être cassées par l'obfuscation/le shrinking sans
# elles.

# --- Firebase / Google Play services ---
# La plupart des SDK Firebase embarquent déjà leurs propres consumer-rules
# dans leur .aar ; ces règles sont une sécurité supplémentaire.
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# --- flutter_secure_storage ---
# Stockage chiffré (Android Keystore / EncryptedSharedPreferences), basé sur
# Tink côté Android — utilisé pour la reconnexion silencieuse protégée par
# biométrie (voir credential_store.dart). Tink utilise beaucoup de réflexion.
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**
-keep class androidx.security.crypto.** { *; }
-dontwarn androidx.security.crypto.**

# --- local_auth ---
-keep class androidx.biometric.** { *; }
-dontwarn androidx.biometric.**

# --- Play Core (référencé par le tooling Flutter pour les "deferred
# components" — non utilisé par l'app, règle défensive pour éviter un
# avertissement de compilation, sans effet si absent). ---
-dontwarn com.google.android.play.core.**

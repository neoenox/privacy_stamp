# Preserve ML Kit and platform-channel bridge classes in release builds.
# Optional text scripts are bundled explicitly in build.gradle.kts; no
# missing-class warning suppression is needed.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision** { *; }
-keep class com.google_mlkit_** { *; }

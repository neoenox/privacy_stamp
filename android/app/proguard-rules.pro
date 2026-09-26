# google_mlkit_text_recognition exposes optional script implementations from
# one Flutter bridge. Japanese is bundled by this app; the other script
# implementations are intentionally absent and must not make R8 fail.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit and Flutter bridge classes are reached through platform channels and
# native registrars. Preserve them in the release smoke build.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision** { *; }
-keep class com.google_mlkit_** { *; }

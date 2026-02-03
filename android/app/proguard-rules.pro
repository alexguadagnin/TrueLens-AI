# Ignora i warning per le lingue non installate di ML Kit
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.**

# Mantieni le classi necessarie
-keep class com.google.mlkit.vision.text.** { *; }
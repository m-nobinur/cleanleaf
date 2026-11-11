# Tesseract4Android ships no consumer rules; its JNI looks up Java members by name.
-keep class com.googlecode.tesseract.android.** { *; }
-keep class com.googlecode.leptonica.android.** { *; }

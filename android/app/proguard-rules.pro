# Tesseract4Android ships no consumer rules; its JNI looks up Java members by name.
-keep class com.googlecode.tesseract.android.** { *; }
-keep class com.googlecode.leptonica.android.** { *; }
# T-032 spike probe: onnxruntime and OpenCV JNI also look up members by name.
-keep class ai.onnxruntime.** { *; }
-keep class org.opencv.** { *; }
# Readable ML Kit traces in the probe (names only; shrinking still applies).
-keepnames class com.google.mlkit.** { *; }
-keepnames class com.google.android.datatransport.** { *; }
-keep class com.google.android.datatransport.runtime.TransportRuntime { public static void initialize(android.content.Context); }
-keep class com.google.mlkit.common.sdkinternal.MlKitContext { public static *** initialize(android.content.Context, java.util.List); }
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }

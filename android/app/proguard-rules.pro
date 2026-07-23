# Keep native method signatures intact
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep JNI classes
-keep class dev.seven_cgpalabs.mojosnap.** { *; }

# Strip unused code
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int i(...);
    public static int w(...);
    public static int d(...);
    public static int e(...);
}

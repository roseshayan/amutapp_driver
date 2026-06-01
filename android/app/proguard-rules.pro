# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
# Flutter Play Store Split support
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# If you still see errors, add these as well:
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
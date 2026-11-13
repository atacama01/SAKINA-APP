# flutter_local_notifications stores its pending notifications as JSON and
# reads them back with Gson. Gson needs the generic type information that R8
# removes by default; without it, release builds throw
# "Missing type parameter" from loadScheduledNotifications(), which used to
# leave the app stuck on its startup spinner.
-keepattributes Signature
-keepattributes *Annotation*

# Keep the generic signatures of Gson's TypeToken and its anonymous
# subclasses (Gson's official R8 guidance).
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# Gson reads and writes these notification models reflectively.
-keep class com.dexterous.flutterlocalnotifications.** { *; }

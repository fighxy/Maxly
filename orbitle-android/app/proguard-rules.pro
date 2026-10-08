# Ядро max-kmp-core разбирает ответы сервера по именам полей и типам; не трогаем его классы.
-keep class com.max.** { *; }
-keepattributes Signature, InnerClasses, EnclosingMethod, *Annotation*
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
# WebRTC зовёт свои Java-классы из JNI по именам.
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

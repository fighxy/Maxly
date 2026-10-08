# Ядро max-kmp-core разбирает ответы сервера по именам полей и типам; не трогаем его классы.
-keep class com.max.** { *; }
-keepattributes Signature, InnerClasses, EnclosingMethod, *Annotation*
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
# WebRTC зовёт свои Java-классы из JNI по именам.
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**
# И классы jni_zero тоже: JNI_OnLoad библиотеки WebRTC первым делом зовёт
# org.jni_zero.JniInit.init(). Из Java на них никто не ссылается, и R8 их выкидывал — релизная
# сборка падала в нативном коде (abort) при первой загрузке WebRTC, то есть на первом звонке.
-keep class org.jni_zero.** { *; }
-dontwarn org.jni_zero.**

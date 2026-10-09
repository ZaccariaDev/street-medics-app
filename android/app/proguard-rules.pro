# Règles ProGuard/R8 pour la release.
#
# Flutter et la plupart des plugins fournissent leurs propres règles.
# On garde explicitement les plugins utilisés par l'app pour éviter que R8
# ne supprime des classes atteintes uniquement par réflexion.

# flutter_local_notifications (sérialisation GSON des notifications)
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**

# flutter_foreground_task (service natif)
-keep class com.pravera.flutter_foreground_task.** { *; }

# geolocator (service natif)
-keep class com.baseflow.geolocator.** { *; }

# PocketBase / HTTP (dart:io côté natif, rien à garder côté Java,
# mais on évite les avertissements R8 sur les annotations manquantes)
-dontwarn org.jetbrains.annotations.**

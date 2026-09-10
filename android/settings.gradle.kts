pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").let { file ->
            if (file.exists()) {
                file.reader().use { properties.load(it) }
            }
        }
        properties.getProperty("flutter.sdk")
    }
    
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("com.android.application") version "8.2.1" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}

include(":app")

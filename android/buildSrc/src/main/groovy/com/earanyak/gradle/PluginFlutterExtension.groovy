package com.earanyak.gradle

import groovy.lang.GroovyObjectSupport

/**
 * Minimal stand-in for the `flutter` extension.
 *
 * The Flutter Gradle Plugin only attaches the real `flutter` extension to the
 * :app module. Plugin library modules (e.g. android_file_picker 2.1.2) read
 * `flutter.compileSdkVersion` in their Android build scripts and fail with
 * "Extension with name 'flutter' does not exist" when the extension is
 * missing. This stub provides just enough for those scripts to keep working.
 *
 * compileSdkVersion = 36 matches the value set for library modules in the
 * root build script.
 */
class PluginFlutterExtension extends GroovyObjectSupport {
    final int compileSdkVersion = 36

    @Override
    Object getProperty(String name) {
        if (name == "compileSdkVersion") {
            return compileSdkVersion
        }
        return super.getProperty(name)
    }
}
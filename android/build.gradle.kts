allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

// Fixed namespace handling (works with evaluation order)
subprojects {
    pluginManager.withPlugin("com.android.library") {
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.let { android ->
            if (android.namespace.isNullOrEmpty()) {
                android.namespace = project.group.toString().ifEmpty { "com.example.${project.name}" }
            }
        }
    }
    pluginManager.withPlugin("com.android.application") {
        extensions.findByType(com.android.build.gradle.AppExtension::class.java)?.let { android ->
            if (android.namespace.isNullOrEmpty()) {
                android.namespace = project.group.toString().ifEmpty { "com.example.${project.name}" }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
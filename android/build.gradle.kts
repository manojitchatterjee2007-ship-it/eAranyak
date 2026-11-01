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

subprojects {
    pluginManager.withPlugin("org.jetbrains.kotlin.android") {
        if (!pluginManager.hasPlugin("com.android.library") && !pluginManager.hasPlugin("com.android.application")) {
            apply(plugin = "com.android.library")
        }
    }
}

subprojects {
    if (project.name != "app") {
        pluginManager.withPlugin("com.android.library") {
            extensions.findByType(com.android.build.api.dsl.LibraryExtension::class.java)?.let { android ->
                android.compileSdk = 36
            }
        }
    }
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
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

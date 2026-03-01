allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Auto-set namespace for old plugins that only have it in AndroidManifest.xml
subprojects {
    plugins.withId("com.android.library") {
        val androidExt = extensions.findByName("android")
                as? com.android.build.gradle.LibraryExtension ?: return@withId
        if (androidExt.namespace.isNullOrEmpty()) {
            val manifest = file("src/main/AndroidManifest.xml")
            if (manifest.exists()) {
                val match = Regex("""package="([^"]+)"""").find(manifest.readText())
                if (match != null) {
                    androidExt.namespace = match.groupValues[1]
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

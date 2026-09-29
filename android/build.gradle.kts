allprojects {
    repositories {
        google()
        mavenCentral()
        // N-Genius (Network International) publishes payment-sdk-android via
        // JitPack only — it is not on Maven Central. Used by
        // app/src/main/kotlin/com/hubmarket/app/PaymentChannel.kt.
        maven { url = uri("https://jitpack.io") }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

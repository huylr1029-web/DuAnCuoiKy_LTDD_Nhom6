// Agora plugin (agora_rtc_engine 6.6.4) lay compileSdk tu
// rootProject.ext.compileSdkVersion, mac dinh fallback ve 31 neu khong
// dat, nen build loi checkDebugAarMetadata khi cac thu vien androidx
// cua no doi compileSdk >= 34. Dat o day de plugin bien dich voi 36,
// khop voi compileSdk = 36 cua app o android/app/build.gradle.kts.
extra["compileSdkVersion"] = 36

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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

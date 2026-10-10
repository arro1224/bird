val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    // AGP's unit-test configuration uses paths relative to the plugin project.
    // Windows cannot relativize paths across drives (for example Pub on C:
    // and this application's build directory on D:).
    val newSubprojectBuildDir = if (
        project.projectDir.toPath().root == newBuildDir.asFile.toPath().root
    ) {
        newBuildDir.dir(project.name)
    } else {
        project.layout.projectDirectory.dir("build")
    }
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

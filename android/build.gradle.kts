allprojects {
    repositories {
        google()
        mavenCentral()
        // 官方仓库优先，阿里云镜像只作国内网络回退。
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/central")
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
// 老三方插件（如 install_plugin 2.1.0）跟不上 AGP 8 / Kotlin 新工具链，
// 这里在 root 层给所有 Android 子模块打三个兜底补丁：
//   1. namespace 缺失时从 AndroidManifest 的 package 属性回填（AGP 8 要求必填）
//   2. Java source/target 统一升到 17，匹配 Kotlin Gradle Plugin 默认的 jvmTarget=17，
//      解决 "Inconsistent JVM-target compatibility" 报错。
//   3. compileSdk 兜底到 34：Java 17 源码要求 compileSdk≥30，老插件常停在 28。
// 必须在下方 evaluationDependsOn(":app") 之前注册 hook，否则 :app 已被评估会抛
// "Cannot run Project.afterEvaluate when the project is already evaluated"。
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android")
            as? com.android.build.gradle.BaseExtension ?: return@afterEvaluate

        if (androidExt.namespace.isNullOrBlank()) {
            val manifest = file("src/main/AndroidManifest.xml")
            if (manifest.exists()) {
                val pkg = Regex("""package\s*=\s*"([^"]+)"""")
                    .find(manifest.readText())
                    ?.groupValues
                    ?.getOrNull(1)
                if (!pkg.isNullOrBlank()) {
                    androidExt.namespace = pkg
                    logger.lifecycle("🩹 注入 namespace=$pkg -> ${project.path}")
                }
            }
        }

        // app 自己保留 Java 11 + Kotlin 11 的显式配置，不用兜底。
        if (project.path != ":app") {
            val curSdk = androidExt.compileSdkVersion
                ?.removePrefix("android-")
                ?.toIntOrNull() ?: 0
            if (curSdk < 34) {
                androidExt.compileSdkVersion(34)
                logger.lifecycle("🩹 升级 compileSdk 28/29 -> 34 -> ${project.path}")
            }
            androidExt.compileOptions.sourceCompatibility = JavaVersion.VERSION_17
            androidExt.compileOptions.targetCompatibility = JavaVersion.VERSION_17
            // 有些插件（flutter_image_compress_common 等）会把 kotlinOptions.jvmTarget 硬编码成 11，
            // 这里在 task 级别最后一次覆盖，保证 Kotlin 与 Java 都是 17。
            tasks.matching {
                it.name.startsWith("compile") &&
                    it.name.endsWith("Kotlin") &&
                    it.javaClass.name.contains("KotlinCompile")
            }.configureEach {
                val opts = javaClass.methods
                    .firstOrNull { it.name == "getKotlinOptions" }
                    ?.invoke(this) ?: return@configureEach
                opts.javaClass.methods
                    .firstOrNull {
                        it.name == "setJvmTarget" &&
                            it.parameterTypes.size == 1 &&
                            it.parameterTypes[0] == String::class.java
                    }
                    ?.invoke(opts, "17")
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

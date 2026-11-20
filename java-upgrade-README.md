Upgrade Java runtime to Java 21 (LTS)

This project uses Gradle and Android Gradle Plugin. The repository has been updated to target Java 21 in `android/app/build.gradle.kts` and `android/gradle.properties` contains a sample `org.gradle.java.home` pointing to a JDK 21 installation on macOS.

Steps to install and verify JDK 21 on macOS:

1. Install a JDK 21 distribution (Temurin/Adoptium recommended):

   brew install --cask temurin21

2. Verify the installation and find the JAVA_HOME path:

   /usr/libexec/java_home -v 21

   # Example output:
   # /Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home

3. (Optional) Set JAVA_HOME for your shell (zsh):

   echo 'export JAVA_HOME=$(/usr/libexec/java_home -v 21)' >> ~/.zshrc
   source ~/.zshrc

4. (Optional) Instead of setting JAVA_HOME globally, update `android/gradle.properties` with the path to your JDK 21 install. The file contains an example:

   org.gradle.java.home=/Library/Java/JavaVirtualMachines/jdk-21.jdk/Contents/Home

5. Verify Gradle picks up Java 21 and build the Android project:

   # From project root
   ./gradlew -p android --version
   ./gradlew -p android assembleDebug

Notes and compatibility:
- The project already sets `sourceCompatibility`, `targetCompatibility`, and Kotlin `jvmTarget` to Java 21 in `android/app/build.gradle.kts`.
- Android Gradle Plugin 8.9.1 and Kotlin 2.1.0 are present in `android/settings.gradle.kts`. These should support JDK 21, but if you encounter tooling errors, consider updating the Android Gradle Plugin and Kotlin plugin to newer compatible versions.
- If CI or other developers use different JDK locations, prefer setting `org.gradle.java.home` locally or setting JAVA_HOME in CI config instead of committing a machine-specific path.

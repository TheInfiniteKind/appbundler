appbundler
=============

A fork of the [Java Application Bundler](https://svn.java.net/svn/appbundler~svn) 
with the following changes:

- The native binary is created as universal (32/64)
- Fixes [icon not showing bug](http://bugs.sun.com/bugdatabase/view_bug.do?bug_id=7159381) in `JavaAppLauncher`
- Adds `LC_CTYPE` environment variable to the `Info.plist` file in order to fix an [issue with `File.exists()` in OpenJDK 7](http://java.net/jira/browse/MACOSX_PORT-165)  **(Contributed by Steve Hannah)**
- Allows to specify the name of the executable instead of using the default `"JavaAppLauncher"` **(contributed by Karl von Randow)**
- Adds `classpathref` support to the `bundleapp` task
- Adds support for `JVMArchs` and `LSArchitecturePriority` keys
- Allows to specify a custom value for `CFBundleVersion` 
- Allows specifying registered file extensions using `CFBundleDocumentTypes`
- Passes to the Java application a set of environment variables with the paths of
  the OSX special folders and whether the application is running in the
  sandbox (see below).
- Allows overriding of passed JVM options by the bundled app itself via java.util.Preferences **(contributed by Hendrik Schreiber)**

These are the environment variables passed to the JVM:

- `LibraryDirectory`
- `DocumentsDirectory`
- `CachesDirectory`
- `ApplicationSupportDirectory`
- `SandboxEnabled` (the String `true` or `false`)


Example 1:

    <target name="bundle">
      <taskdef name="bundleapp" 
        classpath="appbundler-1.0ea.jar"
        classname="com.oracle.appbundler.AppBundlerTask"/>

      <bundleapp 
          classpathref="runclasspathref"
          outputdirectory="${dist}"
          name="${bundle.name}"
          displayname="${bundle.displayname}"
          executableName="MyApp"
          identifier="com.company.product"
          shortversion="${version.public}"
          version="${version.internal}"
          icon="${icons.path}/${bundle.icns}"
          mainclassname="Main"
          copyright="2012 Your Company"
          applicationCategory="public.app-category.finance">
          
          <runtime dir="${runtime}/Contents/Home"/>

          <arch name="x86_64"/>
          <arch name="i386"/>

          <bundledocument extensions="png,jpg"
            icon="${icons.path}/${image.icns}"
            name="Images"
            role="editor">
          </bundledocument> 

          <bundledocument extensions="pdf"
            icon="${icons.path}/${pdf.icns}"
            name="PDF files"
            role="viewer">
          </bundledocument>

          <bundledocument extensions="custom"
            icon="${icons.path}/${data.icns}"
            name="Custom data"
            role="editor"
            isPackage="true">
          </bundledocument>

          <!-- Workaround as com.apple.mrj.application.apple.menu.about.name property may no longer work -->
          <option value="-Xdock:name=${bundle.name}"/>

          <option value="-Dapple.laf.useScreenMenuBar=true"/>
          <option value="-Dcom.apple.macos.use-file-dialog-packages=true"/>
          <option value="-Dcom.apple.macos.useScreenMenuBar=true"/>
          <option value="-Dcom.apple.mrj.application.apple.menu.about.name=${bundle.name}"/>
          <option value="-Dcom.apple.smallTabs=true"/>
          <option value="-Dfile.encoding=UTF-8"/>

          <option value="-Xmx1024M" name="Xmx"/>
      </bundleapp>
    </target>

Example 2, use installed Java but require Java 8 (or later):

    <target name="bundle">
      <taskdef name="bundleapp" 
        classpath="appbundler-1.0ea.jar"
        classname="com.oracle.appbundler.AppBundlerTask"/>
      <bundleapp 
          jvmrequired="1.8"
          classpathref="runclasspathref"
          outputdirectory="${dist}"
          name="${bundle.name}"
          displayname="${bundle.displayname}"
          executableName="MyApp"
          identifier="com.company.product"
          shortversion="${version.public}"
          version="${version.internal}"
          icon="${icons.path}/${bundle.icns}"
          mainclassname="Main"
          copyright="2012 Your Company"
          applicationCategory="public.app-category.finance">
      </bundleapp>
    </target>

Example 2, use installed Java but require Java 8 (or later) JRE and not a JDK:

    <target name="bundle">
      <taskdef name="bundleapp" 
        classpath="appbundler-1.0ea.jar"
        classname="com.oracle.appbundler.AppBundlerTask"/>
      <bundleapp 
          jvmrequired="1.8"
          jrepreferred="true"
          classpathref="runclasspathref"
          outputdirectory="${dist}"
          name="${bundle.name}"
          displayname="${bundle.displayname}"
          executableName="MyApp"
          identifier="com.company.product"
          shortversion="${version.public}"
          version="${version.internal}"
          icon="${icons.path}/${bundle.icns}"
          mainclassname="Main"
          copyright="2012 Your Company"
          applicationCategory="public.app-category.finance">
      </bundleapp>
    </target>



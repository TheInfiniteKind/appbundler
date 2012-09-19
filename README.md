appbundler
=============

A fork of the Java Application Bundler https://svn.java.net/svn/appbundler~svn
with the following changes:

- The native binary is created as universal (32/64)
- Fixes icon not showing, linked to bug 
  http://bugs.sun.com/bugdatabase/view_bug.do?bug_id=7159381 
  in the JavaAppLauncher.
- Add classpathref support to bundleapp
- Add support for JVMArchs and LSArchitecturePriority keys
- Allow to specify a custom value for CFBundleVersion 
- Allow specifying registered file extensions using CFBundleDocumentTypes
- Pass to the Java application 5 environment variables with the paths of
  the OSX special folders and whether the application is running in the
  sandbox.

These are the environment variables passed:

- LibraryDirectory
- DocumentsDirectory
- CachesDirectory
- ApplicationSupportDirectory
- SandboxEnabled (the String "true" or "false")


Example:

    <target name="bundle">
      <taskdef name="bundleapp" 
        classpath="appbundler-1.0ea.jar"
        classname="com.oracle.appbundler.AppBundlerTask"/>

      <bundleapp 
          classpathref="runclasspathref"
          outputdirectory="${dist}"
          name="${bundle.name}"
          displayname="${bundle.displayname}"
          identifier="com.company.product"
          shortversion="${version.public}"
          version="${version.internal}"
          icon="${bundle.icon}"
          mainclassname="Main"
          copyright="2012 Your Company"
          applicationCategory="public.app-category.finance">
          
          <runtime dir="${runtime}/Contents/Home"/>

          <arch name="x86_64"/>
          <arch name="i386"/>

          <bundledocument extensions="png,jpg"
            icon="${bundle.icon}"
            name="Images"
            role="editor">
          </bundledocument> 

          <bundledocument extensions="pdf"
            icon="${bundle.icon}"
            name="PDF files"
            role="viewer">
          </bundledocument>

          <bundledocument extensions="custom"
            icon="${bundle.icon}"
            name="Custom data"
            role="editor"
            isPackage="true">
          </bundledocument>

          <!-- Workaround since the icon parameter for bundleapp doesn't work -->
          <option value="-Xdock:icon=Contents/Resources/${bundle.icon}"/>

          <option value="-Dapple.laf.useScreenMenuBar=true"/>
          <option value="-Dcom.apple.macos.use-file-dialog-packages=true"/>
          <option value="-Dcom.apple.macos.useScreenMenuBar=true"/>
          <option value="-Dcom.apple.mrj.application.apple.menu.about.name=${bundle.name}"/>
          <option value="-Dcom.apple.smallTabs=true"/>
          <option value="-Dfile.encoding=UTF-8"/>

          <option value="-Xmx1024M"/>
      </bundleapp>
    </target>

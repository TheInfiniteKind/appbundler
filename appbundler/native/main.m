/*
 * Copyright 2012, Oracle and/or its affiliates. All rights reserved.
 *
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the "Classpath" exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */

#import <Cocoa/Cocoa.h>
#include <dlfcn.h>
#include <jni.h>

#define JAVA_LAUNCH_ERROR "JavaLaunchError"

#define JVM_RUNTIME_KEY "JVMRuntime"
#define WORKING_DIR "WorkingDirectory"
#define JVM_MAIN_CLASS_NAME_KEY "JVMMainClassName"
#define JVM_OPTIONS_KEY "JVMOptions"
#define JVM_DEFAULT_OPTIONS_KEY "JVMDefaultOptions"
#define JVM_ARGUMENTS_KEY "JVMArguments"

#define JVM_RUN_PRIVILEGED "JVMRunPrivileged"
#define JVM_RUN_JNLP "JVMJNLPLauncher"
#define JVM_RUN_JAR "JVMJARLauncher"

#define UNSPECIFIED_ERROR "An unknown error occurred."

#define APP_ROOT_PREFIX "$APP_ROOT"

#define JAVA_RUNTIME  "/Library/Internet Plug-Ins/JavaAppletPlugin.plugin/Contents/Home"
#define LIBJLI_DY_LIB "lib/jli/libjli.dylib"
#define DEPLOY_LIB    "lib/deploy.jar"

typedef int (JNICALL *JLI_Launch_t)(int argc, char ** argv,
                                    int jargc, const char** jargv,
                                    int appclassc, const char** appclassv,
                                    const char* fullversion,
                                    const char* dotversion,
                                    const char* pname,
                                    const char* lname,
                                    jboolean javaargs,
                                    jboolean cpwildcard,
                                    jboolean javaw,
                                    jint ergo);

int launch(int inputArgc, char *intputArgv[]);
const char * tmpFile();
NSString * findDylib ( );

int main(int argc, char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    int result;
    @try {
        launch(argc, argv);
        result = 0;
    } @catch (NSException *exception) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setAlertStyle:NSCriticalAlertStyle];
        [alert setMessageText:[exception reason]];
        [alert runModal];

        result = 1;
    }

    [pool drain];

    return result;
}

int launch(int inputArgc, char *intputArgv[]) {

    char *commandName = intputArgv[0];
    
    const char *const_jargs = NULL;
    const char *const_appclasspath = NULL;
    
    // Get the main bundle
    NSBundle *mainBundle = [NSBundle mainBundle];

    // Get the main bundle's info dictionary
    NSDictionary *infoDictionary = [mainBundle infoDictionary];
    
    // Set the working directory based on config, defaulting to the user's home directory
    NSString *workingDir = [infoDictionary objectForKey:@WORKING_DIR];
    if (workingDir != nil) {
        workingDir = [workingDir stringByReplacingOccurrencesOfString:@APP_ROOT_PREFIX withString:[mainBundle bundlePath]];
    } else {
        workingDir = NSHomeDirectory();
    }
    
    chdir([workingDir UTF8String]);
           
    // execute privileged
    NSString *privileged = [infoDictionary objectForKey:@JVM_RUN_PRIVILEGED];
    if ( privileged != nil && getuid() != 0 ) {
        NSDictionary *error = [NSDictionary new];
        
        // int i;
        // NSMutableString *parameters = [NSMutableString stringWithFormat:@""];
        // for(i=0;i<inputArgc;i++) {
        //    [parameters appendFormat:@"%@ ", [NSString stringWithCString:intputArgv[i] encoding:NSASCIIStringEncoding]];
        // }

        // NSString *script =  [NSString stringWithFormat:@"do shell script \"\\\"%@\\\"\" with administrator privileges", parameters];
        
        NSString *script =  [NSString stringWithFormat:@"do shell script \"\\\"%@\\\" > /dev/null 2>&1 &\" with administrator privileges", [NSString stringWithCString:commandName encoding:NSASCIIStringEncoding]];
        
        // NSLog(@"script: %@", script);
        NSAppleScript *appleScript = [[NSAppleScript new] initWithSource:script];
        if ([appleScript executeAndReturnError:&error]) {
            // This means we successfully elevated the application and can stop in here.
            return 0;
        }
    }
    
    // Locate the JLI_Launch() function
    NSString *runtime = [infoDictionary objectForKey:@JVM_RUNTIME_KEY];

    const char *libjliPath = NULL;
    if (runtime != nil) {
        runtime = [[[[NSBundle mainBundle] builtInPlugInsPath] stringByAppendingPathComponent:runtime] stringByAppendingPathComponent:@"Contents/Home/jre"];
    }
    else
    {
        runtime = findDylib ( );
    }

    libjliPath = [[runtime stringByAppendingPathComponent:@LIBJLI_DY_LIB] fileSystemRepresentation];
    const_appclasspath = [[runtime stringByAppendingPathComponent:@DEPLOY_LIB] fileSystemRepresentation];
    
    // NSLog(@"Launchpath: %s", libjliPath);

    void *libJLI = dlopen(libjliPath, RTLD_LAZY);

    JLI_Launch_t jli_LaunchFxnPtr = NULL;
    if (libJLI != NULL) {
        jli_LaunchFxnPtr = dlsym(libJLI, "JLI_Launch");
    }

    if (jli_LaunchFxnPtr == NULL) {
        [[NSException exceptionWithName:@JAVA_LAUNCH_ERROR
            reason:NSLocalizedString(@"JRELoadError", @UNSPECIFIED_ERROR)
            userInfo:nil] raise];
    }

    NSFileManager *defaultFileManager = [NSFileManager defaultManager];
    NSString *mainBundlePath = [mainBundle bundlePath];
    
    // make sure the bundle path does not contain a colon, as that messes up the java.class.path,
    // because colons are used a path separators and cannot be escaped.
    
    // funny enough, Finder does not let you create folder with colons in their names,
    // but when you create a folder with a slash, e.g. "audio/video", it is accepted
    // and turned into... you guessed it, a colon:
    // "audio:video"
    if ([mainBundlePath rangeOfString:@":"].location != NSNotFound) {
        [[NSException exceptionWithName:@JAVA_LAUNCH_ERROR
                                 reason:NSLocalizedString(@"BundlePathContainsColon", @UNSPECIFIED_ERROR)
                               userInfo:nil] raise];
    }

    // Set the class path
    NSString *javaPath = [mainBundlePath stringByAppendingString:@"/Contents/Java"];

    // Get the VM options
    NSMutableArray *options = [[infoDictionary objectForKey:@JVM_OPTIONS_KEY] mutableCopy];
    if (options == nil) {
        options = [NSMutableArray array];
    }
    
    // Get the application arguments
    NSMutableArray *arguments = [[infoDictionary objectForKey:@JVM_ARGUMENTS_KEY] mutableCopy];
    if (arguments == nil) {
        arguments = [NSMutableArray array];
    }
    
    // modifyable classPath
    NSMutableString *classPath = [NSMutableString stringWithFormat:@"-Djava.class.path=%@/Classes", javaPath];

    // Set the library path
    NSString *libraryPath = [NSString stringWithFormat:@"-Djava.library.path=%@/Contents/MacOS", mainBundlePath];
    
    // Check for a defined JAR File below the Contents/Java folder
    // If set, use this instead of a classpath setting
    NSString *jarlauncher = [infoDictionary objectForKey:@JVM_RUN_JAR];

    // check for jnlp launcher name
    // This basically circumvents the security problems introduced with 10.8.4 that JNLP Files must be signed to execute them without CTRL+CLick -> Open
    // See: How to sign (dynamic) JNLP files for OSX 10.8.4 and Gatekeeper http://stackoverflow.com/questions/16958130/how-to-sign-dynamic-jnlp-files-for-osx-10-8-4-and-gatekeeper
    // There is no solution to properly sign a dynamic jnlp file to date. Both Apple and Oracle have open rdars/tickets on this.
    // The following mechanism encapsulates a JNLP file/template. It makes a temporary copy when executing. This ensures that the JNLP file can be updates from the server at runtime.
    // YES, this may insert additional security threats, but it is still the only way to avoid permission problems.
    // It is highly recommended that the resulting .app container is being signed with a certificate from Apple - otherwise you will not need this mechanism.
    NSString *jnlplauncher = [infoDictionary objectForKey:@JVM_RUN_JNLP];
    // Get the main class name
    NSString *mainClassName = [infoDictionary objectForKey:@JVM_MAIN_CLASS_NAME_KEY];

    if ( jnlplauncher != nil ) {

        // JNLP Launcher found, need to modify quite a bit now
        [options addObject:@"-classpath"];
        [options addObject:[NSString stringWithFormat:@"%s", const_appclasspath]];
        
        classPath = nil;

        // Main Class is javaws
        mainClassName=@"com.sun.javaws.Main";
        
        // Optional stuff that javaws would do as well
        [options addObject:@"-Dsun.awt.warmup=true"];
        [options addObject:@"-Xverify:remote"];
        [options addObject:@"-Djnlpx.remove=true"];
        [options addObject:@"-DtrustProxy=true"];
        
        [options addObject:[NSString stringWithFormat:@"-Djava.security.policy=file:%@/lib/security/javaws.policy", runtime]];
        [options addObject:[NSString stringWithFormat:@"-Xbootclasspath/a:%@/lib/javaws.jar:%@/lib/deploy.jar:%@/lib/plugin.jar", runtime, runtime, runtime]];

        // Argument that javaws does also
        [arguments addObject:@"-noWebStart"];
        
        // Copy the jnlp to a temporary location
        NSError *copyerror = nil;
        NSString *tempFileName = [NSString stringWithCString:tmpFile() encoding:NSASCIIStringEncoding];
        // File now exists.
        [defaultFileManager removeItemAtPath:tempFileName error:NULL];
        
        // Check if this is absolute or relative (else)
        NSString *jnlpPath = [mainBundlePath stringByAppendingPathComponent:jnlplauncher];
        if ( ![defaultFileManager fileExistsAtPath:jnlpPath] ) {
            jnlpPath = [javaPath stringByAppendingPathComponent:jnlplauncher];
        }
        
        [defaultFileManager copyItemAtURL:[NSURL fileURLWithPath:jnlpPath] toURL:[NSURL fileURLWithPath:tempFileName] error:&copyerror];
        if ( copyerror != nil ) {
            NSLog(@"Error: %@", copyerror);
            [[NSException exceptionWithName:@"Error while copying JNLP File"
                                     reason:@"File copy error"
                                   userInfo:copyerror.userInfo] raise];
        }
        
        // Add the jnlp as argument so that javaws.Main can read and delete it
        [arguments addObject:tempFileName];
        
    } else
    if ( mainClassName == nil && jarlauncher == nil ) {
        [[NSException exceptionWithName:@JAVA_LAUNCH_ERROR
            reason:NSLocalizedString(@"MainClassNameRequired", @UNSPECIFIED_ERROR)
            userInfo:nil] raise];
    }

    // If a jar file is defined as launcher, disacard the javaPath
    if ( jarlauncher != nil ) {
        [classPath appendFormat:@":%@/%@", javaPath, jarlauncher];
    } else {
        // add all jar files.
        NSArray *javaDirectoryContents = [defaultFileManager contentsOfDirectoryAtPath:javaPath error:nil];
        if (javaDirectoryContents == nil) {
            [[NSException exceptionWithName:@JAVA_LAUNCH_ERROR
                                     reason:NSLocalizedString(@"JavaDirectoryNotFound", @UNSPECIFIED_ERROR)
                                   userInfo:nil] raise];
        }
        
        for (NSString *file in javaDirectoryContents) {
            if ([file hasSuffix:@".jar"]) {
                [classPath appendFormat:@":%@/%@", javaPath, file];
            }
        }
    }
    
    // Get the VM default options
    NSArray *defaultOptions = [NSArray array];
    NSDictionary *defaultOptionsDict = [infoDictionary objectForKey:@JVM_DEFAULT_OPTIONS_KEY];
    if (defaultOptionsDict != nil) {
        NSMutableDictionary *defaults = [NSMutableDictionary dictionaryWithDictionary: defaultOptionsDict];
        // Replace default options with user specific options, if available
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        // Create special key that should be used by Java's java.util.Preferences impl
        // Requires us to use "/" + bundleIdentifier.replace('.', '/') + "/JVMOptions/" as node on the Java side
        // Beware: bundleIdentifiers shorter than 3 segments are placed in a different file!
        // See java/util/prefs/MacOSXPreferences.java of OpenJDK for details
        NSString *bundleDictionaryKey = [mainBundle bundleIdentifier];
        bundleDictionaryKey = [bundleDictionaryKey stringByReplacingOccurrencesOfString:@"." withString:@"/"];
        bundleDictionaryKey = [NSString stringWithFormat: @"/%@/", bundleDictionaryKey];

        NSDictionary *bundleDictionary = [userDefaults dictionaryForKey: bundleDictionaryKey];
        if (bundleDictionary != nil) {
            NSDictionary *jvmOptionsDictionary = [bundleDictionary objectForKey: @"JVMOptions/"];
            for (NSString *key in jvmOptionsDictionary) {
                NSString *value = [jvmOptionsDictionary objectForKey:key];
                [defaults setObject: value forKey: key];
            }
        }
        defaultOptions = [defaults allValues];
    }

    // Set OSX special folders
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,   
            NSUserDomainMask, YES);                                            
    NSString *basePath = [paths objectAtIndex:0];                                                                           
    NSString *libraryDirectory = [NSString stringWithFormat:@"-DLibraryDirectory=%@", basePath];
    NSString *containersDirectory = [basePath stringByAppendingPathComponent:@"Containers"];
    NSString *sandboxEnabled = @"false";
    BOOL isDir;
    NSFileManager *fm = [[NSFileManager alloc] init];
    BOOL containersDirExists = [fm fileExistsAtPath:containersDirectory isDirectory:&isDir];
    if (containersDirExists && isDir) {
        sandboxEnabled = @"true";
    }
    NSString *sandboxEnabledVar = [NSString stringWithFormat:@"-DSandboxEnabled=%@", sandboxEnabled];
    
    paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,           
            NSUserDomainMask, YES);                                            
    basePath = [paths objectAtIndex:0];                                                                           
    NSString *documentsDirectory = [NSString stringWithFormat:@"-DDocumentsDirectory=%@", basePath];
                                                                               
    paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, 
            NSUserDomainMask, YES);                                            
    basePath = [paths objectAtIndex:0];                                                                           
    NSString *applicationSupportDirectory = [NSString stringWithFormat:@"-DApplicationSupportDirectory=%@", basePath];
                                                                               
    paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, 
            NSUserDomainMask, YES);                                            
    basePath = [paths objectAtIndex:0];                                                                           
    NSString *cachesDirectory = [NSString stringWithFormat:@"-DCachesDirectory=%@", basePath];

    // Initialize the arguments to JLI_Launch()
    // +5 due to the special directories and the sandbox enabled property
    int argc = 1 + [options count] + [defaultOptions count] + 2 + [arguments count] + 1 + 4 + (classPath != nil?1:0);
    char *argv[argc];

    int i = 0;
    argv[i++] = commandName;
    
    if ( classPath != nil ) {
        argv[i++] = strdup([classPath UTF8String]);
    }

    argv[i++] = strdup([libraryPath UTF8String]);
    argv[i++] = strdup([libraryDirectory UTF8String]);
    argv[i++] = strdup([documentsDirectory UTF8String]);
    argv[i++] = strdup([applicationSupportDirectory UTF8String]);
    argv[i++] = strdup([cachesDirectory UTF8String]);
    argv[i++] = strdup([sandboxEnabledVar UTF8String]);

    for (NSString *option in options) {
        option = [option stringByReplacingOccurrencesOfString:@APP_ROOT_PREFIX withString:[mainBundle bundlePath]];
        argv[i++] = strdup([option UTF8String]);
        // NSLog(@"Option: %@",option);
    }

    for (NSString *defaultOption in defaultOptions) {
        defaultOption = [defaultOption stringByReplacingOccurrencesOfString:@APP_ROOT_PREFIX withString:[mainBundle bundlePath]];
        argv[i++] = strdup([defaultOption UTF8String]);
        // NSLog(@"DefaultOption: %@",defaultOption);
    }

    argv[i++] = strdup([mainClassName UTF8String]);

    for (NSString *argument in arguments) {
        argument = [argument stringByReplacingOccurrencesOfString:@APP_ROOT_PREFIX withString:[mainBundle bundlePath]];
        argv[i++] = strdup([argument UTF8String]);
    }
    
    for (int ii=0; ii<argc; ii++) {
        NSLog(@"Starting java with options: '%s'", argv[ii]);
    }

    // Invoke JLI_Launch()
    return jli_LaunchFxnPtr(argc, argv,
                            sizeof(&const_jargs) / sizeof(char *), &const_jargs,
                            sizeof(&const_appclasspath) / sizeof(char *), &const_appclasspath,
                            "",
                            "",
                            "java",
                            "java",
                            (const_jargs != NULL) ? JNI_TRUE : JNI_FALSE,
                            FALSE,
                            FALSE,
                            0);
}

/*
 * Convenient Method to create a temporary JNLP file(name)
 * This file will be deleted by the JLI_Launch when the program ends.
 */
const char * tmpFile() {
    NSString *tempFileTemplate = [NSTemporaryDirectory()
                                  stringByAppendingPathComponent:@"jnlpFile.XXXXXX.jnlp"];
    
    const char *tempFileTemplateCString = [tempFileTemplate fileSystemRepresentation];
    
    char *tempFileNameCString = (char *)malloc(strlen(tempFileTemplateCString) + 1);
    strcpy(tempFileNameCString, tempFileTemplateCString);
    int fileDescriptor = mkstemps(tempFileNameCString, 5);
    
    // no need to keep it open
    close(fileDescriptor);
    
    if (fileDescriptor == -1) {
        NSLog(@"Error while creating tmp file");
        return nil;
    }
    
    NSString *tempFileName = [[NSFileManager defaultManager]
                              stringWithFileSystemRepresentation:tempFileNameCString
                              length:strlen(tempFileNameCString)];
    
    free(tempFileNameCString);
    
    return [tempFileName fileSystemRepresentation];
}

/**
 *  Searches for a JRE 1.7 or 1.8 dylib.
 *  First checks the "usual" JRE location, and failing that looks for a JDK.
 */
NSString * findDylib ( )
{
    NSLog (@"Searching for a JRE.");

//  Try the "java -version" command and see if we get a 1.7 or 1.8 response (note 
//  that for unknown but ancient reasons, the result is output to stderr). If we
//  do then return address for dylib that should be in the JRE package.
    @try
    {
        NSTask *task = [[NSTask alloc] init];
        [task setLaunchPath:[@JAVA_RUNTIME stringByAppendingPathComponent:@"bin/java"]];
        
        NSArray *args = [NSArray arrayWithObjects: @"-version", nil];
        [task setArguments:args];
        
        NSPipe *stdout = [NSPipe pipe];
        [task setStandardOutput:stdout];
        
        NSPipe *stderr = [NSPipe pipe];
        [task setStandardError:stderr];
        
        [task setStandardInput:[NSPipe pipe]];
        
        NSFileHandle *outHandle = [stdout fileHandleForReading];
        NSFileHandle *errHandle = [stderr fileHandleForReading];
        
        [task launch];
        [task waitUntilExit];
        [task release];
        
        NSData *data1 = [outHandle readDataToEndOfFile];
        NSData *data2 = [errHandle readDataToEndOfFile];
        
        NSString *outRead = [[NSString alloc] initWithData:data1
                                                  encoding:NSUTF8StringEncoding];
        NSString *errRead = [[NSString alloc] initWithData:data2
                                                  encoding:NSUTF8StringEncoding];
    
        if ( errRead != nil)
        {
            if ( [errRead rangeOfString:@"java version \"1.7."].location != NSNotFound
                || [errRead rangeOfString:@"java version \"1.8."].location != NSNotFound)
            {
                return @JAVA_RUNTIME;
            }
        }
    }
    @catch (NSException *exception)
    {
        NSLog (@"JRE search exception: '%@'", [exception reason]);
    }

    NSLog (@"Could not find a JRE. Will look for a JDK.");

//  Having failed to find a JRE in the usual location, see if a JDK is installed
//  (probably in /Library/Java/JavaVirtualMachines). If so, return address of
//  dylib in the JRE within the JDK.
    @try
    {
        NSTask *task = [[NSTask alloc] init];
        [task setLaunchPath:@"/usr/libexec/java_home"];

        NSArray *args = [NSArray arrayWithObjects: @"-v", @"1.7+", nil];
        [task setArguments:args];

        NSPipe *stdout = [NSPipe pipe];
        [task setStandardOutput:stdout];

        NSPipe *stderr = [NSPipe pipe];
        [task setStandardError:stderr];

        [task setStandardInput:[NSPipe pipe]];

        NSFileHandle *outHandle = [stdout fileHandleForReading];
        NSFileHandle *errHandle = [stderr fileHandleForReading];

        [task launch];
        [task waitUntilExit];
        [task release];

        NSData *data1 = [outHandle readDataToEndOfFile];
        NSData *data2 = [errHandle readDataToEndOfFile];

        NSString *outRead = [[NSString alloc] initWithData:data1
                                                    encoding:NSUTF8StringEncoding];
        NSString *errRead = [[NSString alloc] initWithData:data2
                                                    encoding:NSUTF8StringEncoding];

        if ( errRead != nil
                && [errRead rangeOfString:@"Unable"].location != NSNotFound )
        {
            NSLog (@"No JDK 1.7 or later found.");
            return nil;
        }

        if ( [outRead rangeOfString:@"jdk1.7"].location != NSNotFound
            || [outRead rangeOfString:@"jdk1.8"].location != NSNotFound)
        {
            return [[outRead stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                                    stringByAppendingPathComponent:@"jre"];
        }
    }
    @catch (NSException *exception)
    {
        NSLog (@"JDK search exception: '%@'", [exception reason]);
    }

    return nil;
}

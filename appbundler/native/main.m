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
#define JVM_ARGUMENTS_KEY "JVMArguments"

#define JVM_RUN_PRIVILEGED "JVMRunPrivileged"
#define JVM_RUN_JNLP "JVMJNLPLauncher"

#define UNSPECIFIED_ERROR "An unknown error occurred."

#define APP_ROOT_PREFIX "$APP_ROOT"

#define JAVA_RUNTIME "/Library/Internet Plug-Ins/JavaAppletPlugin.plugin/Contents/Home";
#define LIBJLI_DY_LIB "lib/jli/libjli.dylib"
#define DEPLOY_LIB "lib/deploy.jar"

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
        
        int i;
        NSMutableString *parameters = [NSMutableString stringWithFormat:@""];
        for(i=0;i<inputArgc;i++) {
            [parameters appendFormat:@"%@ ", [NSString stringWithCString:intputArgv[i] encoding:NSASCIIStringEncoding]];
        }

        NSString *script =  [NSString stringWithFormat:@"do shell script \"\\\"%@\\\"\" with administrator privileges", parameters];
        
        script =  [NSString stringWithFormat:@"do shell script \"\\\"%@\\\" > /dev/null 2>&1 &\" with administrator privileges", [NSString stringWithCString:commandName encoding:NSASCIIStringEncoding]];
        
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
        runtime = [[[[NSBundle mainBundle] builtInPlugInsPath] stringByAppendingPathComponent:runtime] stringByAppendingPathComponent:@"jre"];
    } else {
        runtime = @JAVA_RUNTIME;
    }

    libjliPath = [[runtime stringByAppendingPathComponent:@LIBJLI_DY_LIB] fileSystemRepresentation];
    const_appclasspath = [[runtime stringByAppendingPathComponent:@DEPLOY_LIB] fileSystemRepresentation];

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

    // Set the class path
    NSString *mainBundlePath = [mainBundle bundlePath];
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
    

    // check for jnlp launcher name
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
        [defaultFileManager copyItemAtURL:[NSURL fileURLWithPath:[javaPath stringByAppendingPathComponent:jnlplauncher]] toURL:[NSURL fileURLWithPath:tempFileName] error:&copyerror];
        if ( copyerror != nil ) {
            NSLog(@"Error: %@", copyerror);
            [[NSException exceptionWithName:@"Error while copying JNLP File"
                                     reason:@"File copy error"
                                   userInfo:copyerror.userInfo] raise];
        }
        
        // Add the jnlp as argument so that javaws.Main can read and delete it
        [arguments addObject:tempFileName];
        
    } else
    if (mainClassName == nil) {
        [[NSException exceptionWithName:@JAVA_LAUNCH_ERROR
            reason:NSLocalizedString(@"MainClassNameRequired", @UNSPECIFIED_ERROR)
            userInfo:nil] raise];
    }

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
    int argc = 1 + [options count] + 2 + [arguments count] + 1 + 4 + (classPath != nil?1:0);
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
    }

    argv[i++] = strdup([mainClassName UTF8String]);

    for (NSString *argument in arguments) {
        argument = [argument stringByReplacingOccurrencesOfString:@APP_ROOT_PREFIX withString:[mainBundle bundlePath]];
        argv[i++] = strdup([argument UTF8String]);
    }
    
    //for (int i; i < argc; i++)
    //    NSLog(@"%s", argv[i]);
    
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
 * Convenient Method to create a temporary file - this will be deleted by the JLI_Launch
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

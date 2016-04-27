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
#define JVM_CLASSPATH_KEY "JVMClassPath"
#define JVM_VERSION_KEY "JVMVersion"
#define JRE_PREFERRED_KEY "JREPreferred"
#define JDK_PREFERRED_KEY "JDKPreferred"
#define JVM_DEBUG_KEY "JVMDebug"
#define IGNORE_PSN_KEY "IgnorePSN"

#define JVM_RUN_PRIVILEGED "JVMRunPrivileged"


#define UNSPECIFIED_ERROR "An unknown error occurred."

#define APP_ROOT_PREFIX "$APP_ROOT"
#define JVM_RUNTIME "$JVM_RUNTIME"

#define JRE_JAVA "/Library/Internet Plug-Ins/JavaAppletPlugin.plugin/Contents/Home/bin/java"
#define JRE_DYLIB "/Library/Internet Plug-Ins/JavaAppletPlugin.plugin/Contents/Home/lib/jli/libjli.dylib"

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

static char** progargv = NULL;
static int progargc = 0;
static int launchCount = 0;

int launch(char *, int, char **);
NSString * findJavaDylib (NSString *, bool, bool, bool);
NSString * findJREDylib (int, bool);
NSString * findJDKDylib (int, bool);
int extractMajorVersion (NSString *);
NSString * convertRelativeFilePath(NSString *);

int main(int argc, char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    int result;
    @try {
    	if ((argc > 1) && (launchCount == 0)) {
    		progargc = argc - 1;
    		progargv = &argv[1];
    	}

        launch(argv[0], progargc, progargv);
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

int launch(char *commandName, int progargc, char *progargv[]) {
    // Get the main bundle
    NSBundle *mainBundle = [NSBundle mainBundle];

    // Get the main bundle's info dictionary
    NSDictionary *infoDictionary = [mainBundle infoDictionary];
    
    // Test for debugging (but only on the second runthrough)
    bool isDebugging = (launchCount > 0) && [[infoDictionary objectForKey:@JVM_DEBUG_KEY] boolValue];
    
    if (isDebugging) {
        NSLog(@"Loading Application '%@'", [infoDictionary objectForKey:@"CFBundleName"]);
    }
    
    // Set the working directory based on config, defaulting to the user's home directory
    NSString *workingDir = [infoDictionary objectForKey:@WORKING_DIR];
    if (workingDir != nil) {
        workingDir = [workingDir stringByReplacingOccurrencesOfString:@APP_ROOT_PREFIX withString:[mainBundle bundlePath]];
    } else {
        workingDir = [[NSFileManager defaultManager] currentDirectoryPath];
    }
    if (isDebugging) {
    	NSLog(@"Working Directory: '%@'", convertRelativeFilePath(workingDir));
    }
    
    chdir([workingDir UTF8String]);
           
    // execute privileged
    NSString *privileged = [infoDictionary objectForKey:@JVM_RUN_PRIVILEGED];
    if ( privileged != nil && getuid() != 0 ) {
        NSDictionary *error = [NSDictionary new];
        NSString *script =  [NSString stringWithFormat:@"do shell script \"\\\"%@\\\" > /dev/null 2>&1 &\" with administrator privileges", [NSString stringWithCString:commandName encoding:NSASCIIStringEncoding]];
        NSAppleScript *appleScript = [[NSAppleScript new] initWithSource:script];
        if ([appleScript executeAndReturnError:&error]) {
            // This means we successfully elevated the application and can stop in here.
            return 0;
        }
    }
    
    // Locate the JLI_Launch() function
    NSString *runtime = [infoDictionary objectForKey:@JVM_RUNTIME_KEY];
    NSString *runtimePath = [[mainBundle builtInPlugInsPath] stringByAppendingPathComponent:runtime];

    NSString *jvmRequired = [infoDictionary objectForKey:@JVM_VERSION_KEY];
    bool jrePreferred = [[infoDictionary objectForKey:@JRE_PREFERRED_KEY] boolValue];
    bool jdkPreferred = [[infoDictionary objectForKey:@JDK_PREFERRED_KEY] boolValue];

    if (jrePreferred && jdkPreferred) {
        NSLog(@"Specifying both JRE- and JDK-preferred means neither is preferred");
        jrePreferred = false;
        jdkPreferred = false;
    }

    NSString *javaDylib;

    if (runtime != nil) {
        NSString *dylibRelPath = [runtime hasSuffix:@".jre"] || [runtime hasSuffix:@".jdk"]
                    ? @"Contents/Home/jre/lib/jli/libjli.dylib"
                    : @"Contents/Home/lib/jli/libjli.dylib";
        javaDylib = [runtimePath stringByAppendingPathComponent:dylibRelPath];

        if (isDebugging) {
            NSLog(@"Java Runtime Path (relative): '%@'", runtimePath);
        }
    }
    else {
        javaDylib = findJavaDylib (jvmRequired, jrePreferred, jdkPreferred, isDebugging);

        if (isDebugging) {
            NSLog(@"Java Runtime Dylib Path: '%@'", convertRelativeFilePath(javaDylib));
        }
    }

    const char *libjliPath = NULL;
    if (javaDylib != nil)
    {
        libjliPath = [javaDylib fileSystemRepresentation];
    }

    void *libJLI = dlopen(libjliPath, RTLD_LAZY);

    JLI_Launch_t jli_LaunchFxnPtr = NULL;
    if (libJLI != NULL) {
        jli_LaunchFxnPtr = dlsym(libJLI, "JLI_Launch");
    }

    if (jli_LaunchFxnPtr == NULL) {
        NSString *msg;

        if (runtime == nil && jvmRequired != nil) {
            int required = extractMajorVersion (jvmRequired);
            
            if (required < 7) { required = 7; }

            if (jdkPreferred) {
                NSString *msga = NSLocalizedString(@"JDKxLoadFullError", @UNSPECIFIED_ERROR);
                msg = [NSString stringWithFormat:msga, required];
            }
            else {
                NSString *msga = NSLocalizedString(@"JRExLoadFullError", @UNSPECIFIED_ERROR);
                msg = [NSString stringWithFormat:msga, required];
            }
        }
        else {
            msg = NSLocalizedString(@"JRELoadError", @UNSPECIFIED_ERROR);
        }

        [[NSException exceptionWithName:@JAVA_LAUNCH_ERROR
                reason:msg userInfo:nil] raise];
    }

    // Get the main class name
    NSString *mainClassName = [infoDictionary objectForKey:@JVM_MAIN_CLASS_NAME_KEY];
    if (mainClassName == nil) {
        [[NSException exceptionWithName:@JAVA_LAUNCH_ERROR
            reason:NSLocalizedString(@"MainClassNameRequired", @UNSPECIFIED_ERROR)
            userInfo:nil] raise];
    }

    // Set the class path
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

    NSString *javaPath = [mainBundlePath stringByAppendingString:@"/Contents/Java"];
    NSMutableString *classPath = [NSMutableString stringWithString:@"-Djava.class.path="];

    NSArray *cp = [infoDictionary objectForKey:@JVM_CLASSPATH_KEY];
    if (cp == nil) {
        
        // Implicit classpath, so use the contents of the "Java" folder to build an explicit classpath
        
        [classPath appendFormat:@"%@/Classes", javaPath];
        NSFileManager *defaultFileManager = [NSFileManager defaultManager];
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
        
    } else {
        
        // Explicit ClassPath

        int k = 0;
        for (NSString *file in cp) {
            if (k++ > 0) [classPath appendString:@":"]; // add separator if needed
            file = [file stringByReplacingOccurrencesOfString:@APP_ROOT_PREFIX withString:[mainBundle bundlePath]];
            [classPath appendString:file];
        }
    }
    
    // Set the library path
    NSString *libraryPath = [NSString stringWithFormat:@"-Djava.library.path=%@/Contents/MacOS", mainBundlePath];

    // Get the VM options
    NSArray *options = [infoDictionary objectForKey:@JVM_OPTIONS_KEY];
    if (options == nil) {
        options = [NSArray array];
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

    // Get the application arguments
    NSArray *arguments = [infoDictionary objectForKey:@JVM_ARGUMENTS_KEY];
    if (arguments == nil) {
        arguments = [NSArray array];
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

    // Remove -psn argument
    int newProgargc = progargc;
    char *newProgargv[newProgargc];
    for (int i = 0; i < progargc; i++) {
        newProgargv[i] = progargv[i];
    }
    
    bool ignorePSN = [[infoDictionary objectForKey:@IGNORE_PSN_KEY] boolValue];
    if (ignorePSN) {
        NSString *psnRegexp = @"^-psn_\\d_\\d+$";
        NSPredicate *psnTest = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", psnRegexp];

        int shift = 0;
        int i = 0;
        while (i < newProgargc) {
            NSString *s = [NSString stringWithFormat:@"%s", newProgargv[i]];
            if ([psnTest evaluateWithObject: s]){
                shift++;
                newProgargc--;
            }
            newProgargv[i] = newProgargv[i+shift];
            i++;
        }
    }
    
    // replace $APP_ROOT in environment variables
    NSDictionary* environment = [[NSProcessInfo processInfo] environment];
    for (NSString* key in environment) {
        NSString* value = [environment objectForKey:key];
        NSString* newValue = [value stringByReplacingOccurrencesOfString:@APP_ROOT_PREFIX withString:[mainBundle bundlePath]];
        if (! [newValue isEqualToString:value]) {
            setenv([key UTF8String], [newValue UTF8String], 1);
        }
    }

    // Initialize the arguments to JLI_Launch()
    // +5 due to the special directories and the sandbox enabled property
    int argc = 1 + [options count] + [defaultOptions count] + 2 + [arguments count] + 1 + 5 + newProgargc;
    char *argv[argc];

    int i = 0;
    argv[i++] = commandName;
    argv[i++] = strdup([classPath UTF8String]);
    argv[i++] = strdup([libraryPath UTF8String]);
    argv[i++] = strdup([libraryDirectory UTF8String]);
    argv[i++] = strdup([documentsDirectory UTF8String]);
    argv[i++] = strdup([applicationSupportDirectory UTF8String]);
    argv[i++] = strdup([cachesDirectory UTF8String]);
    argv[i++] = strdup([sandboxEnabledVar UTF8String]);

    for (NSString *option in options) {
        option = [option stringByReplacingOccurrencesOfString:@APP_ROOT_PREFIX withString:[mainBundle bundlePath]];
        option = [option stringByReplacingOccurrencesOfString:@JVM_RUNTIME withString:runtimePath];
        argv[i++] = strdup([option UTF8String]);
    }

    for (NSString *defaultOption in defaultOptions) {
        defaultOption = [defaultOption stringByReplacingOccurrencesOfString:@APP_ROOT_PREFIX withString:[mainBundle bundlePath]];
        argv[i++] = strdup([defaultOption UTF8String]);
    }

    argv[i++] = strdup([mainClassName UTF8String]);

    for (NSString *argument in arguments) {
        argument = [argument stringByReplacingOccurrencesOfString:@APP_ROOT_PREFIX withString:[mainBundle bundlePath]];
        argv[i++] = strdup([argument UTF8String]);
    }

	int ctr = 0;
	for (ctr = 0; ctr < newProgargc; ctr++) {
		argv[i++] = newProgargv[ctr];
	}
    
    // Print the full command line for debugging purposes...
    if (isDebugging) {
        NSLog(@"Command line passed to application:");
        int j=0;
        for(j=0; j<i; j++) {
            NSLog(@"Arg %d: '%s'", j, argv[j]);
        }
    }

	launchCount++;

    // Invoke JLI_Launch()
    return jli_LaunchFxnPtr(argc, argv,
                            0, NULL,
                            0, NULL,
                            "",
                            "",
                            "java",
                            "java",
                            FALSE,
                            FALSE,
                            FALSE,
                            0);
}

/**
 *  Searches for a JRE or JDK dylib of the specified version or later.
 *  First checks the "usual" JRE location, and failing that looks for a JDK.
 *  The version required should be a string of form "1.X". If no version is
 *  specified or the version is pre-1.7, then a Java 1.7 is sought.
 */
NSString * findJavaDylib (
        NSString *jvmRequired,
        bool jrePreferred,
        bool jdkPreferred,
        bool isDebugging)
{
    int required = extractMajorVersion(jvmRequired);

    if (required < 7)
    {
        if (isDebugging) { NSLog (@"Required JVM must be at least ver. 7."); }
        required = 7;
    }

    if (isDebugging) {
        NSLog (@"Searching for a Java %d", required);
    }

    //  First, if a JRE is acceptible, try to find one with required Java version.
    //  If found, return address for dylib that should be in the JRE package.
    if (jdkPreferred) {
        if (isDebugging) {
            NSLog (@"A JDK is preferred; will not search for a JRE.");
        }
    }
    else {
        NSString * dylib = findJREDylib (required, isDebugging);

        if (dylib != nil) { return dylib; }

        if (isDebugging) { NSLog (@"No matching JRE found."); }
    }

    // If JRE not found or if JDK preferred, look for an acceptable JDK
    // (probably in /Library/Java/JavaVirtualMachines if so). If found,
    // return return address of dylib in the JRE within the JDK.
    if (jrePreferred) {
        if (isDebugging) {
            NSLog (@"A JRE is preferred; will not search for a JDK.");
        }
    }
    else {
        NSString * dylib = findJDKDylib (required, isDebugging);

        return dylib;

        if (isDebugging) { NSLog (@"No matching JDK found."); }
    }

    return nil;
}

/**
 *  Searches for a JRE dylib of the specified version or later.
 */
NSString * findJREDylib (
        int jvmRequired,
        bool isDebugging)
{
    // Try the "java -version" shell command and see if we get a response and
    // if so whether the version  is acceptable.
    // If found, return address for dylib that should be in the JRE package.
    // Note that for unknown but ancient reasons, the result is output to stderr
    // rather than to stdout.
    @try
    {
        NSTask *task = [[NSTask alloc] init];
        [task setLaunchPath:@JRE_JAVA];
        
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

    //  Found something in errRead. Parse it for a Java version string and
    //  try to extract a major version number.
        if (errRead != nil) {
            int version = 0;

            NSRange vrange = [errRead rangeOfString:@"java version \"1."];

            if (vrange.location != NSNotFound) {
                NSString *vstring = [errRead substringFromIndex:(vrange.location + 14)];

                vrange  = [vstring rangeOfString:@"\""];
                vstring = [vstring substringToIndex:vrange.location];

                version = extractMajorVersion(vstring);

                if (isDebugging) {
                    NSLog (@"Found a Java %@ JRE", vstring);
                    NSLog (@"Looks like major version %d", extractMajorVersion(vstring));
                }
            }

            if ( version >= jvmRequired ) {
                if (isDebugging) {
                    NSLog (@"JRE version qualifies");
                }
                return @JRE_DYLIB;
            }
        }
    }
    @catch (NSException *exception)
    {
        NSLog (@"JRE search exception: '%@'", [exception reason]);
    }

    return nil;
}

/**
 *  Searches for a JDK dylib of the specified version or later.
 */
NSString * findJDKDylib (
        int jvmRequired,
        bool isDebugging)
{
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

    //  If matching JDK not found, outRead will include something like
    //  "Unable to find any JVMs matching version "1.X"."
        if ( errRead != nil
                && [errRead rangeOfString:@"Unable"].location != NSNotFound )
        {
            if (isDebugging) {  NSLog (@"No matching JDK found."); }
            return nil;
        }

        int version = 0;

        NSRange vrange = [outRead rangeOfString:@"jdk1."];

        if (vrange.location != NSNotFound) {
            NSString *vstring = [outRead substringFromIndex:(vrange.location)];

            vrange  = [vstring rangeOfString:@"/"];
            vstring = [vstring substringToIndex:vrange.location];

            version = extractMajorVersion(vstring);

            if (isDebugging) {
                NSLog (@"Found a Java %@ JDK", vstring);
                NSLog (@"Looks like major version %d", extractMajorVersion(vstring));
            }
        }

        if ( version >= jvmRequired ) {
            if (isDebugging) {
                NSLog (@"JDK version qualifies");
            }
            return [[outRead stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                                    stringByAppendingPathComponent:@"/jre/lib/jli/libjli.dylib"];
        }
    }
    @catch (NSException *exception)
    {
        NSLog (@"JDK search exception: '%@'", [exception reason]);
    }

    return nil;
}

/**
 *  Extract the Java major version number from a string. We expect the input
 *  to look like either either "1.X", "1.X.Y_ZZ" or "jdk1.X.Y_ZZ", and the 
 *  returned result will be the integral value of X. Any failure to parse the
 *  string will return 0.
 */
int extractMajorVersion (NSString *vstring)
{
    if (vstring == nil) { return 0; }

//  Expecting either a java version of form 1.X, 1.X.Y_ZZ or jdk1.X.Y_ZZ.
//  Strip off everything from start of req string up to and including the "1."
    NSUInteger vstart = [vstring rangeOfString:@"1."].location;

    if (vstart == NSNotFound) { return 0; }

    vstring = [vstring substringFromIndex:(vstart+2)];

//  Now find the dot after the major version number, if present.
    NSUInteger vdot = [vstring rangeOfString:@"."].location;

//  No second dot, so return int of what we have.
    if (vdot == NSNotFound) {
        return [vstring intValue];
    }

//  Strip off everything beginning at that second dot.
    vstring = [vstring substringToIndex:vdot];

//  And convert what's left to an int.
    return [vstring intValue];
}

NSString * convertRelativeFilePath(NSString * path) {
    return [path stringByStandardizingPath];
}

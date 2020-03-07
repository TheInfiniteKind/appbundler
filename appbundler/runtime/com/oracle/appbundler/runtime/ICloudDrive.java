package com.oracle.appbundler.runtime;

public class ICloudDrive
{
	private static native String jni_getPath();

	public static String getPath() {
		return jni_getPath();
	}
}

package com.oracle.appbundler.runtime;

public class ICloudDrive
{
	private static native String jniGetPath();

	public static String getPath() {
		return jniGetPath();
	}
}

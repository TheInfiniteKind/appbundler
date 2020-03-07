import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.nio.file.NoSuchFileException;
import javax.swing.JFrame;
import javax.swing.JLabel;
import com.oracle.appbundler.runtime.ICloudDrive;

import java.lang.reflect.*;

public class TestICloudDrive {
	public static class ICloudDriveChecker implements Runnable {
	    @Override
	    public void run() {
			System.loadLibrary("ICloudDriveNative");

			while (true) {
		        try {
	            	Thread.sleep(1000);
		        } catch (InterruptedException e) {
					return;
		        }

				String path;
				try {
					path = ICloudDrive.getPath();
				} catch (java.lang.UnsatisfiedLinkError e) {
					e.printStackTrace();
					return;
				}

				if (path == null) {
					System.out.println("not logged in, or iCloud Drive is unavailable!");
				} else {
					System.out.println("iCloud Drive path: " + path);
				}
			}
	    }
	}

    public static void main(String[] args){
        Thread checker = new Thread(new ICloudDriveChecker(), "ICloudDriveChecker");
		checker.start();

	    JFrame frame = new JFrame("Test");
	    final JLabel label = new JLabel("You need to watch stdout!");
	    frame.getContentPane().add(label);
	    frame.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
	    frame.pack();
	    frame.setVisible(true);

        try {
			checker.join();
        } catch (InterruptedException e) {
			// do nothing.
        }
    }
}

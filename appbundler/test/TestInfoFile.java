import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.nio.file.NoSuchFileException;
import javax.swing.JFrame;
import javax.swing.JLabel;

public class TestInfoFile {
	public static String iCloudDriveInfoFilePath;

	public static class InfoFileChecker implements Runnable {
	    @Override
	    public void run() {
			while (true) {
		        try {
	            	Thread.sleep(1000);
		        } catch (InterruptedException e) {
					return;
		        }

				if (iCloudDriveInfoFilePath == null) {
					System.out.println("missing info file path!");
				} else {
					try {
						String path = new String(Files.readAllBytes(Paths.get(iCloudDriveInfoFilePath)));
						System.out.println("iCloud Drive path: " + path);
					} catch (NoSuchFileException e) {
						System.out.println(iCloudDriveInfoFilePath + " is missing.");
			        } catch (IOException e) {
			            e.printStackTrace();
					}
				}
			}
	    }
	}

    public static void main(String[] args){
		iCloudDriveInfoFilePath = System.getProperty("iCloudDriveInfoFile");
		System.out.println("iCloudDriveInfoFile: " + iCloudDriveInfoFilePath);

        Thread infoFileChecker = new Thread(new InfoFileChecker(), "infoFileChecker");
		infoFileChecker.start();

	    JFrame frame = new JFrame("Test");
	    final JLabel label = new JLabel("Info file path: " + iCloudDriveInfoFilePath);
	    frame.getContentPane().add(label);
	    frame.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
	    frame.pack();
	    frame.setVisible(true);

        try {
			infoFileChecker.join();
        } catch (InterruptedException e) {
			// do nothing.
        }
    }
}


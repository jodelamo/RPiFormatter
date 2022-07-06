import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var volumes: NSPopUpButton!
    @IBOutlet weak var selectedDiskImage: NSTextField!
    @IBOutlet weak var activityIndicator: NSProgressIndicator!

    // MARK: Application lifecycle

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        monitorVolumes()
        populateVolumes()
    }

    // MARK: Functions

    func monitorVolumes() {
        let workspace = NSWorkspace.shared

        // Notify when volumes change.
        workspace.notificationCenter.addObserver(self,
                                                 selector: #selector(volumesChanged(_:)),
                                                 name: NSWorkspace.didMountNotification,
                                                 object: nil)
        workspace.notificationCenter.addObserver(self,
                                                 selector: #selector(volumesChanged(_:)),
                                                 name: NSWorkspace.didUnmountNotification,
                                                 object: nil)
        workspace.notificationCenter.addObserver(self,
                                                 selector: #selector(volumesChanged(_:)),
                                                 name: NSWorkspace.didRenameVolumeNotification,
                                                 object: nil)
    }

    func populateVolumes() {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsRemovableKey, .volumeIsEjectableKey]
        let paths = FileManager().mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [])

        // Clear previous entries.
        volumes.removeAllItems()

        if let urls = paths {
            for url in urls {
                let components = url.pathComponents

                if components.count > 1 && components[1] == "Volumes" {
                    let image = NSWorkspace.shared.icon(forFile: url.path)
                    volumes.addItem(withTitle: url.path)
                    volumes.lastItem!.image = image
                }
            }
        }
    }

    @objc func volumesChanged(_ notification: Notification) {
        populateVolumes()
    }

    func disableControls() {
        for case let view in (self.window.contentView?.subviews)! {
            if view.responds(to: #selector(setter: NSCell.isEnabled)) {
                view.perform(#selector(setter: NSCell.isEnabled), with: nil)
            }
        }
    }

    func enableControls() {
        for case let view in (self.window.contentView?.subviews)! {
            if view.responds(to: #selector(setter: NSCell.isEnabled)) {
                view.perform(#selector(setter: NSCell.isEnabled), with: true)
            }
        }
    }

    @objc func receivedData(notification: Notification) {
        let fileHandle = notification.object as! FileHandle
        let data = fileHandle.availableData

        if data.count > 1 {
            // Re-register for notifications.
            fileHandle.waitForDataInBackgroundAndNotify()
            if let result = String(data: data, encoding: String.Encoding.utf8) {
                print(result)
            }
        }
    }

    func showAlert(_ message: String) {
        let alert = NSAlert()
        alert.informativeText = message
        alert.messageText = "Oops"
        alert.addButton(withTitle: "Close")
        alert.alertStyle = .critical
        alert.beginSheetModal(for: window, completionHandler: nil)
    }

    // MARK: Actions

    @IBAction func selectDiskImage(_ sender: AnyObject) {
        let fileDialog = NSOpenPanel()

        fileDialog.canChooseDirectories = false
        fileDialog.canCreateDirectories = false
        fileDialog.allowsMultipleSelection = false
        fileDialog.allowedFileTypes = ["img"]

        fileDialog.runModal()

        if let path = fileDialog.url?.path {
            selectedDiskImage.stringValue = path
        }
    }

    @IBAction func format(_ sender: AnyObject) {
        let diskImagePath = selectedDiskImage.stringValue

        guard let selectedVolume = volumes.titleOfSelectedItem,
            FileManager.default.fileExists(atPath: diskImagePath) else {
                showAlert("No volume selected.")
                return
        }

        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            showAlert("Failed to create disk arbitration session.")
            return
        }

        // Loop through mounted volumes to find the selected volume.
        let mountedVolumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [], options: [])!

        for volume in mountedVolumes {
            if selectedVolume == volume.path {
                guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, volume as CFURL) else {
                    return
                }

                guard let bsdName = String(validatingUTF8: DADiskGetBSDName(disk)!) else {
                    return
                }

                let task = Process()

                // Use `diskutil` to format the volume.
                task.launchPath = "/usr/sbin/diskutil"

                // When formatting to FAT32, the volume name needs to be in
                // uppercase.
                task.arguments = ["eraseVolume", "fat32", "BOOT", bsdName]

                // Pipe stdout through here.
                let outputPipe = Pipe()
                outputPipe.fileHandleForReading.waitForDataInBackgroundAndNotify()
                task.standardOutput = outputPipe

                // Pipe errors through here.
                let errorPipe = Pipe()
                errorPipe.fileHandleForReading.waitForDataInBackgroundAndNotify()
                task.standardError = errorPipe

                // Notify when data is available.
                NotificationCenter.default.addObserver(self,
                                                       selector: #selector(self.receivedData(notification:)),
                                                       name: NSNotification.Name.NSFileHandleDataAvailable,
                                                       object: nil)
                
                // Restore user interface when process is terminated.
                task.terminationHandler = { _ in
                    DispatchQueue.main.async(execute: {
                        self.activityIndicator.stopAnimation(nil)
                        self.enableControls()
                    })
                }
                
                // User interface preparations.
                activityIndicator.startAnimation(nil)
                disableControls()
                
                task.launch()
            }
        }
    }

    @IBAction func quit(_ sender: AnyObject) {
        NSApplication.shared.terminate(sender)
    }
}

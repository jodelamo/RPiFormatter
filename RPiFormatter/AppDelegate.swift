//
//  AppDelegate.swift
//  RPiFormatter
//
//  Created by Joacim Löwgren on 10/08/16.
//  Copyright © 2016 Joacim Löwgren. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var volumes: NSPopUpButton!
    @IBOutlet weak var selectedDiskImage: NSTextField!
    @IBOutlet weak var activityIndicator: NSProgressIndicator!

    // MARK: Application lifecycle

    func applicationDidFinishLaunching(aNotification: NSNotification) {
        monitorVolumes()
        populateVolumes()
    }

    // MARK: Functions

    func monitorVolumes() {
        let workspace = NSWorkspace.sharedWorkspace()

        // Notify when volumes change.
        workspace.notificationCenter.addObserver(self, selector: #selector(volumesChanged(_:)), name: NSWorkspaceDidMountNotification, object: nil)
        workspace.notificationCenter.addObserver(self, selector: #selector(volumesChanged(_:)), name: NSWorkspaceDidUnmountNotification, object: nil)
        workspace.notificationCenter.addObserver(self, selector: #selector(volumesChanged(_:)), name: NSWorkspaceDidRenameVolumeNotification, object: nil)
    }

    func populateVolumes() {
        let keys = [NSURLVolumeNameKey, NSURLVolumeIsRemovableKey, NSURLVolumeIsEjectableKey]
        let paths = NSFileManager().mountedVolumeURLsIncludingResourceValuesForKeys(keys, options: [])

        // Clear previous entries.
        volumes.removeAllItems()

        guard let urls = paths else {
            return
        }

        for url in urls {
            if let components = url.pathComponents where components.count > 1 && components[1] == "Volumes" {
                let image = NSWorkspace.sharedWorkspace().iconForFile(url.path!)
                volumes.addItemWithTitle(url.path!)
                volumes.lastItem!.image = image
            }
        }
    }

    func volumesChanged(notification: NSNotification) {
        populateVolumes()
    }

    func disableControls() {
        for case let view in (self.window.contentView?.subviews)! {
            if view.respondsToSelector(Selector("setEnabled:")) {
                view.performSelector(Selector("setEnabled:"), withObject: nil)
            }
        }
    }

    func enableControls() {
        for case let view in (self.window.contentView?.subviews)! {
            if view.respondsToSelector(Selector("setEnabled:")) {
                view.performSelector(Selector("setEnabled:"), withObject: true)
            }
        }
    }

    func receivedData(notification: NSNotification) {
        let fileHandle = notification.object as! NSFileHandle
        let data = fileHandle.availableData

        if data.length > 1 {
            // Re-register for notifications.
            fileHandle.waitForDataInBackgroundAndNotify()
            if let result = String(data: data, encoding: NSUTF8StringEncoding) {
                print(result)
            }
        }
    }

    // MARK: Actions

    @IBAction func selectDiskImage(sender: AnyObject) {
        let fileDialog = NSOpenPanel()

        fileDialog.canChooseDirectories = false
        fileDialog.canCreateDirectories = false
        fileDialog.allowsMultipleSelection = false
        fileDialog.allowedFileTypes = ["img"]

        fileDialog.runModal()

        if let path = fileDialog.URL?.path {
            selectedDiskImage.stringValue = path
        }
    }

    @IBAction func format(sender: AnyObject) {
        let diskImagePath = selectedDiskImage.stringValue

        guard let selectedVolume = volumes.titleOfSelectedItem where NSFileManager.defaultManager().fileExistsAtPath(diskImagePath), let session = DASessionCreate(kCFAllocatorDefault) else {
            return
        }

        // Loop through mounted volumes to find the selected volume.
        let mountedVolumes = NSFileManager.defaultManager().mountedVolumeURLsIncludingResourceValuesForKeys([], options: [])!

        for volume in mountedVolumes {
            guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, volume) where selectedVolume == volume.path!, let bsdName = String.fromCString(DADiskGetBSDName(disk)) else {
                return
            }

            let task = NSTask()

            // Use `diskutil` to format the volume.
            task.launchPath = "/usr/sbin/diskutil"

            // When formatting to FAT32, the volume name needs
            // to be in uppercase.
            task.arguments = ["eraseVolume", "fat32", "BOOT", bsdName]

            // Pipe stdout through here.
            let outputPipe = NSPipe()
            outputPipe.fileHandleForReading.waitForDataInBackgroundAndNotify()
            task.standardOutput = outputPipe

            // Pipe errors through here.
            let errorPipe = NSPipe()
            errorPipe.fileHandleForReading.waitForDataInBackgroundAndNotify()
            task.standardError = errorPipe

            // Notify when data is available.
            NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(receivedData(_:)), name: NSFileHandleDataAvailableNotification, object: nil)

            // Restore user interface when process is terminated.
            task.terminationHandler = { _ in
                dispatch_async(dispatch_get_main_queue(), {
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

    @IBAction func quit(sender: AnyObject) {
        NSApplication.sharedApplication().terminate(sender)
    }
}
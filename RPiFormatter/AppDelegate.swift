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
        // Detect when volumes are mounted.
        NSWorkspace.sharedWorkspace().notificationCenter.addObserver(
            self,
            selector: #selector(volumesChanged(_:)),
            name: NSWorkspaceDidMountNotification,
            object: nil
        )
        
        // Detect when volumes are unmounted.
        NSWorkspace.sharedWorkspace().notificationCenter.addObserver(
            self,
            selector: #selector(volumesChanged(_:)),
            name: NSWorkspaceDidUnmountNotification,
            object: nil
        )
        
        // Detect when volumes are renamed.
        NSWorkspace.sharedWorkspace().notificationCenter.addObserver(
            self,
            selector: #selector(volumesChanged(_:)),
            name: NSWorkspaceDidRenameVolumeNotification,
            object: nil
        )
    }
    
    func populateVolumes() {
        let keys = [NSURLVolumeNameKey, NSURLVolumeIsRemovableKey, NSURLVolumeIsEjectableKey]
        let paths = NSFileManager().mountedVolumeURLsIncludingResourceValuesForKeys(keys, options: [])
        
        // Clear previous entries.
        volumes.removeAllItems()

        if let urls = paths {
            for url in urls {
                if let components = url.pathComponents where components.count > 1 && components[1] == "Volumes" {
                    let image = NSWorkspace.sharedWorkspace().iconForFile(url.path!)
                    volumes.addItemWithTitle(url.path!)
                    volumes.lastItem!.image = image
                }
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
        
        fileDialog.canChooseDirectories = false;
        fileDialog.canCreateDirectories = false;
        fileDialog.allowsMultipleSelection = false;
        fileDialog.allowedFileTypes = ["img"];
        
        fileDialog.runModal()
        
        if let path = fileDialog.URL?.path {
            selectedDiskImage.stringValue = path
        }
    }
    
    @IBAction func format(sender: AnyObject) {
        let diskImagePath = selectedDiskImage.stringValue
        
        if let selectedVolume = volumes.titleOfSelectedItem where NSFileManager.defaultManager().fileExistsAtPath(diskImagePath) {
            // Obtain volume identifier to be able to erase the whole disk.
            if let session = DASessionCreate(kCFAllocatorDefault) {
                let mountedVolumes = NSFileManager.defaultManager().mountedVolumeURLsIncludingResourceValuesForKeys([], options: [])!
                
                for volume in mountedVolumes {
                    if let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, volume) where selectedVolume == volume.path! {
                        if let bsdName = String.fromCString(DADiskGetBSDName(disk)) {
                            let task = NSTask()
                            
                            task.launchPath = "/usr/sbin/diskutil"
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
                }
            }
        }
    }
    
    @IBAction func quit(sender: AnyObject) {
        NSApplication.sharedApplication().terminate(sender)
    }
}
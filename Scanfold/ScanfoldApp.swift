import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent macOS from launching into a "0 windows open" saved state
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        // Bring the window in front of Xcode on launch
        NSApp.activate(ignoringOtherApps: true)
    }

    // Single-window utility: closing the window terminates the app
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // Clicking the Dock icon reopens/focuses the window if it was closed or hidden
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in NSApp.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        ScanStorage.waitForPendingWrites()
    }
}

@main
struct ScanfoldApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Scanfold", id: "main") {
            ContentView()
                .frame(minWidth: 1000, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

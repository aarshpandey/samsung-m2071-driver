import SwiftUI
import AppKit

@main
struct SamsungScannerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 840, idealWidth: 980, minHeight: 620, idealHeight: 700)
                .navigationTitle("Samsung Xpress Scanner (Apple Silicon)")
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Scanner") {
                Button("Overview Scan") {
                    NotificationCenter.default.post(name: NSNotification.Name("TriggerOverview"), object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)
                
                Button("Scan / Add Page") {
                    NotificationCenter.default.post(name: NSNotification.Name("TriggerScan"), object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Button("Auto-Crop Document") {
                    NotificationCenter.default.post(name: NSNotification.Name("TriggerAutoCrop"), object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
                
                Divider()
                
                Button("Save Document") {
                    NotificationCenter.default.post(name: NSNotification.Name("TriggerSave"), object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            CommandMenu("View") {
                Button("Zoom In") {
                    NotificationCenter.default.post(name: NSNotification.Name("TriggerZoomIn"), object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)
                
                Button("Zoom Out") {
                    NotificationCenter.default.post(name: NSNotification.Name("TriggerZoomOut"), object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)
                
                Button("Actual Size / Fit") {
                    NotificationCenter.default.post(name: NSNotification.Name("TriggerZoomFit"), object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

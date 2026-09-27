// A window that hides itself on close instead of closing, as Electron apps do
// (win.on('close', e => { e.preventDefault(); win.hide() })): it is ordered out,
// but not minimized, not destroyed, and its app is not hidden.
// It comes back after --reshow-after seconds (0: never), then the app quits after --quit-after.
//
//   swiftc tests/integration/hide_on_close.swift -o tests/integration/bin/hide-on-close
import AppKit

func argument(_ name: String, _ fallback: Double) -> Double {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: name), i + 1 < args.count, let value = Double(args[i + 1]) else { return fallback }
    return value
}

final class Delegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let reshowAfter = argument("--reshow-after", 5)
    let quitAfter = argument("--quit-after", 60)
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 400),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "hide-on-close"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        print("window \(window.windowNumber)")
        fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now() + quitAfter) { NSApp.terminate(nil) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        print("ordered out")
        fflush(stdout)
        if reshowAfter > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + reshowAfter) {
                sender.makeKeyAndOrderFront(nil)
                print("ordered in")
                fflush(stdout)
            }
        }
        return false
    }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

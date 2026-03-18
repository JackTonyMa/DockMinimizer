import Cocoa

/// Represents the state of an application being tracked
struct AppState {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let localizedName: String?

    init(app: NSRunningApplication) {
        self.processIdentifier = app.processIdentifier
        self.bundleIdentifier = app.bundleIdentifier
        self.localizedName = app.localizedName
    }
}
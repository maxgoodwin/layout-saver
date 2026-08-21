import AppKit

let version = "0.1.0"

func printUsage() {
    print("""
    app-snap \(version)
    Save the arrangement of your open windows per monitor setup, and restore it later.

    Usage:
      app-snap             Run as a menu bar app (default)
      app-snap --version   Print the version and exit
      app-snap --help      Show this message
    """)
}

let arguments = CommandLine.arguments.dropFirst()

if arguments.contains("--version") {
    print(version)
    exit(0)
}

if arguments.contains("--help") || arguments.contains("-h") {
    printUsage()
    exit(0)
}

// main.swift's top-level code runs on the main thread but isn't inferred as
// @MainActor by the compiler; assertIsolated is safe here since process startup
// on macOS is guaranteed to happen on the main thread.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

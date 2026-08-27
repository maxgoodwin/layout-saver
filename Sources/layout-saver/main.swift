import AppKit

let version = "0.1.2"

func printUsage() {
    print("""
    layout-saver \(version)
    Save the arrangement of your open windows per monitor setup, and restore it later.

    Usage:
      layout-saver             Run as a menu bar app (default)
      layout-saver --version   Print the version and exit
      layout-saver --help      Show this message
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

import Foundation
import CoreGraphics
import XeneonTouchDriver

enum Mode {
    case run, diagnose, listDisplays, help
}

struct Options {
    var mode = Mode.run
    var flipX = false
    var flipY = false
    var swapXY = false
    var displayID: CGDirectDisplayID?
    var noSeize = false
}

func parseArgs() -> Options {
    var opts = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    if let first = args.first, !first.hasPrefix("-") {
        switch first {
        case "run": opts.mode = .run
        case "diagnose": opts.mode = .diagnose
        case "list-displays": opts.mode = .listDisplays
        case "help": opts.mode = .help
        default: opts.mode = .help
        }
        args.removeFirst()
    }
    var i = 0
    while i < args.count {
        switch args[i] {
        case "--flip-x": opts.flipX = true
        case "--flip-y": opts.flipY = true
        case "--swap-xy": opts.swapXY = true
        case "--no-seize": opts.noSeize = true
        case "--display":
            i += 1
            if i < args.count, let v = UInt32(args[i]) { opts.displayID = v }
        case "-h", "--help": opts.mode = .help
        default: break
        }
        i += 1
    }
    return opts
}

func printHelp() {
    print("""
    xeneon-touch — absolute touch driver for the Corsair Xeneon Edge on macOS

    USAGE:
      xeneon-touch run [--flip-x] [--flip-y] [--swap-xy] [--display <id>] [--no-seize]
      xeneon-touch diagnose      Print HID elements and live touch reports
      xeneon-touch list-displays Print display ids and bounds
      xeneon-touch help

    NOTES:
      • run needs Input Monitoring (read touch) + Accessibility (inject clicks).
      • The Xeneon Toolbox app embeds this driver — running the app is the normal
        way to use it. This CLI is for diagnostics and headless use.
    """)
}

setvbuf(stdout, nil, _IONBF, 0)

let opts = parseArgs()

switch opts.mode {
case .help:
    printHelp()
case .listDisplays:
    Diagnostics.listDisplays()
case .diagnose:
    Diagnostics.run()
case .run:
    let config = TouchServiceConfig(flipX: opts.flipX, flipY: opts.flipY, swapXY: opts.swapXY,
                                    preferredDisplayID: opts.displayID, preferSeize: !opts.noSeize)
    let service = TouchService(config: config)
    service.onPresenceChanged = { present in
        print(present ? "Xeneon Edge connected — touch active." : "Xeneon Edge idle.")
    }
    guard service.start() else { exit(1) }
    print("Waiting for Xeneon Edge… Ctrl-C to stop.")
    CFRunLoopRun()
}

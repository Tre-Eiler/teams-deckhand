// swift-tools-version:5.9
import PackageDescription

// The daemon is a bare executable, not an .app bundle, so macOS only shows
// the microphone permission prompt (used by auto-mute's speech detection) if
// an Info.plist with NSMicrophoneUsageDescription is embedded in the binary
// itself. Without it the process is killed the first time it touches the mic.
let embeddedInfoPlist = Context.packageDirectory + "/Info.plist"

let package = Package(
    name: "teams-bridge-daemon",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/httpswift/swifter.git", from: "1.5.0")
    ],
    targets: [
        .executableTarget(
            name: "teams-bridge-daemon",
            dependencies: [.product(name: "Swifter", package: "swifter")],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                              "-Xlinker", "__info_plist", "-Xlinker", embeddedInfoPlist])
            ]
        )
    ]
)

// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ThisIsNotFree",
    platforms: [.macOS("14.2")],
    products: [.executable(name: "ThisIsNotFree", targets: ["MacAudioMixer"])],
    targets: [
        .target(name: "MixerCore", publicHeadersPath: "include", linkerSettings: [.linkedFramework("CoreAudio"), .linkedFramework("Foundation"), .linkedFramework("IOKit")]),
        .executableTarget(name: "MacAudioMixer", dependencies: ["MixerCore"], linkerSettings: [.linkedFramework("CoreAudio"), .linkedFramework("AppKit"), .linkedFramework("SwiftUI"), .linkedFramework("Metal"), .linkedFramework("UserNotifications"), .linkedFramework("ApplicationServices"), .linkedFramework("CoreWLAN")]),
        .testTarget(name: "UtilityTests", dependencies: ["MacAudioMixer"])
    ]
)

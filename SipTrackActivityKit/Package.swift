// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SipTrackActivityKit",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "SipTrackActivityKit", targets: ["SipTrackActivityKit"]),
    ],
    targets: [
        .target(
            name: "SipTrackActivityKit",
            path: "Sources/SipTrackActivityKit"
        ),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ToastKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ToastKit", targets: ["ToastKit"]),
    ],
    targets: [
        .target(name: "ToastKit"),
    ]
)

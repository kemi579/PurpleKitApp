// swift-tools-version: 6.0
import PackageDescription

// Pure validation tests run on macOS CI without an iOS device or Apple credentials.
let package = Package(
    name: "PurpleKitValidation",
    products: [.library(name: "PurpleKitValidation", targets: ["PurpleKitValidation"])],
    targets: [
        .target(name: "PurpleKitValidation", path: "Sources/Validation"),
        .testTarget(name: "PurpleKitValidationTests", dependencies: ["PurpleKitValidation"],
                    path: "Tests/PurpleKitValidationTests")
    ]
)

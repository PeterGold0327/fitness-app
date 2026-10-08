// swift-tools-version: 5.9
import PackageDescription

// Portable domain tests only. The iPhone app is built with FitnessApp.xcodeproj.
let package = Package(
    name: "FitnessCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "FitnessCore", targets: ["FitnessCore"])],
    targets: [
        .target(name: "FitnessCore", path: "FitnessApp/Services", exclude: ["HealthService.swift", "KeychainFoodCredentials.swift"],
                sources: ["FitnessLogic.swift", "FoodPhotoService.swift"]),
        .testTarget(name: "FitnessCoreTests", dependencies: ["FitnessCore"], path: "FitnessAppTests")
    ]
)

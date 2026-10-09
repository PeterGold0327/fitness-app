// swift-tools-version: 5.9
import PackageDescription

// Portable domain tests only. The iPhone app is built with FitnessApp.xcodeproj.
let package = Package(
    name: "FitnessCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "FitnessCore", targets: ["FitnessCore"])],
    targets: [
        .target(name: "FitnessCore", path: "FitnessApp", exclude: ["FitnessApp.swift", "Models", "ViewModels", "Views",
                    "Services/HealthService.swift", "Services/KeychainFoodCredentials.swift", "Resources/Info.plist",
                    "Resources/FitnessApp.entitlements", "Resources/PrivacyInfo.xcprivacy",
                    "Resources/en.lproj/InfoPlist.strings", "Resources/zh-Hans.lproj/InfoPlist.strings"],
                sources: ["Services/FitnessLogic.swift", "Services/DailyCoach.swift", "Services/TrainingCoach.swift", "Services/PersonalLibrary.swift", "Services/FoodPhotoService.swift", "Services/L10n.swift", "Services/GrowthTimeline.swift", "Services/TimelineMilestones.swift", "Services/TimelineMarkdown.swift"],
                resources: [.process("Resources/en.lproj/Localizable.strings"), .process("Resources/zh-Hans.lproj/Localizable.strings")]),
        .testTarget(name: "FitnessCoreTests", dependencies: ["FitnessCore"], path: "FitnessAppTests")
    ]
)

// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "TidyCore",
  platforms: [.macOS("26.0")],
  products: [
    .library(name: "TidyCore", targets: ["TidyCore"])
  ],
  targets: [
    .target(name: "TidyCore"),
    .testTarget(name: "TidyCoreTests", dependencies: ["TidyCore"]),
  ]
)

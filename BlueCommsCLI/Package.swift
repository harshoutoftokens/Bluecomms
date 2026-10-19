// swift-tools-version: 6.1
//
//  Package.swift
//
//  Why this file exists:
//    SwiftPM manifest. One package, five targets:
//      BlueCommsCore     — framing, crypto, Bonjour/AWDL, files (the radio)
//      BlueCommsChat     — ChatStore: UI state shared by the Mac and iOS apps
//      BlueCommsCLI      — terminal
//      BlueCommsApp      — Mac window
//      BlueCommsSelfTest — XCTest is missing from Command Line Tools, so a
//                          normal executable that prints ok/FAIL
//
//  Info.plist is linked into the two user binaries (`-sectcreate __TEXT
//  __info_plist`) so macOS Local Network / Bonjour prompts work. Without
//  those keys, browse stays empty even with Wi-Fi on.
//
//  The iOS app (../iOS) is an Xcode project that links the BlueCommsCore and
//  BlueCommsChat library products from this package by local path.
//

import Foundation
import PackageDescription

let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let infoPlistPath = packageDirectory.appendingPathComponent("Sources/BlueCommsCLI/Info.plist").path
let appInfoPlistPath = packageDirectory.appendingPathComponent("Sources/BlueCommsApp/Info.plist").path

let package = Package(
    name: "BlueCommsCLI",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "BlueCommsCore", targets: ["BlueCommsCore"]),
        .library(name: "BlueCommsChat", targets: ["BlueCommsChat"]),
        .executable(name: "BlueCommsCLI", targets: ["BlueCommsCLI"]),
        .executable(name: "BlueCommsApp", targets: ["BlueCommsApp"]),
        .executable(name: "BlueCommsSelfTest", targets: ["BlueCommsSelfTest"]),
    ],
    targets: [
        .target(
            name: "BlueCommsCore"
        ),
        .target(
            name: "BlueCommsChat",
            dependencies: ["BlueCommsCore"]
        ),
        .executableTarget(
            name: "BlueCommsCLI",
            dependencies: ["BlueCommsCore"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlistPath,
                ])
            ]
        ),
        .executableTarget(
            name: "BlueCommsApp",
            dependencies: ["BlueCommsCore", "BlueCommsChat"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", appInfoPlistPath,
                ])
            ]
        ),
        .executableTarget(
            name: "BlueCommsSelfTest",
            dependencies: ["BlueCommsCore"]
        ),
    ]
)

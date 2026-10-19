//
//  Outbox.swift
//
//  Why this file exists:
//    On the Mac, ChatStore can stream straight from the file you picked. iOS
//    revokes access to picked files and Photos temp files right after the
//    picker returns, and a queued file may only send minutes later. So every
//    outgoing file is first copied into our own container, then sent from there.
//
//  Location: Application Support/BlueComms Outbox/<uuid>/<name>. Kept after
//  sending because the thread's file card still points at it.
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

enum Outbox {
    static var directory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("BlueComms Outbox", isDirectory: true)
    }

    /// Copy a file the user picked into the outbox. Handles security-scoped URLs.
    static func copy(_ source: URL) throws -> URL {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }
}

/// A photo or video from PhotosPicker, already copied into the outbox.
struct PickedMedia: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            PickedMedia(url: try Outbox.copy(received.file))
        }
        FileRepresentation(importedContentType: .image) { received in
            PickedMedia(url: try Outbox.copy(received.file))
        }
    }
}

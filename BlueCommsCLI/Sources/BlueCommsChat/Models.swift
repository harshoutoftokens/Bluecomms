//
//  Models.swift
//
//  Why this file exists:
//    SwiftUI needs Identifiable, Hashable types. The radio has DiscoveredPeer
//    (Bonjour only). The sidebar also needs last-seen and LIVE, so we keep a
//    separate NearbyPeer here (PR #4). Shared by the Mac and iOS apps.
//

import Foundation

/// A nearby Mac from Bonjour, plus whether we have a live TCP session.
public struct NearbyPeer: Identifiable, Hashable, Sendable {
    /// Device UUID string from the Bonjour TXT `id` key.
    public let id: String
    public let displayName: String
    /// First 8 hex chars of the id, shown under the name.
    public let shortName: String
    /// Still in the current Bonjour browse results.
    public var isOnline: Bool
    /// Last time they appeared or disappeared from Bonjour.
    public var lastSeen: Date
    /// Handshake finished. Shows the LIVE badge.
    public var isSessionOpen: Bool
}

/// Connect button state. ready = at least one handshake is up.
public enum ConnectionPhase: Equatable, Sendable {
    case idle, connecting, ready
}

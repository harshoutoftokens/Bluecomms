//
//  Exports.swift
//
//  Why this file exists:
//    ChatStore and NearbyPeer moved to the shared BlueCommsChat library so the
//    iOS app can use them too. Re-exporting here keeps every Mac view file
//    working without its own import.
//

@_exported import BlueCommsChat

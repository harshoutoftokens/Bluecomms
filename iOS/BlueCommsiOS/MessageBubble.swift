//
//  MessageBubble.swift
//
//  Why this file exists:
//    One chat row: a text bubble, or a file card with progress. Outgoing is
//    the accent color on the right, incoming is gray on the left (Messages).
//

import BlueCommsCore
import SwiftUI
import UIKit

struct MessageBubble: View {
    let message: ChatMessage
    /// Tapping a finished file asks the conversation to show Quick Look.
    let onOpenFile: (URL) -> Void

    var body: some View {
        HStack {
            if message.isLocal { Spacer(minLength: 60) }
            VStack(alignment: message.isLocal ? .trailing : .leading, spacing: 2) {
                if message.kind == .file {
                    fileCard
                } else {
                    Text(message.text)
                        .foregroundStyle(message.isLocal ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(bubbleFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .contextMenu {
                            Button { UIPasteboard.general.string = message.text } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                }
                caption
            }
            if !message.isLocal { Spacer(minLength: 60) }
        }
    }

    private var bubbleFill: Color {
        message.isLocal ? .accentColor : Color(.systemGray5)
    }

    private var fileCard: some View {
        Button {
            if let path = message.filePath { onOpenFile(URL(fileURLWithPath: path)) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: fileIcon)
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.fileName ?? message.text)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        Text(byteCount(of: message.fileSize ?? 0))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                if isInFlight {
                    ProgressView(value: message.progress)
                    Text("\(byteCount(of: UInt64(Double(message.fileSize ?? 0) * message.progress))) of \(byteCount(of: message.fileSize ?? 0))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(width: 250, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(.separator))
            )
        }
        .buttonStyle(.plain)
        .disabled(message.fileState != .complete || message.filePath == nil)
    }

    private var isInFlight: Bool {
        message.fileState == .transferring
            || (message.fileState == .queued && message.progress > 0 && message.progress < 1)
    }

    private var fileIcon: String {
        let ext = (message.fileName as NSString?)?.pathExtension.lowercased() ?? ""
        if ["png", "jpg", "jpeg", "heic", "gif", "webp", "tif", "tiff"].contains(ext) { return "photo" }
        if ["mov", "mp4", "m4v", "avi", "mkv"].contains(ext) { return "film" }
        return "doc.fill"
    }

    private func byteCount(of value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    @ViewBuilder
    private var caption: some View {
        let time = message.sentAt.formatted(date: .omitted, time: .shortened)
        Group {
            switch (message.kind == .file ? message.fileState : nil, message.delivery) {
            case (.failed?, _):
                Label("Not Delivered", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            case (.cancelled?, _):
                Text("\(time) · Cancelled")
            case (.queued?, _), (nil, .queued):
                Label("\(time) · Waiting to send", systemImage: "clock")
            case (.transferring?, _):
                Text("\(time) · Sending…")
            case (.complete?, _):
                Text(message.isLocal ? "\(time) · Delivered" : "\(time) · Tap to open")
            default:
                Text(time)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
    }
}

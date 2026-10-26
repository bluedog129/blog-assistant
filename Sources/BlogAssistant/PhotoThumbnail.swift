import AppKit
import Photos
import SwiftUI
import AVKit

struct PhotoThumbnail: View {
    let asset: PHAsset
    let manager: PHCachingImageManager
    var showFullImage = false
    @State private var image: NSImage?
    @State private var requestID: PHImageRequestID?
    @State private var token: UUID?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1))
                if let image {
                    GeometryReader { geometry in
                        if showFullImage {
                            Image(nsImage: image).resizable().scaledToFit()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        } else {
                            Image(nsImage: image).resizable().scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        }
                    }
                } else if failed {
                    VStack(spacing: 8) {
                        Image(systemName: "icloud.slash")
                        Button("다시 시도") { load() }.buttonStyle(.borderless)
                    }.foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
                if asset.mediaType == .video {
                    VStack { Spacer(); HStack { Image(systemName: "play.fill"); Text(Self.durationLabel(asset.duration)); Spacer() } }
                        .font(.caption.bold()).foregroundStyle(.white).padding(10)
                        .background(alignment: .bottom) { LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom) }
                }
            }.aspectRatio(showFullImage ? CGFloat(max(1, asset.pixelWidth)) / CGFloat(max(1, asset.pixelHeight)) : 1, contentMode: .fit)
                // Cropping an image alone does not limit its hit-testing area.
                .contentShape(Rectangle())
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(asset.creationDate.map { $0.formatted(date: .omitted, time: .shortened) } ?? "시간 정보 없음")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { load() }
        .onDisappear {
            token = nil
            if let requestID { manager.cancelImageRequest(requestID) }
            requestID = nil
            image = nil
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(asset.creationDate.map { "\(asset.mediaType == .video ? "영상" : "사진"), \($0.formatted())" } ?? "촬영일 정보 없는 사진")
    }

    private static func durationLabel(_ duration: Double) -> String {
        let value = duration.isFinite ? max(0, Int(duration)) : 0
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    private func load() {
        if let requestID { manager.cancelImageRequest(requestID) }
        let currentToken = UUID()
        token = currentToken
        failed = false
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        requestID = manager.requestImage(for: asset, targetSize: CGSize(width: 480, height: 480), contentMode: .aspectFill, options: options) { result, info in
            let cancelled = (info?[PHImageCancelledKey] as? Bool) == true
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
            DispatchQueue.main.async {
                guard token == currentToken, !cancelled else { return }
                if let result { image = result }
                if !degraded {
                    failed = result == nil
                    requestID = nil
                }
            }
        }
    }
}


struct DraftVideoPreview: View {
    let asset: PHAsset
    @State private var player: AVPlayer?
    @State private var requestID: PHImageRequestID?
    @State private var token: UUID?
    @State private var failed = false
    var body: some View {
        VStack {
            if let player { VideoPlayer(player: player) }
            else if failed { Text("영상을 불러오지 못했습니다. iCloud 다운로드와 권한을 확인하세요.") }
            else { ProgressView("영상 불러오는 중…") }
        }
        .aspectRatio(CGFloat(max(1, asset.pixelWidth)) / CGFloat(max(1, asset.pixelHeight)), contentMode: .fit)
        .onAppear {
            let current = UUID(); token = current
            let options = PHVideoRequestOptions(); options.isNetworkAccessAllowed = true
            requestID = PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                DispatchQueue.main.async {
                    guard token == current else { return }
                    player = item.map { AVPlayer(playerItem: $0) }; failed = item == nil; requestID = nil
                }
            }
        }
        .onDisappear { token = nil; player?.pause(); player = nil; if let requestID { PHImageManager.default().cancelImageRequest(requestID) } }
    }
}

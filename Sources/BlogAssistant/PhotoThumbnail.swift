import AppKit
import Photos
import SwiftUI

struct PhotoThumbnail: View {
    let asset: PHAsset
    let manager: PHCachingImageManager
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
                        Image(nsImage: image).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    }
                } else if failed {
                    VStack(spacing: 8) {
                        Image(systemName: "icloud.slash")
                        Button("다시 시도") { load() }.buttonStyle(.borderless)
                    }.foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }.aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10))
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
        .accessibilityLabel(asset.creationDate.map { "사진, \($0.formatted())" } ?? "촬영일 정보 없는 사진")
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

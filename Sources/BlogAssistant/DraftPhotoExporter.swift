import AppKit
import Photos
import ImageIO
import UniformTypeIdentifiers
import AVFoundation

@MainActor enum DraftPhotoExporter {
    static func export(_ photos: [DraftPhoto], assets: [String: PHAsset], folder: URL, postText: String? = nil, template: DraftTemplate = .plain, review: VisitReview? = nil) async throws -> URL {
        guard (postText != nil || !photos.isEmpty), photos.allSatisfy({ assets[$0.id] != nil }) else {
            throw failure("선택한 사진 중 사용할 수 없는 사진이 있습니다. 권한과 방문 구성을 확인하세요.")
        }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let output = folder.appendingPathComponent("블로그사진-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        do {
            var lines: [String] = []
            var filenames: [String] = []
            for (index, photo) in photos.enumerated() {
                try Task.checkCancellation()
                let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                guard status == .authorized || status == .limited else { throw failure("사진 보관함 접근 권한이 필요합니다.") }
                let asset = assets[photo.id]!
                guard (asset.mediaType == .video) == photo.isVideo else { throw failure("\(index + 1)번의 사진·영상 종류가 바뀌었습니다. 선택 목록을 다시 확인하세요.") }
                let caption = photo.caption.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
                let base = String(format: "%02d", index + 1) + "_" + (caption.isEmpty ? "미디어" : String(caption.prefix(50)))
                if photo.isVideo {
                    let name = base + ".mp4"
                    try await exportVideo(asset, to: output.appendingPathComponent(name))
                    lines.append("\(photo.marker(index + 1)) → \(name)")
                    filenames.append(name)
                    continue
                }
                let data = try await imageData(asset)
                try Task.checkCancellation()
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 3000
                      ] as CFDictionary) else { throw failure("사진 \(index + 1)을 JPEG로 변환하지 못했습니다.") }
                let name = base + ".jpg"
                let file = output.appendingPathComponent(name)
                guard let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
                    throw failure("사진 파일을 만들지 못했습니다.")
                }
                // Re-encode pixels without the source's GPS/EXIF metadata.
                CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { throw failure("사진 파일을 저장하지 못했습니다.") }
                lines.append("[사진 \(index + 1)] → \(name)")
                filenames.append(name)
            }
            if let postText {
                var packet = try NaverPostPacket.make(text: postText, photos: photos, filenames: filenames, template: template, review: review)
                for index in packet.photos.indices {
                    let size = try FileManager.default.attributesOfItem(atPath: output.appendingPathComponent(packet.photos[index].filename).path)[.size] as? NSNumber
                    packet.photos[index].byteCount = size?.intValue
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
                try encoder.encode(packet).write(to: output.appendingPathComponent("naver-post.json"), options: .atomic)
            }
            try lines.joined(separator: "\n").write(to: output.appendingPathComponent("사진순서.txt"), atomically: true, encoding: .utf8)
            return output
        } catch {
            // Only remove this operation's new, incomplete export directory.
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
    static let maximumVideoBytes = 200_000_000

    private static func exportVideo(_ photo: PHAsset, to file: URL) async throws {
        guard photo.duration.isFinite, photo.duration > 0, photo.duration <= 900 else {
            throw failure("영상은 15분 이내로 준비하세요. 길이가 긴 영상은 자동으로 자르지 않습니다.")
        }
        let asset: AVAsset = try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.version = .current; options.deliveryMode = .highQualityFormat; options.isNetworkAccessAllowed = true
            PHImageManager.default().requestAVAsset(forVideo: photo, options: options) { asset, _, _ in
                if let asset { continuation.resume(returning: asset) }
                else { continuation.resume(throwing: failure("영상을 읽지 못했습니다. iCloud 다운로드와 보관함 권한을 확인하세요.")) }
            }
        }
        try Task.checkCancellation()
        try await exportVideoAsset(asset, to: file)
    }

    // Shared with an offline fixture check; it never modifies the Photos original.
    static func exportVideoAsset(_ asset: AVAsset, to file: URL) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080), session.supportedFileTypes.contains(.mp4) else {
            throw failure("이 영상을 MP4로 변환할 수 없습니다.")
        }
        session.outputURL = file; session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.metadata = []; session.metadataItemFilter = .forSharing()
        let handle = VideoExportHandle(session)
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                handle.session.exportAsynchronously {
                    if handle.session.status == .completed { continuation.resume() }
                    else { continuation.resume(throwing: handle.session.error ?? failure("영상 변환이 중단됐습니다.")) }
                }
            }
        }, onCancel: { handle.session.cancelExport() })
        try Task.checkCancellation()
        let bytes = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
        guard bytes > 0, bytes <= maximumVideoBytes else { throw failure("변환된 영상은 200MB 이내여야 합니다. 영상을 짧게 편집한 뒤 다시 선택하세요.") }
    }

    private static func imageData(_ asset: PHAsset) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.version = .current
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: failure("사진을 읽지 못했습니다. iCloud 다운로드와 네트워크 상태를 확인하세요.")) }
            }
        }
    }
    nonisolated private static func failure(_ message: String) -> NSError {
        NSError(domain: "DraftPhotoExporter", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

// AVAssetExportSession's asynchronous API permits status/error reads and cancel
// from its completion/cancellation callbacks; the configured session is immutable here.
private final class VideoExportHandle: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}

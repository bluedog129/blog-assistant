import AppKit
import Photos
import ImageIO
import UniformTypeIdentifiers

@MainActor enum DraftPhotoExporter {
    static func export(_ photos: [DraftPhoto], assets: [String: PHAsset], folder: URL) async throws -> URL {
        guard !photos.isEmpty, photos.allSatisfy({ assets[$0.id] != nil }) else {
            throw failure("선택한 사진 중 사용할 수 없는 사진이 있습니다. 권한과 방문 구성을 확인하세요.")
        }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let output = folder.appendingPathComponent("블로그사진-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        do {
            var lines: [String] = []
            for (index, photo) in photos.enumerated() {
                try Task.checkCancellation()
                let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                guard status == .authorized || status == .limited else { throw failure("사진 보관함 접근 권한이 필요합니다.") }
                let data = try await imageData(assets[photo.id]!)
                try Task.checkCancellation()
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 3000
                      ] as CFDictionary) else { throw failure("사진 \(index + 1)을 JPEG로 변환하지 못했습니다.") }
                let caption = photo.caption.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
                let name = String(format: "%02d", index + 1) + "_" + (caption.isEmpty ? "사진" : String(caption.prefix(50))) + ".jpg"
                let file = output.appendingPathComponent(name)
                guard let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
                    throw failure("사진 파일을 만들지 못했습니다.")
                }
                // Re-encode pixels without the source's GPS/EXIF metadata.
                CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { throw failure("사진 파일을 저장하지 못했습니다.") }
                lines.append("[사진 \(index + 1)] → \(name)")
            }
            try lines.joined(separator: "\n").write(to: output.appendingPathComponent("사진순서.txt"), atomically: true, encoding: .utf8)
            return output
        } catch {
            // Only remove this operation's new, incomplete export directory.
            try? FileManager.default.removeItem(at: output)
            throw error
        }
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
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "DraftPhotoExporter", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

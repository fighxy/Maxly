import Foundation
import SwiftUI
import Testing
import MaxlyDomain
import MaxlyPresentation
@testable import MaxlyUI

@Suite("Аватар шапки при загрузке историй")
@MainActor
struct ChatAvatarLayoutTests {
    @Test("Появление кольца не меняет размер и положение изображения внутри слота")
    func loadingStoryRingKeepsImage() throws {
        let avatar = ChatAvatar(kind: .initials("A"), colorIndex: 5)
        let ring = StoryRing(owner: StoryOwner(id: "bob"), name: "Боб", updatedAt: .now, total: 2, read: 0)

        func render(_ ring: StoryRing?) throws -> CGImage {
            let renderer = ImageRenderer(content: StoryRingAvatar(
                avatar: avatar, ring: ring, size: 44, reservesRingSpace: true
            ).environment(\.colorScheme, .light))
            renderer.scale = 1
            return try #require(renderer.cgImage)
        }

        let before = try render(nil)
        let after = try render(ring)
        #expect(before.width == 44 && before.height == 44)
        #expect(after.width == before.width && after.height == before.height)
        // Центральная область не пересекает кольцо: сравниваем само изображение,
        // а не только внешний frame, который и раньше оставался неизменным.
        let center = CGRect(x: 10, y: 10, width: 24, height: 24)
        let beforeCrop = try #require(before.cropping(to: center))
        let afterCrop = try #require(after.cropping(to: center))
        func pixels(_ image: CGImage) throws -> Data {
            var bytes = [UInt8](repeating: 0, count: 24 * 24 * 4)
            try bytes.withUnsafeMutableBytes { buffer in
                let context = try #require(CGContext(
                    data: buffer.baseAddress, width: 24, height: 24, bitsPerComponent: 8,
                    bytesPerRow: 24 * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.draw(image, in: CGRect(x: 0, y: 0, width: 24, height: 24))
            }
            return Data(bytes)
        }
        let beforeData = try pixels(beforeCrop)
        let afterData = try pixels(afterCrop)
        #expect(beforeData == afterData)
    }
}

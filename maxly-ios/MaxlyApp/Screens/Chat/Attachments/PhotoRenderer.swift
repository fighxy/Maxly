import CoreImage
import ImageIO
import UIKit
import MaxlyDomain
import MaxlyPresentation

/// UIImage передаётся только как неизменяемый результат рендера.
struct PhotoRenderedImage: @unchecked Sendable { let image: UIImage }

/// Actor держит декодированный оригинал; обработка и JPEG не занимают главный поток.
actor PhotoRenderer {
    private let original: CGImage
    private let previewBase: CGImage
    private let context = CIContext()
    nonisolated let size: PhotoSize

    static func load(_ draft: AttachmentDraft) async throws -> PhotoRenderer {
        try await Task.detached(priority: .userInitiated) { try PhotoRenderer(path: draft.path) }.value
    }

    private init(path: String) throws {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let original = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2560,
              ] as CFDictionary) else { throw MediaExporter.Failure.unreadable }
        self.original = original
        size = PhotoSize(width: original.width, height: original.height)
        let scale = min(1, 1200.0 / Double(max(original.width, original.height)))
        let target = CGSize(width: max(1, (Double(original.width) * scale).rounded()), height: max(1, (Double(original.height) * scale).rounded()))
        previewBase = Self.draw(size: target) { _ in UIImage(cgImage: original).draw(in: CGRect(origin: .zero, size: target)) }
    }

    func preview(_ edits: [PhotoEdit]) throws -> PhotoRenderedImage {
        PhotoRenderedImage(image: UIImage(cgImage: try render(previewBase, edits)))
    }

    func export(_ edits: [PhotoEdit]) throws -> AttachmentDraft {
        let image = try render(original, edits)
        return try MediaExporter.draft(camera: UIImage(cgImage: image))
    }

    private static func draw(size: CGSize, opaque: Bool = true, _ body: (CGContext) -> Void) -> CGImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = opaque
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            if opaque { UIColor.white.setFill(); renderer.fill(CGRect(origin: .zero, size: size)) }
            body(renderer.cgContext)
        }.cgImage!
    }

    private func render(_ base: CGImage, _ edits: [PhotoEdit]) throws -> CGImage {
        var image = base
        var layer = Self.draw(size: CGSize(width: base.width, height: base.height), opaque: false) { _ in }
        func composite() -> CGImage {
            let size = CGSize(width: image.width, height: image.height)
            return Self.draw(size: size) { _ in
                UIImage(cgImage: image).draw(in: CGRect(origin: .zero,size: size))
                UIImage(cgImage: layer).draw(in: CGRect(origin: .zero,size: size))
            }
        }
        func transform(_ source: CGImage, _ edit: PhotoEdit, opaque: Bool) -> CGImage {
            let size = CGSize(width: source.width,height: source.height)
            var target = size
            if case .rotate = edit { target = CGSize(width: size.height,height: size.width) }
            return Self.draw(size: target, opaque: opaque) { cg in
                switch edit {
                case .rotate(let clockwise):
                    if clockwise { cg.translateBy(x: size.height,y: 0); cg.rotate(by: .pi/2) }
                    else { cg.translateBy(x: 0,y: size.width); cg.rotate(by: -.pi/2) }
                case .flip: cg.translateBy(x: size.width,y: 0); cg.scaleBy(x: -1,y: 1)
                case .straighten(let degrees):
                    let a = degrees * .pi/180, c = abs(cos(a)), s = abs(sin(a))
                    let scale = max(c+size.height/size.width*s,c+size.width/size.height*s)
                    cg.translateBy(x: size.width/2,y: size.height/2); cg.rotate(by: a); cg.scaleBy(x: scale,y: scale); cg.translateBy(x: -size.width/2,y: -size.height/2)
                default: break
                }
                UIImage(cgImage: source).draw(in: CGRect(origin: .zero,size: size))
            }
        }
        for edit in edits {
            try Task.checkCancellation()
            let size = CGSize(width: image.width, height: image.height)
            let shortest = Double(min(image.width, image.height))
            switch edit {
            case .crop(let crop):
                let p = crop.pixels(PhotoSize(width: image.width, height: image.height))
                guard let cropped = image.cropping(to: CGRect(x: p.x, y: p.y, width: p.width, height: p.height)) else { throw MediaExporter.Failure.unreadable }
                guard let croppedLayer = layer.cropping(to: CGRect(x: p.x,y: p.y,width: p.width,height: p.height)) else { throw MediaExporter.Failure.unreadable }
                image = cropped
                layer = croppedLayer
            case .rotate, .flip, .straighten:
                image = transform(image,edit,opaque: true); layer = transform(layer,edit,opaque: false)
            case .adjust(let values): image = try adjust(image,values)
            case .filter(let preset, let amount):
                let input = CIImage(cgImage: image)
                let matrix: [[CGFloat]]
                let bias: [CGFloat]
                switch preset {
                case .mono: matrix = Array(repeating: [0.299, 0.587, 0.114, 0], count: 3); bias = [0, 0, 0, 0]
                case .sepia: matrix = [[0.393, 0.769, 0.189, 0], [0.349, 0.686, 0.168, 0], [0.272, 0.534, 0.131, 0]]; bias = [0, 0, 0, 0]
                case .warm: matrix = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0]]; bias = [20 / 255.0, 5 / 255.0, -15 / 255.0, 0]
                case .cool: matrix = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0]]; bias = [-15 / 255.0, 3 / 255.0, 20 / 255.0, 0]
                case .contrast: matrix = [[1.25, 0, 0, 0], [0, 1.25, 0, 0], [0, 0, 1.25, 0]]; bias = [-32 / 255.0, -32 / 255.0, -32 / 255.0, 0]
                }
                func vector(_ values: [CGFloat]) -> CIVector { CIVector(x: values[0], y: values[1], z: values[2], w: values[3]) }
                let filtered = input.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": vector(matrix[0]), "inputGVector": vector(matrix[1]), "inputBVector": vector(matrix[2]),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1), "inputBiasVector": vector(bias),
                ]).applyingFilter("CIColorClamp", parameters: [
                    "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0), "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
                ])
                let output = input.applyingFilter("CIDissolveTransition", parameters: ["inputTargetImage": filtered, "inputTime": amount])
                guard let result = context.createCGImage(output, from: input.extent) else { throw MediaExporter.Failure.unreadable }
                image = result
            case .stroke(let points, let color, let width, let brush):
                guard let first = points.first else { continue }
                let previous = layer
                let blurred: CGImage?
                if brush == .blur {
                    let input = CIImage(cgImage: composite())
                    blurred = context.createCGImage(input.clampedToExtent().applyingFilter("CIBoxBlur",parameters: ["inputRadius": max(2,shortest*0.012)]).cropped(to: input.extent),from: input.extent)
                } else { blurred = nil }
                layer = Self.draw(size: size,opaque: false) { cg in
                    UIImage(cgImage: previous).draw(in: CGRect(origin: .zero, size: size))
                    cg.setStrokeColor(Self.color(color).cgColor); cg.setFillColor(Self.color(color).cgColor)
                    if brush == .marker { cg.setAlpha(0.4) }
                    if brush == .eraser { cg.setBlendMode(.clear) }
                    cg.setLineWidth(width * shortest); cg.setLineCap(.round); cg.setLineJoin(.round)
                    cg.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
                    for p in points.dropFirst() { cg.addLine(to: CGPoint(x: p.x * size.width, y: p.y * size.height)) }
                    if brush == .arrow, let last = points.last, points.count > 1 {
                        let angle = atan2((last.y-first.y)*size.height,(last.x-first.x)*size.width), length = max(width*shortest*4,shortest*0.04)
                        for side in [-1.0, 1.0] {
                            let turn = Double(angle) + side * 0.5
                            cg.move(to: CGPoint(x: last.x*size.width,y: last.y*size.height))
                            cg.addLine(to: CGPoint(
                                x: last.x * size.width - length * CGFloat(cos(turn)),
                                y: last.y * size.height - length * CGFloat(sin(turn))
                            ))
                        }
                    }
                    if let blurred {
                        if points.count == 1 { cg.addEllipse(in: CGRect(x: first.x*size.width-width*shortest/2,y: first.y*size.height-width*shortest/2,width: width*shortest,height: width*shortest)) }
                        else { cg.replacePathWithStrokedPath() }
                        cg.clip(); UIImage(cgImage: blurred).draw(in: CGRect(origin: .zero,size: size)); return
                    }
                    cg.strokePath()
                    if points.count == 1 {
                        let radius = width * shortest / 2
                        cg.fillEllipse(in: CGRect(x: first.x * size.width - radius, y: first.y * size.height - radius, width: radius * 2, height: radius * 2))
                    }
                }
            case .text(let text):
                let previous = layer
                layer = Self.draw(size: size,opaque: false) { _ in
                    UIImage(cgImage: previous).draw(in: CGRect(origin: .zero, size: size))
                    let fontSize = text.size*shortest
                    let font: UIFont
                    switch text.font {
                    case .sans: font = .boldSystemFont(ofSize: fontSize)
                    case .mono: font = .monospacedSystemFont(ofSize: fontSize,weight: .bold)
                    case .italic: font = .italicSystemFont(ofSize: fontSize)
                    case .serif: font = UIFont(name: "Georgia-Bold",size: fontSize) ?? .boldSystemFont(ofSize: fontSize)
                    }
                    let paragraph = NSMutableParagraphStyle()
                    paragraph.alignment = text.alignment == .left ? .left : text.alignment == .center ? .center : .right
                    var attributes: [NSAttributedString.Key: Any] = [.font: font,.foregroundColor: Self.color(text.color),.paragraphStyle: paragraph]
                    if text.style == .outline { attributes[.strokeColor] = UIColor.black; attributes[.strokeWidth] = -2 }
                    let string = text.text as NSString
                    let bounds = string.size(withAttributes: attributes)
                    let origin = CGPoint(x: min(text.point.x * size.width, max(0, size.width - bounds.width)), y: min(text.point.y * size.height, max(0, size.height - bounds.height)))
                    let rect = CGRect(origin: origin,size: bounds)
                    if text.style == .solid || text.style == .translucent {
                        UIColor.black.withAlphaComponent(text.style == .solid ? 1 : 0.55).setFill()
                        UIBezierPath(roundedRect: rect.insetBy(dx: -4,dy: -4),cornerRadius: 8).fill()
                    }
                    string.draw(in: rect,withAttributes: attributes)
                }
            case .shape(let rect,let shape,let color,let width,let filled):
                let previous = layer
                layer = Self.draw(size: size,opaque: false) { cg in
                    UIImage(cgImage: previous).draw(in: CGRect(origin: .zero,size: size))
                    let box = CGRect(x: rect.left*size.width,y: rect.top*size.height,width: (rect.right-rect.left)*size.width,height: (rect.bottom-rect.top)*size.height)
                    cg.setStrokeColor(Self.color(color).cgColor);cg.setFillColor(Self.color(color).cgColor);cg.setLineWidth(width*shortest)
                    if shape == .ellipse { cg.addEllipse(in: box) } else { cg.addRect(box) }
                    cg.drawPath(using: filled ? .fill : .stroke)
                }
            case .replaceText, .removeText: break // Разрешаются в истории до рендера.
            }
        }
        return composite()
    }

    private func adjust(_ image: CGImage, _ values: PhotoAdjustments) throws -> CGImage {
        let w = image.width, h = image.height
        var pixels = [UInt32](repeating: 0,count: w*h)
        let processor = PhotoColorProcessor(values)
        let result: CGImage? = try pixels.withUnsafeMutableBytes { bytes in
            guard let cg = CGContext(data: bytes.baseAddress,width: w,height: h,bitsPerComponent: 8,bytesPerRow: w*4,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
            cg.draw(image,in: CGRect(x: 0,y: 0,width: w,height: h))
            let words = bytes.bindMemory(to: UInt32.self)
            for y in 0..<h {
                try Task.checkCancellation()
                for x in 0..<w { words[y*w+x] = processor.pixel(words[y*w+x],x: x,y: y,width: w,height: h) }
            }
            return cg.makeImage()
        }
        guard let result else { throw MediaExporter.Failure.unreadable }
        var output = CIImage(cgImage: result)
        let extent = output.extent, shortest = Double(min(w,h))
        if values[.sharpen] > 0 { output = output.clampedToExtent().applyingFilter("CIUnsharpMask",parameters: ["inputRadius": max(1,shortest*0.0015),"inputIntensity": values[.sharpen]*2]).cropped(to: extent) }
        if values[.blur] > 0 { output = output.clampedToExtent().applyingFilter("CIBoxBlur",parameters: ["inputRadius": max(1,shortest*0.025*values[.blur])]).cropped(to: extent) }
        guard let final = context.createCGImage(output,from: extent) else { throw MediaExporter.Failure.unreadable }
        return final
    }

    private static func color(_ rgb: UInt32) -> UIColor {
        UIColor(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
}

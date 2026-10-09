import Foundation
import Testing
@testable import MaxlyPresentation

@Suite("Фоторедактор: геометрия, история и цвет")
struct PhotoEditsTests {
    @Test func dimensionsAndUndo() {
        var history = PhotoEditHistory()
        history.add(.rotate(clockwise: true))
        history.add(.crop(PhotoCrop(left: 0.25,top: 0,right: 0.75,bottom: 1)))
        #expect(history.size(PhotoSize(width: 800,height: 400)) == PhotoSize(width: 200,height: 800))
        history.undo();history.undo()
        #expect(history.size(PhotoSize(width: 800,height: 400)) == PhotoSize(width: 800,height: 400))
        history.redo();history.redo()
        #expect(history.edits.count == 2)
        let tiny = PhotoCrop(left: 0.999,top: 0.999,right: 1,bottom: 1).pixels(PhotoSize(width: 1,height: 1))
        #expect(tiny.width == 1 && tiny.height == 1)
    }
    @Test func editableTextSurvivesGeometryAndCanBeRestored() {
        let text = PhotoText(text: "До",point: PhotoPoint(x: 0.2,y: 0.3),color: 0xffffff,size: 0.1)
        var history = PhotoEditHistory(edits: [.text(text),.rotate(clockwise: true)])
        var changed = text;changed.text = "После"
        history.add(.replaceText(changed))
        #expect(history.texts.first?.text == "После")
        history.undo();#expect(history.texts.first?.text == "До")
        history.add(.removeText(text.id));#expect(history.texts.isEmpty)
        history.undo();#expect(history.texts.count == 1)
        let position = history.textPoint(text.id,displayed: PhotoPoint(x: 0.2,y: 0.3),original: PhotoSize(width: 800,height: 400))
        #expect(abs(position.x-0.3)<0.00001 && abs(position.y-0.8)<0.00001)
    }
    @Test func movableCropStaysInsidePhoto() {
        let drag = PhotoCropDrag(rect: PhotoCrop(left: 0.2,top: 0.2,right: 0.8,bottom: 0.8),start: PhotoPoint(x: 0.5,y: 0.5),thresholdX: 0.02,thresholdY: 0.02)
        let moved = drag.update(PhotoPoint(x: 1,y: 1))
        #expect(moved.right == 1 && moved.bottom == 1)
        #expect(abs(moved.right-moved.left-0.6)<0.00001)
    }
    @Test func neutralCorrectionAndCurvesPreservePixels() {
        let processor = PhotoColorProcessor(PhotoAdjustments())
        let pixels: [UInt32] = [0xff000000,0xffffffff,0xff123456,0xff8092ac]
        for pixel in pixels {
            #expect(processor.pixel(pixel,x: 3,y: 5,width: 10,height: 10) == pixel)
        }
        var values = PhotoAdjustments();values[.saturation] = -1
        let gray = PhotoColorProcessor(values).pixel(0xffad7291,x: 0,y: 0,width: 10,height: 10)
        #expect((gray>>16)&255 == gray&255)
    }
}

import SwiftUI
import UIKit
import MaxlyDomain
import MaxlyPresentation

struct PhotoEditor: View {
    let draft: AttachmentDraft
    let onSave: (AttachmentDraft, PhotoEditHistory) -> Void
    let onClose: () -> Void

    private enum Tool: String, CaseIterable { case crop = "Кадр", rotate = "Поворот", draw = "Рисунок", text = "Текст", filter = "Фильтры" }
    private let colors: [UInt32] = [0xffffff, 0x111111, 0xef5350, 0xffca28, 0x66bb6a, 0x42a5f5]
    @State private var renderer: PhotoRenderer?
    @State private var preview: UIImage?
    @State private var history = PhotoEditHistory()
    @State private var tool = Tool.crop
    @State private var crop = PhotoCrop.full
    @State private var points: [PhotoPoint] = []
    @State private var ink: UInt32 = 0xffffff
    @State private var brush = 0.012
    @State private var fontSize = 0.07
    @State private var text = ""
    @State private var filter = PhotoFilter.mono
    @State private var amount = 1.0
    @State private var filterPreview = false
    @State private var busy = false
    @State private var rendering = false
    @State private var failure: String?
    @State private var brushTool = PhotoBrush.pen
    @State private var shape: PhotoShape?
    @State private var filled = false
    @State private var cropDrag: PhotoCropDrag?
    @State private var angle = 0.0
    @State private var adjustments = PhotoAdjustments()
    @State private var tune = PhotoTune.exposure
    @State private var filterMode = 0
    @State private var curveChannel = 0
    @State private var selectedText: PhotoText?
    @State private var textStyle = PhotoTextStyle.outline
    @State private var textFont = PhotoFont.sans
    @State private var textAlignment = PhotoAlignment.left
    @State private var originalShown = false

    init(draft: AttachmentDraft, initialHistory: PhotoEditHistory = PhotoEditHistory(), onSave: @escaping (AttachmentDraft, PhotoEditHistory)->Void, onClose: @escaping ()->Void) {
        self.draft = draft; self.onSave = onSave; self.onClose = onClose
        _history = State(initialValue: initialHistory)
    }

    private var stagedText: PhotoText? {
        guard var value = selectedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        value.text = text.trimmingCharacters(in: .whitespacesAndNewlines); value.color = ink; value.size = fontSize
        value.style = textStyle; value.font = textFont; value.alignment = textAlignment
        return value
    }
    private var pending: [PhotoEdit] {
        var edits: [PhotoEdit] = []
        if tool == .filter && filterPreview { edits.append(.filter(filter,amount: amount)) }
        if tool == .filter && !adjustments.isDefault { edits.append(.adjust(adjustments)) }
        if tool == .rotate && angle != 0 { edits.append(.straighten(angle)) }
        if tool == .text, let stagedText, stagedText != selectedText { edits.append(.replaceText(stagedText)) }
        return edits
    }

    private var visibleEdits: [PhotoEdit] {
        PhotoEditHistory(edits: history.edits + pending).resolved
    }
    private var previewEdits: [PhotoEdit] { originalShown ? [] : visibleEdits }
    private var canEdit: Bool { renderer != nil && preview != nil && !busy && !rendering && !originalShown }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Отмена", action: onClose).disabled(busy)
                Spacer()
                Text("Редактор фото").font(.headline)
                Spacer()
                Button("Готово", action: finish).disabled(!canEdit)
            }.padding()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Button("Назад") { history.undo(); resetPending() }.disabled(history.edits.isEmpty || busy)
                    Button("Повторить") { history.redo(); resetPending() }.disabled(history.undone.isEmpty || busy)
                    Button("Сбросить") { history = PhotoEditHistory(); resetPending() }.disabled(busy)
                    Button(originalShown ? "Результат" : "Оригинал") { originalShown.toggle() }.disabled(busy)
                }.padding(.horizontal)
            }.padding(.bottom, 8)
            GeometryReader { proxy in
                ZStack {
                    Color.black
                    if let preview {
                        let ratio = preview.size.width / preview.size.height
                        let width = min(proxy.size.width, proxy.size.height * ratio)
                        let frame = CGSize(width: width, height: width / ratio)
                        Image(uiImage: preview).resizable().frame(width: frame.width, height: frame.height)
                            .overlay { canvas(frame) }
                            .contentShape(Rectangle())
                            .gesture(gesture(frame))
                    }
                    if renderer == nil || rendering || busy { ProgressView().tint(.white) }
                }
            }
            VStack(spacing: 8) {
                if let failure {
                    Text(failure).font(.footnote).foregroundStyle(.red)
                    Button("Закрыть сообщение") { self.failure = nil }
                }
                ScrollView { VStack(spacing: 8) { controls } }.frame(maxHeight: 230)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Tool.allCases, id: \.self) { item in
                            Button(item.rawValue) {
                                guard item != tool else { return }
                                for edit in pending { history.add(edit) }
                                if tool == .crop && crop != .full { history.add(.crop(crop)) }
                                resetPending(); tool = item; points = []
                            }
                                .buttonStyle(.bordered).tint(tool == item ? .accentColor : .secondary)
                                .disabled(busy)
                        }
                    }
                }
            }.padding(12)
        }
        .background(Color(uiColor: .systemBackground))
        .interactiveDismissDisabled(busy)
        .task {
            do {
                let loaded = try await PhotoRenderer.load(draft)
                renderer = loaded
                preview = try await loaded.preview(previewEdits).image
            } catch is CancellationError {} catch { failure = "Не удалось открыть фото" }
        }
        .task(id: previewEdits) {
            guard let renderer else { return }
            rendering = true
            defer { rendering = false }
            do {
                let rendered = try await renderer.preview(previewEdits)
                try Task.checkCancellation()
                preview = rendered.image
            } catch is CancellationError {} catch { failure = "Не удалось обработать фото. Отмените последнее действие и попробуйте снова." }
        }
    }

    private func canvas(_ frame: CGSize) -> some View {
        Canvas { context, size in
            if tool == .crop && !originalShown {
                let rect = CGRect(x: crop.left * size.width, y: crop.top * size.height, width: (crop.right - crop.left) * size.width, height: (crop.bottom - crop.top) * size.height)
                var mask = Path(CGRect(origin: .zero, size: size)); mask.addRect(rect)
                context.fill(mask, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
                context.stroke(Path(rect), with: .color(.white), lineWidth: 2)
                for p in [CGPoint(x: rect.minX,y: rect.minY),CGPoint(x: rect.maxX,y: rect.minY),CGPoint(x: rect.minX,y: rect.maxY),CGPoint(x: rect.maxX,y: rect.maxY)] {
                    context.fill(Path(ellipseIn: CGRect(x: p.x-4,y: p.y-4,width: 8,height: 8)),with: .color(.white))
                }
                var grid = Path()
                for i in 1...2 {
                    let x = rect.minX + rect.width * CGFloat(i) / 3, y = rect.minY + rect.height * CGFloat(i) / 3
                    grid.move(to: CGPoint(x: x, y: rect.minY)); grid.addLine(to: CGPoint(x: x, y: rect.maxY))
                    grid.move(to: CGPoint(x: rect.minX, y: y)); grid.addLine(to: CGPoint(x: rect.maxX, y: y))
                }
                context.stroke(grid, with: .color(.white.opacity(0.5)), lineWidth: 1)
            }
            if tool == .draw, let first = points.first {
                var path = Path(); path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
                for p in points.dropFirst() { path.addLine(to: CGPoint(x: p.x * size.width, y: p.y * size.height)) }
                let width = brush * min(size.width, size.height)
                if let shape, let rect = PhotoCrop.between(first,points.last!) {
                    let box = CGRect(x: rect.left*size.width,y: rect.top*size.height,width: (rect.right-rect.left)*size.width,height: (rect.bottom-rect.top)*size.height)
                    let outline = shape == .ellipse ? Path(ellipseIn: box) : Path(box)
                    context.stroke(outline,with: .color(color(ink)),lineWidth: width)
                } else {
                    let paint = brushTool == .eraser || brushTool == .blur ? Color.white.opacity(0.5) : color(ink).opacity(brushTool == .marker ? 0.4 : 1)
                    context.stroke(path, with: .color(paint), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                }
                if points.count == 1 {
                    context.fill(Path(ellipseIn: CGRect(x: first.x * size.width - width / 2, y: first.y * size.height - width / 2, width: width, height: width)), with: .color(color(ink)))
                }
            }
        }.frame(width: frame.width, height: frame.height)
    }

    private func gesture(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard canEdit else { return }
                let p = point(value.location, size)
                if tool == .draw {
                    if let last = points.last, abs(last.x - p.x) + abs(last.y - p.y) < 0.002 { return }
                    points.append(p)
                } else if tool == .crop {
                    if cropDrag == nil { cropDrag = PhotoCropDrag(rect: crop,start: point(value.startLocation,size),thresholdX: 24/size.width,thresholdY: 24/size.height) }
                    if let cropDrag { crop = cropDrag.update(p) }
                }
            }
            .onEnded { value in
                guard canEdit else { points = []; return }
                if tool == .draw, !points.isEmpty {
                    if let shape, let rect = PhotoCrop.between(points.first!,points.last!) { history.add(.shape(rect,shape: shape,color: ink,width: brush,filled: filled)) }
                    else if shape == nil { history.add(.stroke(points: brushTool == .arrow ? [points.first!,points.last!] : points,color: ink,width: brush,brush: brushTool)) }
                    points = []
                }
                cropDrag = nil
                if tool == .text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    placeText(point(value.location,size))
                }
            }
    }

    @ViewBuilder private var controls: some View {
        switch tool {
        case .crop:
            Text("Перетащите края или середину рамки").font(.caption)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Button("Весь кадр") { crop = .full }
                    ForEach([1.0, 4.0 / 3, 16.0 / 9], id: \.self) { ratio in
                        Button(ratio == 1 ? "1:1" : ratio < 1.5 ? "4:3" : "16:9") {
                            if let renderer { crop = .centered(history.size(renderer.size), ratio: ratio) }
                        }
                    }
                    Button("Обрезать") { history.add(.crop(crop)); crop = .full }.disabled(!canEdit || crop == .full)
                }.buttonStyle(.bordered).disabled(busy)
            }
        case .rotate:
            HStack {
                Button("↶ 90°") { angle = 0; history.add(.rotate(clockwise: false)); crop = .full }
                Button("↷ 90°") { angle = 0; history.add(.rotate(clockwise: true)); crop = .full }
                Button("Отразить") { history.add(.flip) }
            }.buttonStyle(.bordered).disabled(!canEdit)
            Text("Горизонт: \(Int(angle))°").font(.caption)
            Slider(value: $angle,in: -45...45).disabled(busy)
            Button("Применить") { history.add(.straighten(angle)); angle = 0 }.disabled(!canEdit || angle == 0)
        case .draw, .text:
            if tool == .text {
                choices(history.texts, selected: selectedText, title: { String($0.text.prefix(16)) }, select: selectText)
                TextField("Текст — затем коснитесь фото", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...2).disabled(busy)
                    .onChange(of: text) { _, value in if value.count > 200 { text = String(value.prefix(200)) } }
                choices(PhotoTextStyle.allCases,selected: textStyle,title: { $0.rawValue }) { textStyle = $0 }
                choices(PhotoFont.allCases,selected: textFont,title: { $0.rawValue }) { textFont = $0 }
                choices(PhotoAlignment.allCases,selected: textAlignment,title: { $0.rawValue }) { textAlignment = $0 }
                HStack {
                    Button("Новый текст") { if let stagedText { history.add(.replaceText(stagedText)) }; selectedText = nil; text = "" }
                    if let selectedText { Button("Удалить") { history.add(.removeText(selectedText.id)); self.selectedText = nil; text = "" } }
                }.disabled(busy)
                Text("Выберите надпись и перетащите её по фото").font(.caption)
            } else {
                choices(PhotoBrush.allCases,selected: shape == nil ? brushTool : nil,title: { $0.rawValue }) { brushTool = $0; shape = nil }
                choices(PhotoShape.allCases,selected: shape,title: { $0.rawValue }) { shape = $0 }
                if shape != nil { Toggle("Заливка",isOn: $filled) }
            }
            HStack(spacing: 10) {
                ForEach(colors, id: \.self) { rgb in
                    Button { ink = rgb } label: {
                        Circle().fill(color(rgb)).frame(width: 24, height: 24)
                            .overlay { Circle().stroke(ink == rgb ? Color.accentColor : .gray, lineWidth: ink == rgb ? 3 : 1) }
                    }.accessibilityLabel("Цвет \(rgb)")
                }
                if tool == .draw { Slider(value: $brush, in: 0.004...0.04).accessibilityLabel("Толщина кисти") }
                else { Slider(value: $fontSize, in: 0.035...0.15).accessibilityLabel("Размер текста") }
            }.disabled(busy)
            ColorPicker("Свой цвет",selection: Binding(get: { color(ink) },set: { value in
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                if UIColor(value).getRed(&r,green: &g,blue: &b,alpha: &a) {
                    ink = (UInt32((r*255).rounded())<<16) | (UInt32((g*255).rounded())<<8) | UInt32((b*255).rounded())
                }
            }),supportsOpacity: false).disabled(busy)
        case .filter:
            choices([0,1,2],selected: filterMode,title: { ["Пресеты","Настройки","Кривые"][$0] }) { filterMode = $0 }
            if filterMode == 0 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(PhotoFilter.allCases, id: \.self) { preset in
                        Button(preset.title) { filter = preset; filterPreview = true }
                            .buttonStyle(.bordered).tint(filterPreview && filter == preset ? .accentColor : .secondary)
                    }
                }
            }.disabled(busy)
            HStack {
                Slider(value: $amount, in: 0...1).onChange(of: amount) { _, _ in filterPreview = true }.accessibilityLabel("Сила фильтра")
                Button("Применить") { history.add(.filter(filter, amount: amount)); filterPreview = false }.disabled(!canEdit || !filterPreview)
            }.disabled(busy)
            } else if filterMode == 1 {
                choices(PhotoTune.allCases,selected: tune,title: { $0.rawValue }) { tune = $0 }
                Text("\(tune.rawValue): \(Int(adjustments[tune]*100))").font(.caption)
                Slider(value: Binding(get: { adjustments[tune] },set: { adjustments[tune] = $0 }),in: (tune.positive ? 0 : -1)...1).disabled(busy)
            } else {
                choices([0,1,2,3],selected: curveChannel,title: { ["Все","Красный","Зелёный","Синий"][$0] }) { curveChannel = $0 }
                curveEditor
            }
            if filterMode != 0 {
                HStack {
                    Button("Применить") { history.add(.adjust(adjustments)); adjustments = PhotoAdjustments() }.disabled(!canEdit || adjustments.isDefault)
                    Button("Сбросить настройки") { adjustments = PhotoAdjustments() }.disabled(busy)
                }
            }
        }
    }

    private func finish() {
        guard let renderer else { return }
        var finalHistory = PhotoEditHistory(edits: history.edits + pending)
        if tool == .crop && crop != .full { finalHistory.add(.crop(crop)) }
        if tool == .text && selectedText == nil && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finalHistory.add(.text(makeText(PhotoPoint(x: 0.1,y: 0.45))))
        }
        let edits = finalHistory.resolved
        let savedHistory = finalHistory
        busy = true
        Task {
            defer { busy = false }
            do { onSave(edits.isEmpty ? draft : try await renderer.export(edits),savedHistory) }
            catch { failure = "Не удалось сохранить фото. Попробуйте ещё раз." }
        }
    }
    private func resetPending() { filterPreview = false; adjustments = PhotoAdjustments(); angle = 0; selectedText = nil; text = ""; crop = .full; originalShown = false }
    private func selectText(_ value: PhotoText) { selectedText = value; text = value.text; ink = value.color; fontSize = value.size; textStyle = value.style; textFont = value.font; textAlignment = value.alignment }
    private func makeText(_ point: PhotoPoint) -> PhotoText {
        PhotoText(text: text.trimmingCharacters(in: .whitespacesAndNewlines),point: point,color: ink,size: fontSize,style: textStyle,font: textFont,alignment: textAlignment)
    }
    private func placeText(_ point: PhotoPoint) {
        if var selected = stagedText, let renderer {
            selected.point = history.textPoint(selected.id,displayed: point,original: renderer.size)
            history.add(.replaceText(selected)); selectText(selected)
        } else { let added = makeText(point); history.add(.text(added)); selectText(added) }
    }
    private func choices<T: Hashable>(_ items: [T], selected: T?, title: @escaping (T)->String, select: @escaping (T)->Void) -> some View {
        ScrollView(.horizontal,showsIndicators: false) {
            HStack { ForEach(items,id: \.self) { item in Button(title(item)) { select(item) }.buttonStyle(.bordered).tint(item == selected ? .accentColor : .secondary) } }
        }.disabled(busy)
    }
    private var curveEditor: some View {
        GeometryReader { proxy in
            Canvas { context,size in
                var grid = Path()
                for i in 1...3 { let n = CGFloat(i)/4; grid.move(to: CGPoint(x: size.width*n,y: 0)); grid.addLine(to: CGPoint(x: size.width*n,y: size.height)); grid.move(to: CGPoint(x: 0,y: size.height*n)); grid.addLine(to: CGPoint(x: size.width,y: size.height*n)) }
                context.stroke(grid,with: .color(.gray),lineWidth: 1)
                var path = Path()
                for (i,v) in adjustments.curves[curveChannel].enumerated() {
                    // Только CGFloat: смесь Double и CGFloat здесь неоднозначна для компилятора.
                    let x: CGFloat = size.width * CGFloat(i) / 4
                    let y: CGFloat = size.height * (1 - CGFloat(v))
                    let p = CGPoint(x: x, y: y)
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    context.fill(Path(ellipseIn: CGRect(x: p.x-5,y: p.y-5,width: 10,height: 10)),with: .color(.white))
                }
                context.stroke(path,with: .color(.white),lineWidth: 2)
            }.background(.black).gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard !busy else { return }
                let index = min(4,max(0,Int((value.location.x/proxy.size.width*4).rounded())))
                let y = Double(value.location.y / proxy.size.height)
                adjustments.curves[curveChannel][index] = min(1, max(0, 1 - y))
            })
        }.frame(height: 100)
    }
    private func point(_ p: CGPoint, _ size: CGSize) -> PhotoPoint { PhotoPoint(x: p.x / size.width, y: p.y / size.height) }
    private func color(_ rgb: UInt32) -> Color { Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255) }
}

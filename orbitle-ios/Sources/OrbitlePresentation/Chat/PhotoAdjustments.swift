import Foundation

public enum PhotoTune: String, CaseIterable, Sendable {
    case exposure = "Экспозиция", brightness = "Яркость", contrast = "Контраст", saturation = "Насыщенность", warmth = "Теплота"
    case shadows = "Тени", highlights = "Света", fade = "Выцветание", vignette = "Виньетка", grain = "Зерно", sharpen = "Резкость", blur = "Размытие"
    public var positive: Bool { [.fade,.vignette,.grain,.sharpen,.blur].contains(self) }
}

public struct PhotoAdjustments: Hashable, Sendable {
    public var values: [PhotoTune: Double] = [:]
    public var curves: [[Double]] = Array(repeating: [0,0.25,0.5,0.75,1], count: 4)
    public init() {}
    public subscript(_ key: PhotoTune) -> Double { get { values[key] ?? 0 } set { values[key] = newValue } }
    public var isDefault: Bool { values.values.allSatisfy { $0 == 0 } && curves == PhotoAdjustments().curves }
}

public struct PhotoColorProcessor: Sendable {
    let values: PhotoAdjustments
    let exposure: Double
    let curves: [[Double]]
    public init(_ values: PhotoAdjustments) {
        self.values = values; exposure = pow(2,values[.exposure]*2)
        curves = values.curves.map { points in (0..<256).map { i in
            let x = Double(i)/255*4, segment = min(3,Int(x)), t = x-Double(segment)
            let p0 = points[max(0,segment-1)], p1 = points[segment], p2 = points[segment+1], p3 = points[min(4,segment+2)]
            let m1 = segment == 0 ? p2-p1 : (p2-p0)/2, m2 = segment == 3 ? p2-p1 : (p3-p1)/2
            let a = (2*t*t*t-3*t*t+1)*p1 + (t*t*t-2*t*t+t)*m1
            let b = (-2*t*t*t+3*t*t)*p2 + (t*t*t-t*t)*m2
            return min(1,max(0,a+b))
        } }
    }
    public func pixel(_ argb: UInt32, x: Int, y: Int, width: Int, height: Int) -> UInt32 {
        var r = Double((argb >> 16)&255)/255*exposure + values[.brightness]*0.25
        var g = Double((argb >> 8)&255)/255*exposure + values[.brightness]*0.25
        var b = Double(argb&255)/255*exposure + values[.brightness]*0.25
        let l = min(1,max(0,0.299*r+0.587*g+0.114*b))
        let tone = values[.shadows]*(1-l)*(1-l)*0.35 + values[.highlights]*l*l*0.35
        let c = 1+values[.contrast]*0.75, sat = 1+values[.saturation]
        r = (l+(r-l)*sat+tone-0.5)*c+0.5+values[.warmth]*0.08
        g = (l+(g-l)*sat+tone-0.5)*c+0.5
        b = (l+(b-l)*sat+tone-0.5)*c+0.5-values[.warmth]*0.08
        let dx = (Double(x)+0.5)/Double(width)*2-1, dy = (Double(y)+0.5)/Double(height)*2-1
        let shade = 1-values[.vignette]*min(1,(dx*dx+dy*dy)/2)*0.8
        let seed = UInt32(truncatingIfNeeded: x) &* 374761393 &+ UInt32(truncatingIfNeeded: y) &* 668265263
        let noise = (Double((seed ^ (seed >> 13))&255)/255-0.5)*values[.grain]*0.18
        func channel(_ v: Double, _ i: Int) -> UInt32 {
            let colored = curves[i][Int((min(1,max(0,v))*255).rounded())]
            let curved = curves[0][Int((colored*255).rounded())]
            let faded = curved*(1-values[.fade]*0.35)+values[.fade]*0.15
            return UInt32(min(255,max(0,((faded*shade+noise)*255).rounded())))
        }
        return (argb & 0xff000000) | (channel(r,1)<<16) | (channel(g,2)<<8) | channel(b,3)
    }
}

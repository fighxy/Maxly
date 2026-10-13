import Foundation

/// Элементы интерфейса просмотра фото и видео: шапка, подпись, кнопки, полоса ролика.
///
/// Одиночное касание прячет и показывает их. У играющего ролика они уходят сами через
/// `autoHideDelay`; на паузе, в конце ролика и пока тянут полосу — видны.
public struct MediaViewerChrome: Equatable, Sendable {
    public private(set) var visible = true

    /// Через сколько секунд спрятать у играющего ролика.
    public static let autoHideDelay: TimeInterval = 3

    public init() {}

    public mutating func toggle() { visible.toggle() }

    public mutating func show() { visible = true }

    public mutating func hide() { visible = false }

    /// Ролик встал (пауза, конец, ошибка): элементы нужны, чтобы продолжить.
    public mutating func playbackStopped() { visible = true }

    /// Прятать ли элементы по таймеру: видны, ролик играет, полосу не тянут и меню закрыто.
    public func shouldAutoHide(playing: Bool, scrubbing: Bool, menuOpen: Bool) -> Bool {
        visible && playing && !scrubbing && !menuOpen
    }
}

/// Двойное касание у края ролика: −10 / +10 секунд, как в Telegram и YouTube. Касания
/// подряд в пределах `window` складываются: третье — уже 20 секунд.
public struct SeekTapAccumulator: Equatable, Sendable {
    public struct Seek: Equatable, Sendable {
        /// Куда перемотать, с.
        public let target: TimeInterval
        /// Сколько всего перемотано серией касаний, с (для подписи «20 с»).
        public let total: Int
        public let forward: Bool
    }

    public static let step: TimeInterval = 10
    /// Пауза между касаниями, после которой серия начинается заново.
    public static let window: TimeInterval = 0.8
    /// Какая доля ширины слева и справа — края для перемотки; середина — пауза.
    public static let edge: Double = 0.35

    private var last: TimeInterval?
    private var forward = true
    private var total = 0

    public init() {}

    /// Касание в точке `x` из ширины `width`: край — перемотка, середина — `nil`.
    public static func side(x: Double, width: Double) -> Bool? {
        guard width > 0 else { return nil }
        if x < width * edge { return false }
        if x > width * (1 - edge) { return true }
        return nil
    }

    public mutating func tap(forward: Bool, at now: TimeInterval, position: TimeInterval, duration: TimeInterval) -> Seek {
        if let last, now - last <= Self.window, forward == self.forward {
            total += Int(Self.step)
        } else {
            total = Int(Self.step)
        }
        last = now
        self.forward = forward
        let raw = position + (forward ? Self.step : -Self.step)
        let upper = duration > 0 ? duration : max(raw, 0)
        return Seek(target: min(max(0, raw), upper), total: total, forward: forward)
    }

    /// Серия кончилась: подпись «20 с» можно убрать.
    public func isActive(at now: TimeInterval) -> Bool {
        guard let last else { return false }
        return now - last <= Self.window
    }
}

/// Смахивание просмотра: закрыть или вернуть кадр на место, и как гаснет фон.
public enum MediaDismissRule {
    /// Закрыть, если увели больше чем на эту долю высоты экрана…
    public static let distanceFraction: Double = 0.15
    /// …или бросили быстрее этого (точек в секунду) хотя бы на `minimumFlick`.
    public static let flickVelocity: Double = 800
    public static let minimumFlick: Double = 40

    public static func shouldClose(offset: Double, velocity: Double, height: Double) -> Bool {
        let distance = abs(offset)
        guard height > 0 else { return distance > 120 }
        if distance > height * distanceFraction { return true }
        return distance > minimumFlick && abs(velocity) > flickVelocity && (velocity > 0) == (offset > 0)
    }

    /// Прозрачность чёрного фона: тускнеет по мере увода кадра, не ниже 0,2.
    public static func backgroundOpacity(offset: Double, height: Double) -> Double {
        guard height > 0 else { return 1 }
        return max(0.2, 1 - abs(offset) / height * 1.6)
    }
}

/// Скорость ролика: меню 0,5…2× и удержание — 2×.
public enum PlaybackSpeed {
    public static let options: [Double] = [0.5, 1, 1.25, 1.5, 2]
    public static let hold: Double = 2

    /// «1×», «1,5×», «0,5×».
    public static func label(_ rate: Double) -> String {
        let rounded = (rate * 100).rounded() / 100
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded).replacingOccurrences(of: ".", with: ",")
        return text + "×"
    }
}

/// Время ролика: «0:07», «12:45», «1:02:03»; оставшееся — с минусом.
public enum MediaTimeText {
    public static func clock(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "–:––" }
        let total = Int(max(0, seconds).rounded(.down))
        let hours = total / 3600
        let minutes = total / 60 % 60
        let secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }

    public static func remaining(position: TimeInterval, duration: TimeInterval) -> String {
        guard duration.isFinite, duration > 0 else { return "–:––" }
        return "-" + clock(max(0, duration - position))
    }

    /// Загрузка ролика: «37 %» или «12,4 из 48 МБ», когда известен размер.
    public static func download(fraction: Double, totalBytes: Int64? = nil) -> String {
        let clamped = min(1, max(0, fraction.isFinite ? fraction : 0))
        guard let totalBytes, totalBytes > 0 else { return "\(Int((clamped * 100).rounded())) %" }
        let total = Double(totalBytes) / 1_048_576
        return "\(megabytes(total * clamped)) из \(megabytes(total)) МБ"
    }

    private static func megabytes(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}

/// Полёт кадра между плиткой в ленте и просмотром: где кадр стоит в просмотре и где он в
/// промежуточный момент.
public enum MediaHeroGeometry {
    /// Кадр с отношением сторон [aspect] (ширина / высота), вписанный в [bounds] по центру.
    public static func fit(aspect: Double, in bounds: CGRect) -> CGRect {
        guard aspect > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        let width = min(bounds.width, bounds.height * aspect)
        let height = width / aspect
        return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
    }

    /// Рамка на доле пути [progress] от [from] (0) до [to] (1).
    public static func interpolate(from: CGRect, to: CGRect, progress: Double) -> CGRect {
        let t = min(1, max(0, progress))
        return CGRect(
            x: from.minX + (to.minX - from.minX) * t,
            y: from.minY + (to.minY - from.minY) * t,
            width: from.width + (to.width - from.width) * t,
            height: from.height + (to.height - from.height) * t
        )
    }

    /// Возвращаться в плитку, только если она видна на экране хоть наполовину: иначе кадр
    /// улетел бы за край, и лучше просто погасить просмотр.
    public static func canReturn(to source: CGRect, screen: CGRect) -> Bool {
        guard source.width > 1, source.height > 1 else { return false }
        let visible = source.intersection(screen)
        guard !visible.isNull else { return false }
        return visible.width * visible.height >= source.width * source.height / 2
    }
}

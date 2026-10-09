import Foundation

/// Разбор SDP и идентификаторов сервера звонков.
public enum CallSdp {
    /// Номера `a=ssrc:` по порядку, без повторов: их сервер ждёт в `accept-producer`.
    public static func ssrcs(in sdp: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for line in lines(sdp) where line.hasPrefix("a=ssrc:") {
            let number = line.dropFirst("a=ssrc:".count).prefix { $0.isNumber }
            guard !number.isEmpty, seen.insert(String(number)).inserted else { continue }
            result.append(String(number))
        }
        return result
    }

    /// Кандидаты прямо в SDP сервера (SFU не шлёт их отдельно) с `mid` первой секции.
    public static func candidates(in sdp: String) -> [IceCandidate] {
        let all = lines(sdp)
        guard let mid = all.first(where: { $0.hasPrefix("a=mid:") }).map({ String($0.dropFirst("a=mid:".count)) }) else { return [] }
        var seen = Set<String>()
        var result: [IceCandidate] = []
        for line in all where line.hasPrefix("a=candidate:") {
            let candidate = String(line.dropFirst(2))
            guard seen.insert(candidate).inserted else { continue }
            result.append(IceCandidate(sdp: candidate, sdpMid: mid, sdpMLineIndex: 0))
        }
        return result
    }

    /// `mid` видеосекций, которые сервер предлагает только на приём (`a=recvonly`): слоты под
    /// своё видео в SFU.
    public static func receiveOnlyVideoMids(in sdp: String) -> Set<String> {
        var mids = Set<String>()
        var kind: String?
        var mid: String?
        var receiveOnly = false
        func flush() {
            if kind == "video", receiveOnly, let mid { mids.insert(mid) }
        }
        for line in lines(sdp) {
            if line.hasPrefix("m=") {
                flush()
                kind = line.dropFirst(2).split(separator: " ").first.map(String.init)
                mid = nil
                receiveOnly = false
            } else if line.hasPrefix("a=mid:") {
                mid = String(line.dropFirst("a=mid:".count))
            } else if line == "a=recvonly" {
                receiveOnly = true
            }
        }
        flush()
        return mids
    }

    /// Подписывает свои видеодорожки так, как их ищет сервер: id дорожки в `a=msid` и
    /// `a=ssrc … msid/label` заменяется на `u<свой номер>:sCAMERA` или `:sSCREEN`.
    public static func label(_ sdp: String, names: [String: String]) -> String {
        guard !names.isEmpty else { return sdp }
        let separator = sdp.contains("\r\n") ? "\r\n" : "\n"
        let parts = sdp.components(separatedBy: separator)
        let labeled = parts.map { line -> String in
            if line.hasPrefix("a=msid:") {
                let fields = line.split(separator: " ", omittingEmptySubsequences: false)
                if fields.count == 2, let name = names[String(fields[1])] {
                    return "\(fields[0]) \(name)"
                }
            } else if line.hasPrefix("a=ssrc:") {
                let fields = line.split(separator: " ", omittingEmptySubsequences: false)
                if fields.count == 3, fields[1].hasPrefix("msid:"), let name = names[String(fields[2])] {
                    return "\(fields[0]) \(fields[1]) \(name)"
                }
                if fields.count == 2, fields[1].hasPrefix("label:"),
                   let name = names[String(fields[1].dropFirst("label:".count))] {
                    return "\(fields[0]) label:\(name)"
                }
            }
            return line
        }
        return labeled.joined(separator: separator)
    }

    /// Подписывает видео в секциях SFU с этими `mid` (слот своего видео) ключом `name`, какой бы
    /// id дорожки там ни стоял. Замена дорожки в отправителе SDP не меняет: в нём остаётся id
    /// дорожки, с которой слот согласовали (камера), а сервер ищет видео по подписи.
    public static func label(_ sdp: String, mids: Set<String>, as name: String) -> String {
        guard !mids.isEmpty else { return sdp }
        let separator = sdp.contains("\r\n") ? "\r\n" : "\n"
        var parts = sdp.components(separatedBy: separator)
        let starts = parts.indices.filter { parts[$0].hasPrefix("m=") }
        for (number, start) in starts.enumerated() {
            let end = number + 1 < starts.count ? starts[number + 1] : parts.count
            let section = start..<end
            guard let midLine = parts[section].first(where: { $0.hasPrefix("a=mid:") }),
                  mids.contains(String(midLine.dropFirst("a=mid:".count)))
            else { continue }
            for index in section {
                parts[index] = relabeled(parts[index], as: name)
            }
        }
        return parts.joined(separator: separator)
    }

    /// Строка `a=msid` или `a=ssrc … msid/label` с новым id дорожки; остальные — как есть.
    private static func relabeled(_ line: String, as name: String) -> String {
        let fields = line.split(separator: " ", omittingEmptySubsequences: false)
        if line.hasPrefix("a=msid:"), fields.count == 2 {
            return "\(fields[0]) \(name)"
        }
        if line.hasPrefix("a=ssrc:") {
            if fields.count == 3, fields[1].hasPrefix("msid:") {
                return "\(fields[0]) \(fields[1]) \(name)"
            }
            if fields.count == 2, fields[1].hasPrefix("label:") {
                return "\(fields[0]) label:\(name)"
            }
        }
        return line
    }

    /// Номер участника из `participantId`: число или строка вида `u123:d0` (`u` — пользователь,
    /// `g` — группа, `d` — номер устройства).
    public static func participantId(_ raw: JSONValue?) -> Int64? {
        switch raw {
        case .int(let value)?:
            return value
        case .double(let value)? where value.rounded() == value:
            return Int64(value)
        case .string(let text)?:
            for segment in text.split(separator: ":") where !segment.isEmpty {
                let head = segment.first!
                if head == "u" || head == "g" {
                    if let value = Int64(segment.dropFirst()) { return value }
                } else if head != "d", let value = Int64(segment) {
                    return value
                }
            }
            return nil
        default:
            return nil
        }
    }

    /// Чья видеодорожка и что в ней, по её id: `u123:sSCREEN` / `u123:sCAMERA`, слот SFU
    /// `video-pat-3`, `video-123` / `audio-123`.
    public static func owner(ofTrack id: String) -> TrackOwner {
        if id.hasPrefix("video-pat-"), let slot = Int(id.dropFirst("video-pat-".count)) {
            return TrackOwner(slot: slot)
        }
        if id.hasPrefix("u") {
            let parts = id.split(separator: ":")
            if let first = parts.first, let participant = Int64(first.dropFirst()) {
                let screen = parts.dropFirst().contains { $0 == "sSCREEN" }
                return TrackOwner(participant: participant, screen: screen)
            }
        }
        for prefix in ["video-", "audio-"] where id.count > prefix.count && id.hasPrefix(prefix) {
            if let participant = participantId(.string(String(id.dropFirst(prefix.count)))) {
                return TrackOwner(participant: participant)
            }
        }
        return TrackOwner()
    }

    /// Ключ видео участника в раскладке SFU.
    public static func layoutKey(participant: Int64, screen: Bool) -> String {
        "u\(participant):\(screen ? "sSCREEN" : "sCAMERA")"
    }

    private static func lines(_ sdp: String) -> [String] {
        sdp.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}

/// Хозяин дорожки: участник, слот SFU и экран ли это.
public struct TrackOwner: Hashable, Sendable {
    public var participant: Int64?
    public var slot: Int?
    public var screen = false

    public init(participant: Int64? = nil, slot: Int? = nil, screen: Bool = false) {
        self.participant = participant
        self.slot = slot
        self.screen = screen
    }
}

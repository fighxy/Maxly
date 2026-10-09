import Foundation
import Observation
import MaxlyDomain

/// Шапка настроек, редактирование профиля и настройки аккаунта из конфига сервера.
///
/// Переключатели меняются сразу и откатываются, если сервер отказал: так экран не ждёт сеть.
@MainActor
@Observable
public final class AccountSettingsModel {
    public private(set) var profile: MyProfile?
    public private(set) var settings: AccountSettings = .unknown
    /// Номер в шапке открыт кнопкой-глазом. Не сохраняется: при каждом входе номер скрыт.
    public var isPhoneRevealed = false
    /// Идёт загрузка или удаление фото.
    public private(set) var isUpdatingPhoto = false
    public private(set) var isSaving = false
    /// Когда сервер удалит профиль, если он назвал дату (ответ `PROFILE_DELETE`).
    public private(set) var deletionDate: Date?
    /// Последняя ошибка для алерта. Экран обнуляет её после показа.
    public var errorMessage: String?

    @ObservationIgnored private let repository: any AccountRepository
    @ObservationIgnored private var watch: Task<Void, Never>?

    public init(repository: any AccountRepository) {
        self.repository = repository
    }

    public func activate() async {
        watchSettings()
        await reloadProfile()
    }

    /// Подписка на конфиг без загрузки профиля. Чат читает быструю реакцию до открытия настроек.
    public func watchSettings() {
        guard watch == nil else { return }
        let stream = repository.settings()
        watch = Task { [weak self] in
            for await value in stream {
                guard let self else { return }
                self.settings = value
            }
        }
    }

    public func deactivate() {
        watch?.cancel()
        watch = nil
    }

    public func reloadProfile() async {
        do {
            profile = try await repository.profile()
        } catch {
            // Шапка остаётся с прежними данными или заглушкой, алерт тут не нужен.
            Log.warning(.settings, "Профиль не загрузился: \(error)")
        }
    }

    /// Номер для шапки: скрытый или открытый. Пусто, если номер неизвестен.
    public var headerPhone: String {
        guard let profile else { return "" }
        return isPhoneRevealed ? profile.formattedPhone : profile.maskedPhone
    }

    public var hasPhoto: Bool { profile?.hasPhoto ?? false }

    // MARK: Профиль

    /// `true`, если сервер сохранил. Имя обязательно.
    @discardableResult
    public func saveProfile(firstName: String, lastName: String, about: String) async -> Bool {
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty else {
            errorMessage = "Укажите имя"
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            profile = try await repository.updateProfile(
                firstName: first,
                lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                about: about.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            Log.info(.settings, "Профиль сохранён")
            return true
        } catch {
            errorMessage = error.message
            return false
        }
    }

    public func uploadPhoto(jpeg: Data) async {
        isUpdatingPhoto = true
        defer { isUpdatingPhoto = false }
        do {
            profile = try await repository.uploadAvatar(jpeg: jpeg)
            Log.info(.settings, "Фото профиля загружено: \(jpeg.count) байт")
        } catch {
            errorMessage = "Не удалось загрузить фото. \(error.message)"
        }
    }

    public func removePhoto() async {
        isUpdatingPhoto = true
        defer { isUpdatingPhoto = false }
        do {
            profile = try await repository.removeAvatar()
            Log.info(.settings, "Фото профиля удалено")
        } catch {
            errorMessage = "Не удалось удалить фото. \(error.message)"
        }
    }

    /// Запрос на удаление профиля. `true`, если сервер его принял.
    public func deleteAccount() async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            let when = try await repository.deleteAccount()
            deletionDate = when
            Log.info(.settings, "Профиль будет удалён\(when.map { " \($0)" } ?? "")")
            return true
        } catch {
            errorMessage = "Не удалось удалить профиль. \(error.message)"
            return false
        }
    }

    // MARK: Настройки конфига

    public func setPhonePrivacy(_ access: PrivacyAccess) async {
        await change(\.phonePrivacy, to: access) { try await $0.setPhonePrivacy(access) }
    }

    /// «Кто видит статус в сети»: `true` — никто, `false` — контакты.
    public func setOnlineHidden(_ hidden: Bool) async {
        await change(\.onlineHidden, to: hidden) { try await $0.setOnlineHidden(hidden) }
    }

    public func setSafeMode(_ enabled: Bool) async {
        await change(\.safeMode, to: enabled) { try await $0.setSafeMode(enabled) }
    }

    public func setInactiveTTL(_ ttl: InactiveTTL) async {
        await change(\.inactiveTTL, to: ttl) { try await $0.setInactiveTTL(ttl) }
    }

    /// Выбор эмодзи включает быструю реакцию. Пустую строку сервер не получает.
    public func setQuickReaction(_ emoji: String) async {
        let clean = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 32 else { return }
        let before = settings
        guard before.quickReaction != clean || !before.quickReactionEnabled else { return }
        settings.quickReaction = clean
        settings.quickReactionEnabled = true
        do {
            settings = try await repository.setQuickReaction(clean)
        } catch {
            settings.quickReaction = before.quickReaction
            settings.quickReactionEnabled = before.quickReactionEnabled
            errorMessage = "Не удалось сохранить настройку. \((error as? MaxlyError ?? .unknown).message)"
        }
    }

    private func change<Value: Equatable>(
        _ path: WritableKeyPath<AccountSettings, Value>,
        to value: Value,
        _ send: (any AccountRepository) async throws -> AccountSettings
    ) async {
        let before = settings
        guard before[keyPath: path] != value else { return }
        settings[keyPath: path] = value
        do {
            settings = try await send(repository)
        } catch {
            // Только своё поле: другое могло за это время прийти с сервера.
            settings[keyPath: path] = before[keyPath: path]
            errorMessage = "Не удалось сохранить настройку. \((error as? MaxlyError ?? .unknown).message)"
        }
    }
}

public extension MaxlyError {
    /// Текст для алерта.
    var message: String { errorDescription ?? "Что-то пошло не так" }
}

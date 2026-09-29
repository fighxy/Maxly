import Foundation
import Observation
import OrbitlDomain

@MainActor
@Observable
final class AuthViewModel {
    var phone = ""
    var code = ""
    var password = ""
    var firstName = ""
    var lastName = ""
    var step: AuthPhase = .signedOut
    var error: OrbitlError?
    var isBusy = false

    private let auth: any AuthService
    private var watch: Task<Void, Never>?

    init(auth: any AuthService) {
        self.auth = auth
    }

    func activate() {
        guard watch == nil else { return }
        watch = Task {
            for await phase in auth.phases() {
                step = phase
            }
        }
    }

    func requestCode() async {
        await run { try await auth.requestCode(phone: phone.trimmingCharacters(in: .whitespaces)) }
    }

    func resendCode() async {
        await run { try await auth.resendCode() }
    }

    func verify() async {
        await run { try await auth.verifyCode(code.trimmingCharacters(in: .whitespaces)) }
    }

    func submitPassword() async {
        await run { try await auth.submitPassword(password) }
    }

    func register() async {
        let name = firstName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            error = .rejected("Введите имя")
            return
        }
        await run { try await auth.register(firstName: name, lastName: lastName.trimmingCharacters(in: .whitespaces)) }
    }

    private func run(_ body: () async throws(OrbitlError) -> Void) async {
        error = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await body()
        } catch let failure {
            error = failure
        }
    }
}

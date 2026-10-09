import SwiftUI
import AVFoundation
import UIKit
import MaxlyDomain
import MaxlyPresentation

/// «Устройства»: сеансы аккаунта, завершение остальных и вход на новом устройстве по QR-коду.
struct DevicesView: View {
    @Bindable var model: DevicesModel
    @State private var confirmClose = false
    @State private var showsScanner = false
    @State private var scanned: String?
    @State private var cameraProblem: CameraAccess.Result?

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "laptopcomputer.and.iphone")
                        .font(.system(size: 44, weight: .regular))
                        .foregroundStyle(.tint)
                    Text("Устройства с MAX")
                        .font(.title3.weight(.semibold))
                    Text("Войдите на новых устройствах и управляйте сеансами")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            switch model.sessions {
            case .loading:
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            case .failed(let message):
                Section {
                    Text(message).foregroundStyle(.secondary)
                    Button("Повторить") { Task { await model.load() } }
                }
            case .loaded(let sessions):
                let current = sessions.filter(\.isCurrent)
                let others = sessions.filter { !$0.isCurrent }
                if !current.isEmpty {
                    Section("Этот сеанс") {
                        ForEach(current) { SessionRow(session: $0) }
                    }
                }
                if !others.isEmpty {
                    Section("Другие сеансы") {
                        ForEach(others) { SessionRow(session: $0) }
                    }
                }
            }

            if model.hasOtherSessions {
                Section {
                    Button(role: .destructive) {
                        confirmClose = true
                    } label: {
                        HStack {
                            Text("Завершить все сеансы, кроме текущего")
                            if model.isClosing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(model.isClosing)
                } footer: {
                    Text("На остальных устройствах нужно будет войти заново.")
                }
            }

            Section {
                Button {
                    Task {
                        let access = await CameraAccess.request()
                        if access == .granted { showsScanner = true } else { cameraProblem = access }
                    }
                } label: {
                    HStack {
                        Label("Войти по QR-коду", systemImage: "qrcode.viewfinder")
                        if model.isApproving {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(model.isApproving)
            } footer: {
                Text("Откройте web.max.ru или MAX на компьютере и отсканируйте QR-код входа.")
            }
        }
        .navigationTitle("Устройства")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
        .confirmationDialog("Завершить остальные сеансы?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Завершить", role: .destructive) { Task { await model.closeOthers() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Этот сеанс останется, на других устройствах MAX попросит войти снова.")
        }
        .fullScreenCover(isPresented: $showsScanner) {
            QRScannerSheet { value in
                showsScanner = false
                scanned = value
            }
        }
        .confirmationDialog(
            "Войти на другом устройстве?",
            isPresented: Binding(get: { scanned != nil }, set: { if !$0 { scanned = nil } }),
            titleVisibility: .visible
        ) {
            Button("Войти") {
                if let value = scanned { Task { await model.approve(scanned: value) } }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Подтверждайте вход, только если QR-код показан на вашем устройстве.\n\(scanned ?? "")")
        }
        .alert(
            model.errorMessage == nil ? (model.notice ?? "") : "Не получилось",
            isPresented: Binding(
                get: { model.errorMessage != nil || model.notice != nil },
                set: { if !$0 { model.errorMessage = nil; model.notice = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            if let error = model.errorMessage { Text(error) }
        }
        .alert(
            cameraProblem == .unavailable ? "Камера недоступна" : "Нет доступа к камере",
            isPresented: Binding(get: { cameraProblem != nil }, set: { if !$0 { cameraProblem = nil } })
        ) {
            if cameraProblem == .denied {
                Button("Открыть настройки") { CameraAccess.openSettings() }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(cameraProblem == .unavailable
                 ? "На этом устройстве нет камеры."
                 : "Разрешите Maxly доступ к камере в Настройках, чтобы сканировать QR-код.")
        }
    }
}

/// Строка сеанса: приложение, устройство, место и время последней активности.
private struct SessionRow: View {
    let session: DeviceSession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.body.weight(.medium))
                if !session.info.isEmpty, session.info != session.title {
                    Text(session.info)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let details {
                    Text(details)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var details: String? {
        var parts: [String] = []
        if !session.location.isEmpty { parts.append(session.location) }
        if session.isCurrent {
            parts.append("в сети")
        } else if let seen = session.lastSeen {
            parts.append(seen.formatted(.relative(presentation: .named)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var symbol: String {
        let text = "\(session.client) \(session.info)".lowercased()
        if text.contains("web") || text.contains("chrome") || text.contains("safari") || text.contains("firefox") { return "globe" }
        if text.contains("ipad") { return "ipad" }
        if text.contains("iphone") || text.contains("ios") || text.contains("android") { return "iphone" }
        if text.contains("mac") || text.contains("windows") || text.contains("linux") || text.contains("desktop") { return "desktopcomputer" }
        return "iphone"
    }
}

/// Полноэкранный сканер QR-кода с кнопкой «Отмена».
struct QRScannerSheet: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QRScannerView(onScan: onScan)
                .ignoresSafeArea()
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                        .frame(width: 250, height: 250)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottom) {
                    Text("Наведите камеру на QR-код входа")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.bottom, 48)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { dismiss() }
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

/// Камера с распознаванием QR (`AVCaptureMetadataOutput`). У SwiftUI своего сканера нет.
struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {
        controller.onScan = onScan
    }

    final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onScan: ((String) -> Void)?
        private let runner = CaptureRunner()
        private var session: AVCaptureSession { runner.session }
        private var preview: AVCaptureVideoPreviewLayer?
        private var delivered = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(layer)
            preview = layer
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            runner.start()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            runner.stop()
        }

        nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            let value = metadataObjects
                .compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
                .first { !$0.isEmpty }
            guard let value else { return }
            MainActor.assumeIsolated {
                guard !delivered else { return }
                delivered = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onScan?(value)
            }
        }
    }
}

/// Сеанс камеры запускается и останавливается не на главном потоке, как советует Apple.
/// Все обращения к нему идут через одну последовательную очередь.
private final class CaptureRunner: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.maxly.qr-scanner")

    func start() {
        queue.async { if !self.session.isRunning { self.session.startRunning() } }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }
}

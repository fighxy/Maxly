import SwiftUI
import OrbitlePresentation
import OrbitleUI

/// Первый шаг: страна, код страны и номер.
struct AuthPhoneStep: View {
    @Bindable var viewModel: AuthViewModel

    private enum Field: Hashable {
        case countryCode, number
    }

    @FocusState private var focus: Field?
    @State private var isPickingCountry = false

    var body: some View {
        AuthStepScroll {
            AuthWordmark()
            AuthHeader(
                title: "Телефон",
                subtitle: Text("Проверьте код страны и введите свой номер телефона.")
            )
            if viewModel.sessionExpired {
                Text("Сессия истекла. Войдите снова. Переписка на устройстве сохранится, пока вы сами не выйдете.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }
            form
                .padding(.top, 28)
            AuthPrimaryButton(
                title: "Продолжить",
                isEnabled: viewModel.canRequestCode,
                isBusy: viewModel.isBusy
            ) {
                await viewModel.requestCode()
            }
            .padding(.top, 24)
            AuthMessage(error: viewModel.errorMessage, hint: viewModel.phoneHint)
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPickingCountry) {
            CountryPickerView(selected: viewModel.country) { country in
                viewModel.selectCountry(country)
                focus = .number
            }
        }
        .onAppear { focus = .number }
        .onChange(of: viewModel.countryCode) {
            // Код набран до конца — курсор переходит в номер.
            if focus == .countryCode, viewModel.isCountryCodeComplete {
                focus = .number
            }
        }
    }

    private var form: some View {
        VStack(spacing: 0) {
            AuthFieldRow(showsTopDivider: true) {
                countryRow
            }
            AuthFieldRow {
                numberRow
            }
        }
    }

    private var countryRow: some View {
        Button {
            isPickingCountry = true
        } label: {
            HStack(spacing: 10) {
                if let country = viewModel.country {
                    Text(verbatim: country.flag)
                        .font(.title2)
                        .accessibilityHidden(true)
                }
                Text(viewModel.countryTitle)
                    .foregroundStyle(viewModel.country == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.body)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Страна: \(viewModel.countryTitle)")
        .accessibilityHint("Открывает список стран")
    }

    private var numberRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 1) {
                Text(verbatim: "+")
                TextField("", text: $viewModel.countryCode, prompt: Text(verbatim: "7"))
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    .focused($focus, equals: .countryCode)
                    .accessibilityLabel("Код страны")
            }
            .font(.body.monospacedDigit())
            .frame(width: 58, alignment: .leading)

            Divider()
                .frame(height: 30)

            TextField("", text: $viewModel.nationalNumber, prompt: Text(verbatim: viewModel.phonePlaceholder))
                .font(.body.monospacedDigit())
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .focused($focus, equals: .number)
                .accessibilityLabel("Номер телефона")
        }
    }
}

/// Выбор страны: системный список с поиском по названию и коду.
struct CountryPickerView: View {
    let selected: PhoneCountry?
    let onSelect: (PhoneCountry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let countries = PhoneCountry.search(query)
        NavigationStack {
            List(countries) { country in
                Button {
                    onSelect(country)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(verbatim: country.flag)
                            .font(.title2)
                            .accessibilityHidden(true)
                        Text(country.name)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Text(verbatim: "+\(country.code)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        if country == selected {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(country == selected ? .isSelected : [])
            }
            .listStyle(.plain)
            .overlay {
                if countries.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Страна")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Поиск")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
        .tint(Color.orbitleAccent)
    }
}

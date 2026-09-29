import SwiftUI
import Contacts
import OrbitlPresentation
import OrbitlUI

/// Вкладка «Контакты»: крупный заголовок, кнопки поиска и добавления (на iOS 26
/// система собирает их в стеклянную капсулу), плоское поле поиска, разделы по
/// буквам с алфавитным указателем справа.
struct ContactsView: View {
    @Bindable var viewModel: ContactsViewModel
    /// Открыть диалог с контактом.
    let onOpenChat: (String) -> Void

    @State private var isAdding = false
    @State private var showsAddUnavailable = false
    @State private var contactsAccess = CNContactStore.authorizationStatus(for: .contacts)
    @State private var isPickingContacts = false

    private static let searchRowId = "search"

    var body: some View {
        ScrollViewReader { proxy in
            List {
                FlatSearchField(text: $viewModel.query, isActive: $viewModel.isSearching)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .id(Self.searchRowId)
                if !viewModel.isFiltering {
                    ContactsAccessRow(status: contactsAccess) { isPickingContacts = true }
                }
                content
            }
            .listStyle(.plain)
            .orbitlSectionIndexVisible(showsIndex)
            .overlay(alignment: .trailing) {
                if showsIndex, !SectionIndexSupport.isNative {
                    SectionIndexStrip(titles: ContactsViewModel.indexTitles) { title in
                        if let id = viewModel.sectionId(forIndexTitle: title),
                           let first = viewModel.sections.first(where: { $0.id == id })?.rows.first {
                            proxy.scrollTo(first.id, anchor: .top)
                        }
                    }
                    .padding(.vertical, 24)
                    .padding(.trailing, 2)
                }
            }
            .animation(.default, value: viewModel.isFiltering)
            .navigationTitle("Контакты")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        withAnimation { proxy.scrollTo(Self.searchRowId, anchor: .top) }
                        viewModel.isSearching = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Поиск")
                    Button {
                        if viewModel.canAdd { isAdding = true } else { showsAddUnavailable = true }
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .accessibilityLabel("Добавить контакт")
                }
            }
        }
        .task { viewModel.activate() }
        .contactsAccess(status: $contactsAccess, isPickingMore: $isPickingContacts)
        .sheet(isPresented: $isAdding) {
            AddContactSheet(viewModel: viewModel)
        }
        .alert("Добавление контактов пока недоступно", isPresented: $showsAddUnavailable) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text("Эта версия Orbitl ещё не умеет добавлять контакты.")
        }
    }

    private var showsIndex: Bool {
        viewModel.state == .ready && !viewModel.isFiltering
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
                .listRowSeparator(.hidden)
        case .unavailable:
            placeholder(
                "Контакты пока недоступны",
                systemImage: "person.crop.circle.badge.questionmark",
                description: "Список появится, когда Orbitl научится получать его с сервера."
            )
        case .empty:
            placeholder(
                "Нет контактов",
                systemImage: "person.crop.circle",
                description: "Здесь появятся люди из вашей адресной книги в Max."
            )
        case .ready:
            if viewModel.isFiltering {
                searchResults
            } else {
                sections
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if viewModel.searchResults.isEmpty {
            ContentUnavailableView.search(text: viewModel.query)
                .listRowSeparator(.hidden)
                .padding(.top, 40)
        } else {
            ForEach(viewModel.searchResults) { row in
                contactButton(row)
            }
        }
    }

    private var sections: some View {
        ForEach(viewModel.sections) { section in
            Section {
                ForEach(section.rows) { row in
                    contactButton(row)
                }
            } header: {
                // У пустого раздела нет заголовка: он нужен только указателю.
                if !section.rows.isEmpty {
                    Text(section.title)
                }
            }
            .orbitlSectionIndexLabel(section.id)
        }
    }

    private func contactButton(_ row: ContactRow) -> some View {
        Button {
            if let chatId = viewModel.chatId(forContact: row.id) {
                onOpenChat(chatId)
            }
        } label: {
            ContactRowView(row: row)
        }
        .accessibilityLabel("\(row.title), \(row.status)")
    }

    private func placeholder(_ title: String, systemImage: String, description: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
            .padding(.top, 40)
            .listRowSeparator(.hidden)
    }
}

/// Строка контакта: аватар, имя, статус. Разделитель система выравнивает по тексту.
struct ContactRowView: View {
    let row: ContactRow

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(title: row.title, id: row.id, url: row.avatarURL, size: OrbitlTheme.smallAvatar, isOnline: row.isOnline)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(row.status)
                    .font(.subheadline)
                    .foregroundStyle(row.isOnline ? AnyShapeStyle(Color.orbitlAccent) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// Новый контакт по номеру телефона.
struct AddContactSheet: View {
    @Bindable var viewModel: ContactsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Имя", text: $firstName)
                        .textContentType(.givenName)
                    TextField("Фамилия (необязательно)", text: $lastName)
                        .textContentType(.familyName)
                }
                Section {
                    TextField("Номер телефона", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                } footer: {
                    if let error = viewModel.errorMessage {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Новый контакт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        viewModel.dismissError()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        Task {
                            isSaving = true
                            let added = await viewModel.addContact(phone: phone, firstName: firstName, lastName: lastName)
                            isSaving = false
                            if added { dismiss() }
                        }
                    }
                    .disabled(isSaving || firstName.trimmingCharacters(in: .whitespaces).isEmpty || phone.filter(\.isNumber).count < 7)
                }
            }
        }
        .tint(Color.orbitlAccent)
    }
}

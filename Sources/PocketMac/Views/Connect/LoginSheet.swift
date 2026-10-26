import SwiftUI

/// Mac username + password, and an address when adding a Mac by hand.
struct LoginSheet: View {
    let target: LoginTarget
    @ObservedObject var savedMacs: SavedMacStore
    let connect: (MacConnectionRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var port = "5900"
    @State private var username = ""
    @State private var password = ""
    @State private var rememberPassword = true
    @FocusState private var focusedField: Field?

    private enum Field { case host, username, password }

    var body: some View {
        NavigationStack {
            Form {
                if isManual {
                    Section {
                        TextField("192.168.1.20 or MacBook.local", text: $host)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .host)
                        TextField("Port", text: $port)
                            .keyboardType(.numberPad)
                    } header: {
                        Text("Mac address")
                    } footer: {
                        Text("Find it on your Mac under System Settings › General › Sharing › Screen Sharing.")
                    }
                }

                Section {
                    TextField("Mac username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                    SecureField("Mac password", text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(submit)
                } footer: {
                    Text("The account you log in to this Mac with. Your password is sent to the Mac encrypted and saved only in this iPhone's Keychain.")
                }

                Section {
                    Toggle("Remember Password", isOn: $rememberPassword)
                        .onChange(of: rememberPassword) { HapticsManager.selectionChanged() }
                }

                Section {
                    Button(action: submit) {
                        Text("Connect")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!canConnect)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        HapticsManager.tap()
                        dismiss()
                    }
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private var isManual: Bool {
        switch target {
        case .manual: return true
        case .saved(let mac): if case .host = mac.address { return true } else { return false }
        case .discovered: return false
        }
    }

    private var title: String {
        switch target {
        case .discovered(let mac): return mac.name
        case .saved(let mac): return mac.name
        case .manual: return "Add Mac"
        }
    }

    private var canConnect: Bool {
        !password.isEmpty && (!isManual || !host.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func prefill() {
        switch target {
        case .saved(let mac):
            username = mac.username
            password = savedMacs.password(for: mac) ?? ""
            if case .host(let savedHost, let savedPort) = mac.address {
                host = savedHost
                port = String(savedPort)
            }
            focusedField = password.isEmpty ? .password : nil
        case .manual:
            focusedField = .host
        case .discovered:
            focusedField = .username
        }
    }

    private func submit() {
        guard canConnect else { return }
        HapticsManager.appOpen()

        let address: SavedMac.Address
        let name: String
        switch target {
        case .discovered(let mac):
            address = .bonjour(serviceName: mac.name)
            name = mac.name
        case .saved(let mac) where !isManual:
            address = mac.address
            name = mac.name
        default:
            let trimmed = host.trimmingCharacters(in: .whitespaces)
            address = .host(trimmed, port: UInt16(port) ?? 5900)
            if case .saved(let mac) = target { name = mac.name } else { name = trimmed }
        }

        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        let saved = savedMacs.save(
            name: name, address: address, username: trimmedUsername,
            password: rememberPassword ? password : nil
        )
        connect(savedMacs.request(for: saved, password: password))
        dismiss()
    }
}

import SwiftUI
import TidyCore

struct GitHubSettings: View {
    @Environment(InboxStore.self) private var store
    @State private var isReplacing = false
    @State private var isConfirmingDisconnect = false

    var body: some View {
        Form {
            if let account = store.account, store.isSignedIn {
                Section {
                    HStack(spacing: 12) {
                        AsyncImage(url: account.user.avatarURL) { image in
                            image.resizable()
                        } placeholder: {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .foregroundStyle(.tertiary)
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(.circle)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.user.login)
                                .font(.headline)
                            Text(store.issue == .unauthorized ? "Token no longer valid" : "Connected")
                                .font(.callout)
                                .foregroundStyle(store.issue == .unauthorized ? .red : .secondary)
                        }
                        Spacer()
                        Button("Replace Token…") { isReplacing = true }
                            .disabled(isReplacing)
                        Button("Disconnect…") { isConfirmingDisconnect = true }
                    }
                    .padding(.vertical, 4)
                }
                Section("Token Scopes") {
                    ForEach(["notifications", "repo"], id: \.self) { scope in
                        let isGranted = account.scopes.contains(scope)
                        LabeledContent {
                            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(isGranted ? .green : .red)
                                .accessibilityLabel(isGranted ? "Granted" : "Missing")
                        } label: {
                            Text(scope).monospaced()
                            Text(scope == "repo" ? "Required: state, authors and security alerts" : "Reads your notifications")
                        }
                    }
                }
                .confirmationDialog("Disconnect GitHub?", isPresented: $isConfirmingDisconnect) {
                    Button("Disconnect", role: .destructive) {
                        isReplacing = false
                        store.disconnect()
                    }
                } message: {
                    Text("Tidy removes the token from your Keychain and clears the inbox, Done and muted threads on this Mac. Your filters stay.")
                }
            }
            if !store.isSignedIn || isReplacing || store.issue == .unauthorized || store.issue == .missingScope {
                TokenEntry(onConnect: { isReplacing = false })
            }
        }
        .formStyle(.grouped)
        .frame(height: 400)
    }
}

private struct TokenEntry: View {
    let onConnect: () -> Void
    @Environment(InboxStore.self) private var store
    @State private var token = ""
    @State private var error: String?
    @State private var isConnecting = false

    var body: some View {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let isFineGrained = trimmed.hasPrefix("github_pat_")
        let message = isFineGrained ? GitHubError.fineGrainedToken.message : error
        Section {
            SecureField("Personal access token (classic)", text: $token, prompt: Text("ghp_…"))
                .onChange(of: token) { error = nil }
                .onSubmit { connect(trimmed) }
            if let message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack(spacing: 8) {
                Link("Create Token…", destination: URL(string: "https://github.com/settings/tokens/new?scopes=notifications,repo&description=Tidy")!)
                Spacer()
                if isConnecting {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Connecting")
                }
                Button("Connect") { connect(trimmed) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty || isFineGrained || isConnecting)
            }
        } header: {
            Text(store.isSignedIn ? "Replace Token" : "Connect GitHub")
        } footer: {
            Text("Create a classic token with the notifications and repo scopes. Fine-grained tokens (github_pat_…) can't read notifications. Tidy keeps the token in your Keychain on this Mac only.")
        }
        #if DEBUG
        .onAppear { if SettingsSnapshot.scene == "fineGrained" { token = "github_pat_snapshot" } }
        #endif
    }

    private func connect(_ candidate: String) {
        guard !candidate.isEmpty, !candidate.hasPrefix("github_pat_"), !isConnecting else { return }
        isConnecting = true
        Task {
            defer { isConnecting = false }
            do {
                try await store.connect(token: candidate)
                token = ""
                onConnect()
            } catch {
                self.error = (error as? GitHubError)?.message ?? "Couldn't save the token to your Keychain."
            }
        }
    }
}

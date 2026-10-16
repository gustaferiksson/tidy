import SwiftUI
import TidyCore
import UserNotifications

struct NotificationSettings: View {
    @Environment(InboxStore.self) private var store
    @State private var authorization = UNAuthorizationStatus.notDetermined

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Button("Open System Settings…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")")!)
                    }
                } label: {
                    if authorization == .denied {
                        Label("Notifications are off", systemImage: "bell.slash")
                        Text("Turn on notifications for Tidy in System Settings to get banners.")
                    } else if authorization == .notDetermined {
                        Label("Not set up yet", systemImage: "bell")
                        Text("Tidy asks for permission after you connect GitHub.")
                    } else {
                        Label("Notifications are on", systemImage: "bell.badge")
                        Text("Choose the banner style and sound in System Settings.")
                    }
                }
            }
            Section {
                ForEach(ReasonGroup.allCases, id: \.self) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title)
                            .font(.headline)
                        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 8) {
                            ForEach(group.reasons, id: \.self) { reason in
                                Toggle(reason.title, isOn: Binding(
                                    get: { !store.silencedReasons.contains(reason) },
                                    set: { isOn in
                                        if isOn { store.silencedReasons.remove(reason) } else { store.silencedReasons.insert(reason) }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Notify For")
            } footer: {
                Text("Use Filters to quiet specific repositories, authors or states.")
            }
        }
        .formStyle(.grouped)
        .frame(height: 520)
        .task { authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
        }
    }
}

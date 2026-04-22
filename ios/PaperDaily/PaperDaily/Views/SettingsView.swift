import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: PaperStore
    @EnvironmentObject private var settings: UserSettingsStore

    @State private var reminderDate = Date()

    var body: some View {
        Form {
            Section("数据源") {
                TextField(UserSettingsStore.defaultFeedURLString, text: $settings.feedURLString)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled(true)
                Button("测试连接") {
                    Task {
                        await store.testConnection()
                    }
                }
                Button("立即刷新") {
                    Task {
                        await store.refresh()
                    }
                }
            }

            Section("提醒") {
                Toggle(
                    "每日提醒",
                    isOn: Binding(
                        get: { settings.notificationsEnabled },
                        set: { newValue in
                            Task {
                                await store.setNotifications(enabled: newValue)
                            }
                        }
                    )
                )
                DatePicker("提醒时间", selection: $reminderDate, displayedComponents: .hourAndMinute)
                    .onChange(of: reminderDate) { _, newValue in
                        Task {
                            await store.updateReminder(at: newValue)
                        }
                    }
                Toggle("默认只看未读", isOn: $settings.defaultUnreadOnly)
            }

            Section("缓存") {
                Button("清除缓存", role: .destructive) {
                    store.clearCache()
                }
            }

            Section("状态") {
                labeledValue("Schema Version", value: store.feed?.schemaVersion ?? "暂无")
                labeledValue("Feed 生成时间", value: store.generatedAtDescription)
                labeledValue("App 版本", value: settings.appVersionDescription)
                if let statusMessage = store.statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage = store.lastErrorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("设置")
        .task {
            reminderDate = settings.reminderDate
        }
    }

    private func labeledValue(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
        }
    }
}

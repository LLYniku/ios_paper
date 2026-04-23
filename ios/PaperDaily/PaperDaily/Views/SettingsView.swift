import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: PaperStore
    @EnvironmentObject private var settings: UserSettingsStore
    @EnvironmentObject private var syncStore: AppSyncStore

    @State private var reminderDate = Date()
    @State private var isEditingFeedConfig = false
    @State private var isEditingRemoteSync = false
    @FocusState private var focusedField: SyncField?

    private enum SyncField: Hashable {
        case syncURL
        case syncToken
    }

    var body: some View {
        Form {
            Section("数据源") {
                if settings.feedURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isEditingFeedConfig {
                    TextField(UserSettingsStore.defaultFeedURLString, text: $settings.feedURLString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled(true)
                } else {
                    configuredRow(title: "数据源地址", actionTitle: "编辑") {
                        isEditingFeedConfig = true
                    }
                }
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
                if isEditingFeedConfig {
                    Button("完成数据源编辑") {
                        focusedField = nil
                        isEditingFeedConfig = false
                    }
                    .buttonStyle(.bordered)
                }
            }

            Section("远端同步") {
                if settings.syncBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isEditingRemoteSync {
                    TextField("https://your-worker.workers.dev", text: $settings.syncBaseURLString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled(true)
                        .focused($focusedField, equals: .syncURL)
                        .submitLabel(.next)
                } else {
                    configuredRow(title: "远端同步网址", actionTitle: "编辑") {
                        isEditingRemoteSync = true
                    }
                }

                if settings.syncTokenString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isEditingRemoteSync {
                    SecureField("Sync Token", text: $settings.syncTokenString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .focused($focusedField, equals: .syncToken)
                        .submitLabel(.done)
                } else {
                    configuredRow(title: "Sync Token", actionTitle: "编辑") {
                        isEditingRemoteSync = true
                    }
                }

                if isEditingRemoteSync || !syncStore.remoteSyncEnabled {
                    Button("保存同步配置") {
                        focusedField = nil
                        settings.applyRemoteSyncInputs()
                        isEditingRemoteSync = false
                    }
                    .buttonStyle(.bordered)
                }

                HStack {
                    Button("推送本机") {
                        focusedField = nil
                        settings.applyRemoteSyncInputs()
                        syncStore.pushToRemote()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("拉取远端") {
                        focusedField = nil
                        settings.applyRemoteSyncInputs()
                        syncStore.refreshFromRemote()
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let remoteStatus = syncStore.remoteSyncStatus, !remoteStatus.isEmpty {
                    Text(remoteStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                labeledValue("同步状态", value: syncStatusText)
                Text("同步内容：收藏、已读、星级、收藏快照、最近打开和基础偏好。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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

            Section("最近打开") {
                if syncStore.recentOpenEntries.isEmpty {
                    Text("暂无跨设备同步记录。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(syncStore.recentOpenEntries.prefix(6))) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                                .font(.body.weight(.medium))
                            Text("\(entry.kind.title) · \(entry.subtitle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(FeedDisplay.dateTimeString(from: entry.openedAt))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .desktopReadableWidth(DesktopLayout.settingsMaxWidth)
        .navigationTitle("设置")
        .task {
            reminderDate = settings.reminderDate
            settings.applyRemoteSyncInputs()
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

    private func configuredRow(title: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("已配置")
            }
            Spacer()
            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
        }
    }

    private var syncStatusText: String {
        if syncStore.cloudSyncEnabled, syncStore.cloudAccountAvailable {
            return "iCloud 私有同步已启用"
        }
        if syncStore.remoteSyncEnabled {
            return "Cloudflare 远端同步已配置"
        }
        if syncStore.cloudSyncEnabled {
            return "已接入 iCloud；待系统账号可用后自动同步"
        }
        return "当前为本地统一状态；跨设备自动同步受当前个人签名限制"
    }
}

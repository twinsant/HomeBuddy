//
//  SettingsView.swift
//  HomeBuddy
//

import AppKit
import SwiftUI

struct SettingsView: View {
    @State private var storageDirectory: URL?
    @State private var pendingDirectory: URL?
    @State private var isConfirmingOverwrite = false
    @State private var isShowingError = false
    @State private var errorMessage = ""
    @State private var statusMessage = ""

    var body: some View {
        Form {
            Section("照片元数据") {
                LabeledContent("SQLite 存储目录") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(storageDirectory?.path ?? "未配置")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)

                        Button("选择目录…") {
                            chooseStorageDirectory()
                        }
                    }
                }

                Text("照片信息会缓存到该目录下的 photo-metadata.sqlite 文件中。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("通过目录选择器确认后，HomeBuddy 才能获得该目录的访问权限。隐藏目录（例如 ~/.homebuddy）也可以选择。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560, height: 190)
        .onAppear {
            storageDirectory = PhotoMetadataCache.shared.storageDirectoryURL
        }
        .alert("目标目录已有数据库", isPresented: $isConfirmingOverwrite) {
            Button("取消", role: .cancel) {
                pendingDirectory = nil
            }
            Button("覆盖并复制", role: .destructive) {
                if let pendingDirectory {
                    migrateDatabase(to: pendingDirectory, overwriting: true)
                }
                self.pendingDirectory = nil
            }
        } message: {
            Text("目标目录中已存在 photo-metadata.sqlite。覆盖后目标目录中的缓存将被当前缓存替换。")
        }
        .alert("无法切换存储目录", isPresented: $isShowingError) {
            Button("好", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func chooseStorageDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择照片元数据存储目录"
        panel.message = "选择目录即授予 HomeBuddy 对该目录的读写权限。"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = storageDirectory

        guard panel.runModal() == .OK, let directory = panel.url else { return }
        prepareToChangeDirectory(directory)
    }

    private func prepareToChangeDirectory(_ directory: URL) {
        let directory = directory.standardizedFileURL
        let resolvedDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
        let currentDirectory = storageDirectory?.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedDirectory != currentDirectory else {
            statusMessage = "当前已经使用该目录。"
            return
        }

        let databaseURL = directory.appendingPathComponent("photo-metadata.sqlite")
        if FileManager.default.fileExists(atPath: databaseURL.path) {
            pendingDirectory = directory
            isConfirmingOverwrite = true
        } else {
            migrateDatabase(to: directory, overwriting: false)
        }
    }

    private func migrateDatabase(to directory: URL, overwriting: Bool) {
        guard PhotoMetadataCache.shared.copyDatabase(to: directory, overwriting: overwriting) else {
            errorMessage = "数据库复制失败，当前存储目录未改变。请确认目标目录可写。"
            isShowingError = true
            return
        }

        storageDirectory = PhotoMetadataCache.shared.setStorageDirectory(directory)
        statusMessage = "数据库已复制并切换到：\(storageDirectory?.path ?? directory.path)"
    }
}

#Preview {
    SettingsView()
}

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
    @State private var ollamaBaseURL = OllamaConfiguration.defaultBaseURL
    @State private var ollamaModel = OllamaConfiguration.defaultModel
    @State private var ollamaModels: [String] = []
    @State private var isLoadingOllamaModels = false

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

            Section("Ollama 图片识别") {
                TextField("服务地址", text: $ollamaBaseURL)
                TextField("模型名称", text: $ollamaModel)

                HStack {
                    if isLoadingOllamaModels {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在读取已安装模型…")
                    } else if ollamaModels.isEmpty {
                        Text("未读取到模型，请确认 Ollama 已启动。")
                    } else {
                        Text("已找到 \(ollamaModels.count) 个模型。请选择支持图片输入的模型。")
                    }
                    Spacer()
                    Button {
                        refreshOllamaModels()
                    } label: {
                        Label("刷新模型", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoadingOllamaModels)
                    Button("保存") {
                        OllamaConfiguration(baseURL: ollamaBaseURL, model: ollamaModel).save()
                        statusMessage = "Ollama 配置已保存。"
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !ollamaModels.isEmpty {
                    Picker("已安装模型", selection: $ollamaModel) {
                        ForEach(ollamaModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }

                Text("默认使用本机 Ollama 服务。模型名称也可以手动输入。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560, height: 330)
        .onAppear {
            storageDirectory = PhotoMetadataCache.shared.storageDirectoryURL
            let configuration = OllamaConfiguration.current
            ollamaBaseURL = configuration.baseURL
            ollamaModel = configuration.model
            refreshOllamaModels()
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

    private func refreshOllamaModels() {
        let configuration = OllamaConfiguration(baseURL: ollamaBaseURL, model: ollamaModel)
        isLoadingOllamaModels = true

        Task {
            do {
                ollamaModels = try await OllamaVisionService.shared.availableModels(configuration: configuration)
                if ollamaModels.contains(configuration.model) == false, let firstModel = ollamaModels.first {
                    ollamaModel = firstModel
                }
            } catch {
                ollamaModels = []
                statusMessage = error.localizedDescription
            }
            isLoadingOllamaModels = false
        }
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

//
//  SettingsView.swift
//  HomeBuddy
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var chromaBaseURL = ChromaConfiguration.defaultBaseURL
    @State private var chromaTenant = ChromaConfiguration.defaultTenant
    @State private var chromaDatabase = ChromaConfiguration.defaultDatabase
    @State private var chromaCollection = ChromaConfiguration.defaultCollection
    @State private var isTestingChroma = false
    @State private var chromaStatusMessage = ""
    @State private var faceModelPath = FaceRecognitionConfiguration.modelPath
    @State private var faceModelStatusMessage = ""

    var body: some View {
        Form {
            Section("照片数据库") {
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

                Text("照片缓存、磁盘目录访问书签及图片索引保存在 photo-metadata.sqlite 中；原图不会存入数据库。")
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

            Section("本地人脸识别") {
                LabeledContent("GGUF 模型") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(faceModelPath ?? "未配置")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                        HStack {
                            Button("选择模型…", action: chooseFaceModel)
                            if faceModelPath != nil {
                                Button("移除", role: .destructive, action: clearFaceModel)
                            }
                        }
                    }
                }
                Text("选择 face-detect.cpp 兼容的 antelopev2.gguf。模型通过安全书签访问；该预训练权重仅限非商业用途。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !faceModelStatusMessage.isEmpty {
                    Text(faceModelStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Chroma 向量数据库") {
                TextField("服务地址", text: $chromaBaseURL)
                TextField("Tenant", text: $chromaTenant)
                TextField("Database", text: $chromaDatabase)
                TextField("Collection", text: $chromaCollection)

                HStack {
                    Text("本机 Chroma HTTP 服务用于保存已确认人物的人脸 embedding，并查询待确认的候选人物。")
                    Spacer()
                    Button {
                        testChromaConnection()
                    } label: {
                        if isTestingChroma {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("测试连接", systemImage: "bolt.horizontal")
                        }
                    }
                    .disabled(isTestingChroma)
                    Button("保存") {
                        saveChromaConfiguration()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !chromaStatusMessage.isEmpty {
                    Text(chromaStatusMessage)
                        .font(.caption)
                        .foregroundStyle(chromaStatusMessage == "Chroma v2 连接成功。" ? .green : .red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 600, height: 620)
        .onAppear {
            storageDirectory = PhotoMetadataCache.shared.storageDirectoryURL
            let configuration = OllamaConfiguration.current
            ollamaBaseURL = configuration.baseURL
            ollamaModel = configuration.model
            let chromaConfiguration = ChromaConfiguration.current
            chromaBaseURL = chromaConfiguration.baseURL
            chromaTenant = chromaConfiguration.tenant
            chromaDatabase = chromaConfiguration.database
            chromaCollection = chromaConfiguration.collection
            faceModelPath = FaceRecognitionConfiguration.modelPath
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
            Text("目标目录中已存在 photo-metadata.sqlite。覆盖后，该数据库的照片缓存、人物标注、磁盘目录及图片索引都将被当前数据库替换。原图不受影响。")
        }
        .alert("无法切换存储目录", isPresented: $isShowingError) {
            Button("好", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func chooseStorageDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择照片数据库存储目录"
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

    private func saveChromaConfiguration() {
        ChromaConfiguration(
            baseURL: chromaBaseURL,
            tenant: chromaTenant,
            database: chromaDatabase,
            collection: chromaCollection
        ).save()
        chromaStatusMessage = "Chroma 配置已保存。"
    }

    private func chooseFaceModel() {
        let panel = NSOpenPanel()
        panel.title = "选择 face-detect GGUF 模型"
        panel.prompt = "选择"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try FaceRecognitionConfiguration.saveModelURL(url)
            faceModelPath = url.path
            faceModelStatusMessage = "模型路径已保存。打开大图后可执行人脸识别。"
        } catch {
            faceModelStatusMessage = "无法保存模型访问权限：\(error.localizedDescription)"
        }
    }

    private func clearFaceModel() {
        FaceRecognitionConfiguration.clearModelURL()
        faceModelPath = nil
        faceModelStatusMessage = "模型配置已移除。"
    }

    private func testChromaConnection() {
        let configuration = ChromaConfiguration(
            baseURL: chromaBaseURL,
            tenant: chromaTenant,
            database: chromaDatabase,
            collection: chromaCollection
        )
        isTestingChroma = true

        Task {
            do {
                try await ChromaService.shared.checkConnection(configuration: configuration)
                chromaStatusMessage = "Chroma v2 连接成功。"
            } catch {
                chromaStatusMessage = error.localizedDescription
            }
            isTestingChroma = false
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

# HomeBuddy

HomeBuddy 是一款 macOS 照片整理工具：浏览系统照片图库、缓存照片元数据、进行本地人脸检测与人物标注，并可选择使用 Ollama 对照片进行视觉描述。

> 当前项目处于开发阶段。发布公开仓库或分发应用前，请阅读 [安全与隐私审计](doc/security-privacy-audit-2026-09-24.md)。

## 功能

- 浏览系统照片图库、智能相册和用户相册。
- 查看照片尺寸、格式、拍摄时间、相机、镜头、曝光、ISO、焦距等元数据。
- 将照片元数据和 Ollama 识别文字缓存到 SQLite。
- 使用 `face-detect.cpp` 兼容的 `antelopev2.gguf` 模型在本地检测人脸并生成 embedding。
- 创建人物名称，将已确认的人脸向量保存到 Chroma，并查询可能的人物候选。
- 使用 Ollama 视觉模型单张或批量识别照片，并按识别文字搜索照片。
- 通过 macOS 安全书签访问用户选择的模型文件和 SQLite 存储目录。

## 系统要求

- macOS 26.5 或更高版本
- Xcode 27 或更高版本
- Swift 5
- 照片图库访问权限
- 本地人脸识别：`face-detect.cpp` 兼容的 `antelopev2.gguf` 模型
- 可选图片描述：已运行的 [Ollama](https://ollama.com/)，以及支持图片输入的视觉模型
- 可选人物向量索引：已运行的 [Chroma](https://www.trychroma.com/) HTTP 服务

应用当前没有独立的包管理器依赖；原生依赖以 `HomeBuddy/Native/lib/` 中的静态库形式提交。发布工具使用 Bundler 管理 fastlane。

## 构建和运行

1. 克隆仓库并用 Xcode 打开 `HomeBuddy.xcodeproj`。
2. 选择 `HomeBuddy` scheme 和本机 macOS 目标。
3. 在 Xcode 中执行 Build 或 Run。
4. 首次运行时，在系统设置中授予照片图库权限。
5. 打开应用设置，选择 `antelopev2.gguf` 模型文件。
6. 如需 Ollama，确认服务已启动，在设置中选择视觉模型并保存地址。
7. 如需 Chroma，启动 Chroma HTTP 服务，在设置中配置 Tenant、Database 和 Collection，并测试连接。

默认服务地址：

- Ollama：`http://127.0.0.1:11434`
- Chroma：`http://localhost:8000`

项目允许手动填写服务地址。将服务配置为远端时，应使用 HTTPS、认证和受限网络访问；当前客户端不会自动替你完成这些安全措施。

## Mac App Store 发布

已提供 fastlane 的 `mac test`、`mac build` 和 `mac upload` 流程。签名、环境变量、命令及提交前检查见 [Mac App Store 发布指南](doc/mac-app-store-release.md)。上传不会自动提交审核或发布。

## 数据和隐私

- 照片原图默认从系统照片图库读取，不由 HomeBuddy 自动复制到仓库目录。
- 元数据、人物名称、人脸框和 Ollama 识别文字会写入 SQLite 缓存。默认缓存目录为 `~/.homebuddy/photo-metadata.sqlite`，无法使用时会尝试 macOS Application Support 目录；也可以在设置中选择其他目录。
- Ollama 图片识别会把照片数据发送到设置中的 Ollama 地址。默认地址是本机回环地址，但用户可以改为远端地址。
- Chroma 会接收人脸 embedding；已确认的人脸记录还会包含照片标识、人物 ID、人物名称和模型 ID。
- 仅配置本地人脸模型不会自动把模型文件复制到仓库；模型通过安全书签访问。
- 删除本地缓存不会自动保证远端 Chroma 数据已经删除。当前数据删除和同步能力仍在完善中。

请不要将真实照片、SQLite 数据库、模型权重或个人配置提交到 Git。公开仓库前请检查完整 Git 历史，而不只是当前工作区。

## 权限

应用启用 App Sandbox、Hardened Runtime、照片图库访问，以及用户选择文件的读写权限。首次访问照片和用户选择的模型或存储目录时，macOS 会显示相应的授权提示。

## 第三方组件和许可证

仓库内原生静态库及其许可证位于 `HomeBuddy/Native/`。当前目录包含 `face-detect.cpp`、ggml 和 libjpeg-turbo 相关文件及许可证。发布前请核对每个静态库、模型权重和 Ollama 模型的版本、来源、许可证及用途限制。

应用界面提示 `antelopev2.gguf` 预训练权重仅限非商业用途。请以模型发布者提供的最新许可证为准。

## 测试

在项目目录执行：

```sh
xcodebuild test -project HomeBuddy.xcodeproj -scheme HomeBuddy -destination 'platform=macOS'
```

具体可用的 macOS 模拟或运行目标取决于本机 Xcode 安装和版本。

## 已知限制

- Ollama 和 Chroma 配置支持任意用户输入的 URL；远端 HTTPS 和认证需要部署者自行保证。
- 当前版本没有完整的本地缓存清除、远端向量删除重试和照片删除同步机制。
- 原生静态库包含构建产物，升级依赖时需要同步更新来源、许可证和构建说明。

## 贡献

提交 Issue 或 Pull Request 时，请避免附加真实照片、数据库、模型文件、日志中的个人信息和服务凭证。安全问题请不要直接公开发布可利用细节，优先通过私下渠道联系维护者。

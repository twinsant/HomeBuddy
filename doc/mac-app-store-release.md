# Mac App Store 发布准备

本配置只提供测试、签名归档和上传二进制的自动化，**不代表应用已经符合上架要求**。不自动创建商店条目、不上传文案/截图、不提交审核、不自动发布，也不执行 Developer ID 公证流程。

## 1. 工具与环境

- 使用完整 Xcode，并确保其支持项目的 macOS 26.5 部署目标；首次启动 Xcode 完成组件安装与许可确认。
- 使用受维护的 Ruby（Gemfile 最低要求 3.2，推荐与开发机一致的版本），不要使用 macOS 自带 Ruby 2.6，也不要 `sudo gem install`。
- 安装 Bundler，随后在仓库根目录执行 `bundle install`。提交 `Gemfile.lock`；升级 fastlane 后重新验证签名导出和上传。
- 当前 lockfile 的 `BUNDLED WITH` 记录生成时的 Bundler 版本；可通过 `gem install bundler -v 4.0.16` 安装匹配版本（需兼容的 Ruby）。

例如使用 Homebrew Ruby 时，先把 `/opt/homebrew/opt/ruby/bin` 加入 PATH；Intel Mac 的 Homebrew 前缀通常是 `/usr/local`。

以下命令均在仓库根目录执行：

```sh
cp fastlane/.env.example fastlane/.env
bundle install
bundle exec fastlane lanes
```

编辑 `fastlane/.env` 中的 `APPLE_TEAM_ID`、`BUILD_NUMBER` 和可选 `APP_VERSION`。fastlane 自动读取该文件；CI 可以直接注入同名环境变量。不要把真实 `.env`、API 私钥、证书或描述文件提交到 Git。

## 2. Apple 账号与签名

1. 准备有效的 Apple Developer Program 会员资格，完成 App Store Connect 的协议及适用的税务/银行资料。
2. 为 `com.twinsant.HomeBuddy` 注册明确的 App ID，在 App Store Connect 创建 **macOS** 应用条目；Bundle ID 必须与项目及 `fastlane/Appfile`、`Fastfile` 一致。
3. `APPLE_TEAM_ID` 使用开发者门户中的 10 位团队 ID，不是 App Store Connect 的数字团队 ID。
4. 在 Xcode 登录所属团队，准备可用的 Mac App Store 应用分发证书、安装包分发证书（Mac Installer Distribution）及相应 provisioning profile；证书必须附带私钥并在已解锁的钥匙串中。不要使用 Developer ID Application/Installer 替代商店签名。
5. 当前流程沿用项目的 Automatic signing。默认不允许自动申请或更新签名资源；需要时显式设置 `ALLOW_PROVISIONING_UPDATES=true`，并确保 Xcode 已登录有权限的账号。上传 API Key 不会自动安装证书，也不等价于 Xcode 签名登录；CI 需要单独安全导入证书、描述文件并配置钥匙串。
6. 在干净检出/CI 使用前，确认 `HomeBuddy` scheme 可被命令行发现并包含测试和 Release Archive 配置。当前 Xcode 将其报告为 Shared，但仓库没有实体 `.xcscheme` 文件；建议在 Xcode 的 Manage Schemes 中保存共享 scheme，并提交 `HomeBuddy.xcodeproj/xcshareddata/xcschemes/`，不要依赖 `xcuserdata` 或自动生成状态。

## 3. 测试、打包、上传

```sh
# 只运行本机 macOS 测试，不上传
bundle exec fastlane mac test

# 干净构建 Release，归档并导出商店签名安装包，不上传
bundle exec fastlane mac build

# 在本地验收且确认所选产物后，显式上传该 pkg
bundle exec fastlane mac upload pkg:build/mac-app-store/HomeBuddy.pkg
```

输出：`build/mac-app-store/HomeBuddy.xcarchive`、`HomeBuddy.pkg` 和 `logs/`；测试报告在 `build/test-results/`。这些目录被 Git 忽略。再次构建会覆盖同名产物，请在发布时将 `.xcarchive`、`.pkg`、dSYM、日志和源码提交号安全留存于仓库外。

`BUILD_NUMBER` 必填且为正整数，每次上传必须使用新的递增值；`APP_VERSION` 留空则使用项目版本。两者仅通过 archive 命令行覆盖，不修改项目文件或 Info.plist。导出时关闭 Xcode 自动管理版本号。归档使用标准架构而非仅本机架构；当前原生静态库包含 arm64 和 x86_64，发布前仍须验收两种架构。fastlane 当前使用 `app-store` 导出方法名，后续升级 fastlane/Xcode 时需复核兼容性。

上传 lane 只上传显式传入的已存在 `.pkg`，不会重新构建或隐式选择目录中“最新”文件。可以检查签名：

```sh
pkgutil --check-signature build/mac-app-store/HomeBuddy.pkg
codesign --verify --deep --strict --verbose=2 build/mac-app-store/HomeBuddy.xcarchive/Products/Applications/HomeBuddy.app
codesign -d --entitlements :- build/mac-app-store/HomeBuddy.xcarchive/Products/Applications/HomeBuddy.app
```

上传前在 `fastlane/.env` 或 CI secrets 中设置团队级 App Store Connect API Key：

- `ASC_KEY_ID`：密钥 ID。
- `ASC_ISSUER_ID`：Issuer ID；本流程使用团队密钥，不支持无 issuer 的个人密钥。
- `ASC_KEY_FILEPATH`：`.p8` 私钥路径，推荐仓库外的绝对路径；相对路径基于仓库根目录解析。

为密钥授予上传本应用所需的最小角色权限。上传不会覆盖商店文案、截图或版本资料；完成后到 App Store Connect 等待处理、核对构建和版本信息、填写合规资料，再手动选择构建并提交审核。上传成功不等于处理或审核成功。

## 4. 商店文案与截图

商店页内容不写在 App Store Connect 网页里，写在这个仓库里，由 fastlane 推上去。

```
fastlane/metadata/en-US/        名称、副标题、关键词、描述、促销文字、发布说明、三个 URL、版权
fastlane/metadata/zh-Hans/      同一套中文
fastlane/metadata/review_information/notes.txt   审核备注
fastlane/screenshots/en-US/     截图（目前为空，规格见 screenshots/README.md）
fastlane/screenshots/zh-Hans/
```

文案定稿见 [Mac App Store ASO](aso-mac-app-store.md)，改文案改这里的数据文件，两边要一致。

```sh
# 只做本地校验：字符上限、缺文件，不联网
bundle exec fastlane mac check_metadata

# 只推文案，不动二进制和截图
bundle exec fastlane mac metadata

# 只推截图
bundle exec fastlane mac screenshots

# 只推二进制（原有流程，跳过文案和截图）
bundle exec fastlane mac upload pkg:build/mac-app-store/HomeBuddy.pkg
```

**前置条件**：App Store Connect 里必须已经有一个可编辑状态的版本（Prepare for Submission）。三个 lane 都带 `skip_app_version_update: true`，不会替你创建版本，没有可编辑版本时推送会失败。

**API Key 角色**：上传二进制和修改商店文案都要求密钥所属账号有 App Manager 或 Admin 权限。只有 Developer 角色的密钥能上传构建，但改不了文案。

**metadata 管不到的东西**，仍然要手动填：价格（$0.99）、分类、年龄分级、隐私标签、出口合规、审核联系方式。价格改动会触发重新审核，别在提交前临时改。

**不要用 `deliver` 的自动截图上传去覆盖人工排版**：截图一旦上传，同名文件会被覆盖，确认素材再推。

---

## 5. 首次提交前的阻塞项与验收清单

- [ ] 配置完整的商店应用图标与合适的 `LSApplicationCategoryType`；当前 Info.plist 尚未设置应用类别，图标资源也需人工核实。检查最终包中的 Bundle ID、版本、最低系统版本和沙盒签名。
- [ ] 按实际用途核对隐私权限文案、ATS/本地网络访问配置。验收照片授权拒绝、模型与数据库目录选择、安全书签跨重启恢复及授权失效；核对持久化书签所需 entitlement，不扩大权限来绕过问题。
- [ ] 用商店签名构建或 TestFlight 验证沙盒行为，在 Apple Silicon 和 Intel 支持环境覆盖浏览、扫描、缓存和识别。验证 Ollama/Chroma 不运行、无模型和断网时仍可正常处理。
- [ ] 发布稳定可访问的支持 URL、隐私政策 URL，完成中英文商店文案、截图、年龄分级、定价和适用的加密出口合规问卷；不要未经核实声明免加密申报。
- [ ] 按实际 API 和数据流审查 Required Reason API、Privacy Manifest 及 App Store 隐私标签。当前仓库未提供 `PrivacyInfo.xcprivacy`，需要核实并补齐适用声明；照片、人物名称和人脸 embedding 可能发送至用户配置的 Ollama/Chroma 服务，不能笼统宣称所有数据始终仅保存在本机。
- [ ] 处理 [安全与隐私审计](security-privacy-audit-2026-09-24.md) 中仍适用的问题，确认传输告知、远端安全配置、缓存清除与数据删除行为与隐私政策一致。
- [ ] 确认模型及全部依赖的分发/商业授权。**当前界面注明 `antelopev2.gguf` 预训练权重仅限非商业用途**；付费或商业发布前必须取得适用授权或替换方案。将必要第三方许可声明纳入分发包。
- [ ] 在审核说明中写清可选 AI 服务和模型的配置方式、无依赖时可用功能，并提供合成素材及可复现步骤；不要要求审核人员访问开发者本机的 localhost 服务，不要在截图中包含真人照片或私人路径。

这些项目需要真实账号、商店资料及产品合规判断，fastlane 不会代为确认或绕过。
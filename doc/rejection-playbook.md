# macOS 首发拒因应对手册 · HomeBuddy

> 写于 2026-10-29。对象是 1.0（build 2），审核中。所有「苹果会怎么问」按 Guideline 编号分组，
> 问题文字是英文原文的语气改写，不是苹果逐字原文。
> 依据：`doc/aso-mac-app-store.md`、`doc/mac-app-store-release.md`、当前源码、
> 以及 2026-10-29 从 App Store Connect 读到的状态（见 `doc/app-review-status-2026-10-29.md`）。

## 0. 这一版最可能先被问到哪两类

按 1.0 的实际形态（付费、模型自备、可选本地服务、商店页有六张功能截图），拒信落点大概率是这两条：

1. **截图与可复现性**：截图里有人脸列表和文字搜索结果，审核员装上后看不到。
2. **外部服务依赖**：认人要 gguf 权重、搜文字要 Ollama，审核员两样都没有。

其余四类属于「被问到时要有现成答案」，不必现在动手。下面每条按「苹果会怎么问 / 我们怎么答 / 需要改什么」写。

---

## 1. 元数据不实（Guideline 2.3、2.3.1、2.3.3）

### 苹果会怎么问

- 「Your screenshots show a named person and text-search results. After installing, we could not reproduce them: face tagging requires a model file that is not in the app, and text search requires an Ollama server.」
- 「The en-US screenshots display Chinese interface text.」
- 「Your description says cache cleanup and syncing deletions are still being built. Is this a finished app?」（2.2 的边缘问法，来自描述最后一段的自曝）

### 我们怎么答

- 1.0 的核心是「浏览 + 看元数据」，这两件事装完就能用，不需要任何配置。审核备注第 2、5 条已经给了无模型复现步骤。
- 人脸与文字搜索是「自备模型」功能，不是隐藏付费墙：应用里没有内购、没有账号，模型也不由我们分发（许可证原因，见第 6 节）。描述 REQUIREMENTS 里标了 Optional。
- 截图里的照片是合成素材，不是用户图库。

### 需要改什么

- `fastlane/metadata/en-US/description.txt` 最后一段「HomeBuddy is early software… cache cleanup and syncing deletions to remote services are still being built」改成范围声明，例如「1.0 focuses on browsing, metadata and local tagging；cache cleanup lands in a later update」。**这一句是主动递给审核员的「未完成」把柄。**
- en-US 截图重拍成英文界面。前提是下一次构建把本地化资源打进去（build 2 里没有，见状态报告第 4 节）。
- 人脸与搜索截图只展示「已经跑过一次识别之后」的界面，不展示跑的过程和「一键得到」的暗示。文案里 "Faces found on your Mac" 可以留，但别让它读起来像开箱即用。

---

## 2. 需要外部服务才能用（Guideline 2.1、2.2、4.2）

### 苹果会怎么问

- 「Please provide a demo account or a way to evaluate face recognition and text search. We cannot connect to a service running on your machine.」
- 「The app requires a locally hosted Ollama and a third-party model to perform its headline feature.」（这类问法通常落在 2.1「必须能独立运行」或 4.2「最低功能」）

### 我们怎么答

- 不接受账号、也没有账号可给：应用无登录、无云端、无开发者服务器。
- 不配任何服务时，打开就是图库网格、相册、元数据面板；人脸按钮会给出「还没有模型」的提示，不报错、不阻断（`SetupNotice.swift` 与照片信息面板都是这个行为）。
- 本地服务由用户自己装（Ollama 官方安装包、Chroma 自带 docker 镜像），应用只填地址、不代下载。这是「BYO model」的产品选择，写进了描述与审核备注。

### 需要改什么

- 审核备注补三行可执行步骤：无模型时看到什么、怎样三步看到元数据、两个地址默认是回环地址（`127.0.0.1:11434`、`localhost:8000`）。现在第 5 条只有一句「browse albums, open a photo」，不够像操作手册。
- 首次启动的提示已有（照片权限 + 缺模型两条），不要改成弹窗式引导，那会坐实「必须先配置」。
- 如果审核追问模型从哪来，只给发布者页面（mudler 的 face-detect-gguf、InsightFace antelopev2 原始页），不要给本机路径，也不要代传文件。

---

## 3. 隐私标签与行为不一致（Guideline 5.1.1、5.1.2，隐私清单）

### 苹果会怎么问

- 「Your description says images stay on your Mac, but the app posts photos to `http://127.0.0.1:11434` and face embeddings to `http://localhost:8000`. Both addresses are user-editable. What leaves the device?」
- 「Your privacy manifest declares Photos as collected. Explain how data is collected when there is no account and no server.」

### 我们怎么答

- 两个地址默认都是回环地址；只有在设置里手动改成远端地址才会离开这台 Mac。应用没有任何开发者运营的服务器，也不含分析或广告 SDK。
- `PrivacyInfo.xcprivacy` 的声明是「Photos or Videos：App Functionality、不与身份关联、不追踪」，`NSPrivacyTracking` 为 false，追踪域名列表为空。这与代码行为一致。
- 数据流的完整说明在隐私政策页，无需在回复里复述。

### 需要改什么

- 到 App Store Connect 人工比对隐私标签与 manifest 是否同一口径（照片：收集 / App 功能 / 不关联 / 不追踪）。这一步只能人工核对，公开 API 读不到隐私标签。改标签属于写操作，等确认。
- 审核备注加一句「Both endpoints default to loopback addresses; HomeBuddy never contacts a server operated by the developer.」
- `PrivacyInfo.xcprivacy` 里 `C617.1` 这个文件时间戳理由在代码里找不到对应访问，建议核实后删掉（多报不致命，但被追问时要答得出是给谁用的）。细节见状态报告第 3 节。

---

## 4. 截图含真实数据（Guideline 2.3.3，以及 5.1.1 的边缘）

### 苹果会怎么问

- 「Your screenshots contain a personal file path (`/Users/…`).」（通常直接要求换图，措辞很轻）
- 「Screenshot 1 shows a 23,040-item library, but the app's grid in screenshot 2 shows a 12-item demo folder. Please make screenshots reflect the app accurately.」
- 中文界面出现在 en-US 商品页，也可能被写成「screenshots do not match the localized listing」。

### 我们怎么答

- 承认是开发机截图，换成干净账号的 demo 图库重拍，不争辩。

### 需要改什么

- `fastlane/screenshots/zh-Hans/02-setup.png` 与 `en-US/02-setup.png` 都有 `/Users/twinsant/.homebuddy`。这是开发者的真实主目录，属于「截图含真实数据」的典型。
- `01-library.png` 的侧栏有真实照片库数量（23,040）和真实的 `Pictures` 文件夹，与主区域 12 张的 demo 目录不匹配。
- 重拍放在一个新建的演示账号里，用户名用 `demo` 之类，路径就变成 `/Users/demo/...`，不再暴露身份。照片信息面板、设置页都会显示绝对路径，这是目前所有截图的最大雷点；不改代码的前提下，换账号是最省事的解法。
- 上传覆盖用 `bundle exec fastlane mac screenshots`，同名文件会覆盖。**当前版本在审，不要现在推。**

---

## 5. 沙盒 / 权限说明（Guideline 2.1、5.1.1、5.1.2，App Sandbox）

### 苹果会怎么问

- 「Why does the app request Photo Library access on launch? What happens if I deny it?」
- 「The app writes a hidden `.homebuddy` folder in my home directory. Why does a photo organizer need that?」
- 「The photo library permission prompt is Chinese-only on an English system.」
- 「The app connects to `localhost:11434` and `localhost:8000`. Is local network permission required?」

### 我们怎么答

- 照片权限只用于显示系统相册；拒绝后仍可用「添加目录…」浏览磁盘照片，提示条会告诉用户怎么继续（`SetupNotice.swift`）。
- `.homebuddy` 是 SQLite 缓存目录，用户在设置里主动选的；没选过时落 `~/Library/Application Support/HomeBuddy`。缓存里只有元数据与索引，不含原图。
- 回环地址不触发本地网络权限；只有用户把地址改成局域网或远端主机，系统才会要权限，而 1.0 没有写 `NSLocalNetworkUsageDescription`。
- 权限文案的英文本地化已经写好（`HomeBuddy/HomeBuddy-InfoPlist.xcstrings`），只是 build 2 没带进去。

### 需要改什么

- 下次构建确认 `en.lproj/InfoPlist.strings` 真的进包，审核员在英文系统看到的是英文权限说明。
- 如果决定支持局域网地址，补 `NSLocalNetworkUsageDescription`；否则在设置页把地址输入框的提示限定为本机地址。
- `HomeBuddy.xcodeproj` 里 `ENABLE_USER_SELECTED_FILES = readonly` 与 `HomeBuddy.entitlements` 的 `files.user-selected.read-write` 不一致，成品包里两个 entitlement 都在。统一成 read-write（写 SQLite 缓存需要），别让审核员看到互相矛盾的权限声明。
- 照片 entitlement 用的是 `com.apple.security.personal-information.photos-library`，这是对的，不要为了省事加宽到整个文件系统。

---

## 6. 许可证与第三方内容（Guideline 5.2，附 2.3）

### 苹果会怎么问

- 「The app is sold for $0.99, but Settings state the pretrained weights are non-commercial. Explain your rights to distribute them.」（付费应用 + 非商业字样的组合，最容易被要求解释）
- 「Provide licenses for third-party code included in the bundle.」
- 「What is 'antelopev2'? Is it your trademark or licensed to you?」

### 我们怎么答

- pkg 里没有 `.gguf` 权重，可以让审核方核查：设置页是让用户自选本机文件，应用不发、不镜像、不下载权重。用户下载的权重，许可义务在用户手上。
- 包内第三方代码的许可证随包：`face-detect-MIT.txt`、`ggml-MIT.txt`、`libjpeg-turbo.txt` 都在 `Contents/Resources`。
- `antelopev2.gguf` 是格式兼容性说明，不是商标使用；商店文案没有用第三方名称做卖点。

### 需要改什么

- 设置页那句「该预训练权重仅限非商业用途」（`SettingsView.swift` 第 154 行）改成「模型由你自行获取，使用时须遵守其许可」。现在这句会被审核员直接和 $0.99 放在一起读。
- 描述里的 `antelopev2.gguf compatible model file` 保留，它说明的是格式，不是分发。
- 准备一份「权重不在包内」的说明，附包内容清单；被问到再给，不主动塞进审核备注。

---

## 附：拒信到手后怎么走

1. 先看状态是 `REJECTED`、`METADATA_REJECTED` 还是 `INVALID_BINARY`。这三种处理路径不同，别一上来就重建。
2. Resolution Center 的回复只答被问的那一条，附复现步骤与证据截图，不复述产品理念。
3. 改文案或截图不用换 build；改代码必须把 `BUILD_NUMBER` 加一，`1.0` 的版本号不变。
4. 改完不要自己点「重新提交」，先确认改动落地（`fastlane mac check_metadata` 或包内核对），再决定。

## 附：这一版已经确定的四个事实

- 提审时间 2026-10-28 09:11（GMT+8），对应太平洋时间 2026-10-27 18:11。
- 在审版本是 1.0（build 2），构建于 2026-10-26，包内没有本地化资源，界面只有中文。
- 审核备注 1,022 字符，已随版本提交。
- 二进制声明分类 `public.app-category.photography`，App Store Connect 上的主分类是 Utilities，两者不一致。

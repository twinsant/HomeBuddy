# 1.0 审核状态与上架缺口 · 2026-10-29

> 数据来源：2026-10-29 10:00 前后用 App Store Connect API（只读）查的实时状态，加上仓库与构建产物核对。
> 凭据未打印、未改动任何线上内容。本文件只记录事实与判断，不包含写操作。

## 1. 审核到哪一步

| 项 | 值 |
|---|---|
| 应用 | `com.twinsant.HomeBuddy`（app id 6824771683，主语言 zh-Hans） |
| 版本 | 1.0，id `2cb921a5-754f-420c-bba5-6ee5679b2be2` |
| 版本状态 | `WAITING_FOR_REVIEW` |
| 应用信息状态 | `WAITING_FOR_REVIEW` |
| 本次审核提交 | id `08f65627-…6330`，平台 MAC_OS，状态 `WAITING_FOR_REVIEW` |
| 提交时间 | 2026-10-28 09:11（GMT+8），即太平洋时间 2026-10-27 18:11 |
| 附带的构建 | build 2，`VALID`，上传于 2026-10-26 09:19（GMT+8），过期日 2027-01-23 |
| 发布方式 | 手动发布（`release_type = MANUAL`），审核通过不会自动上架 |
| 商店截图 | 两种语言各 2 张（`APP_DESKTOP:2`） |
| 审核备注 | 已在线上，1,022 字符 |

**有没有新消息**：没有。版本状态仍是 `WAITING_FOR_REVIEW`，没有出现 `REJECTED` 或 `METADATA_REJECTED`。
Resolution Center 的会话读不到：公开 API 里 `resolutionCenterThreads` 这个路径不存在，只有苹果自有接口能读，所以「无新消息」是从版本状态推断的，不是查了收件箱。到此刻在审约 25 小时，macOS 首发正常区间。

## 2. 截图盘点

商店页规划六张（`doc/aso-mac-app-store.md` 第 5 节），现在有 2 张，缺 4 张。已经有的两张都有问题。

### 2.1 已有的两张

| 文件 | 内容 | 问题 |
|---|---|---|
| `01-library.png`（zh-Hans、en-US） | 图库网格，合成风景图，侧栏有磁盘目录、人物、系统相册 | 侧栏是真实照片库：Recents 23,040 张、`Pictures` 91 张，和主区域 12 张的 demo 目录对不上。en-US 版的界面文字是中文 |
| `02-setup.png`（zh-Hans、en-US） | 设置窗口「数据库」标签页 | 显示开发者真实主目录 `/Users/twinsant/.homebuddy`；en-US 版同样显示这条路径，界面也是中文；内容讲的是 SQLite 目录，不是文案要讲的「自备模型」 |

两张都是 2880×1800，规格没问题。广告文案是后期叠上去的，排版没问题。

### 2.2 缺的四张

| 序号 | 计划画面 | 需要的界面状态 | 需要的条件 | 现在能不能拍 |
|---|---|---|---|---|
| 03 | 人物命名（ASO 表第 2 行） | 打开一张多人照片 → 工具栏「检测人脸」→ 图上出现人脸框 → 点框弹出「标注人物」，里面有「确认是 XXX（相似度 96%）」 | antelopev2.gguf；候选相似度那行还要 Chroma | 能拍。模型文件在本机 `~/.lmstudio/models/mudler/face-detect-gguf/antelopev2.gguf` |
| 04 | 同一个人跨相册结果（第 3 行） | 左栏「按人物筛选」显示某人「已识别 12 张 · 潜在识别 3 张」，点开后网格是跨两个相册的同一人照片 | 模型 + Chroma + 同一个人分别出现在两个不同相册或目录里 | 能拍。Chroma 已在 `localhost:8000` 跑起来 |
| 05 | 关键词搜图（第 4 行） | 搜索框输入一个词，结果条显示「找到 N 张照片（需同时包含全部关键词）」，照片信息面板里有「Ollama 识别文字」 | Ollama + 视觉模型 + 先对这些照片跑过批量识图 | 能拍。Ollama 在跑，应用默认的 `qwen3.8:27b-mlx` 在列表里 |
| 06 | 单张照片元数据面板（第 5 行） | 详情页右栏「照片信息」：分辨率、文件类型、文件大小、拍摄时间、相机、镜头、曝光、ISO、焦距、位置 | 不需要任何服务 | 能拍，但面板顶部会显示 SQLite 缓存的绝对路径 |
| 07 | 设置页模型配置（第 6 行） | 设置 →「人脸识别」标签页，已选中 gguf 模型；或「图片识别」标签页显示模型下拉与连接状态 | 人脸页不需要服务；图片识别页必须先连上 Ollama，否则显示「未读取到模型，请确认 Ollama 已启动」，不能上商店 | 能拍，用人脸识别页 |

**文案和画面的对应关系要改**：`02-setup.png` 现在的位置对应 ASO 表的第 6 行（`Bring your own model`），但画面是数据库目录。重拍时文件名跟着改（例如 `06-model-settings.png`），旧文件删掉，否则上传时按文件名排序会把旧图一起带上。

### 2.3 拍之前的准备

1. **建一个干净的演示账号**（系统设置里新建标准用户，用户名用 `demo` 之类，或干脆用虚拟机）。原因：照片信息面板固定显示 SQLite 缓存绝对路径，设置页固定显示模型路径，不换账号就一定带出 `/Users/twinsant/…`。换账号是最省事的解法，不用改代码。
2. 演示账号里准备素材：合成人像（AI 生成，不是真人）同一人 3 到 5 张，分散在两个不同目录，模拟「跨相册」；再准备一组合成字牌图，牌子上写英文词，让 Ollama 的识别文字有内容可搜。
3. 服务是系统级进程，演示账号能直接用 Ollama 与 Chroma；但 `antelopev2.gguf` 在开发者主目录里（权限 700），演示账号读不到。拍之前把模型拷到 `/Users/Shared` 之类可读位置，拍完记得处理，不要随包分发。
4. 每张都先在有服务的环境里跑一遍，确认人脸真的检测得出来、Chroma 真的能返回候选。antelopev2 对合成人像的检出率不稳定，跑不通就换素材。

## 3. `HomeBuddy/PrivacyInfo.xcprivacy` 与实际行为核对

### 3.1 逐项对齐

| 声明 | 值 | 代码 / 构建里的实情 | 结论 |
|---|---|---|---|
| `NSPrivacyTracking` | `false` | 没有广告、分析、归因 SDK；出网只有 Ollama 与 Chroma 两个用户可填地址 | 一致 |
| `NSPrivacyTrackingDomains` | 空数组 | 同上，没有已知追踪域名 | 一致 |
| 收集数据类型 | `PhotosorVideos`，不关联身份，不追踪，用途 `PurposeAppFunctionality` | 照片与元数据在本机处理；用户把地址改成远端时才会外发，应用无开发者服务器 | 方向一致。照片留在本机时按苹果定义不算「收集」，属于多报，不会因此被拒 |
| UserDefaults | `CA92.1` | 只读写自己的偏好与安全书签：`SettingsView`、`PhotoLibraryStore`、`FaceRecognitionService`、`OllamaVisionService`、`ChromaService`、`HomeBuddyApp` 共 6 处 | 一致 |
| 文件时间戳 | `3B52.1` | `DiskLibraryStore` 对用户选的目录读 `.contentModificationDateKey`（与库里存的 `modificationTime` 比对，判断缓存是否过期）与 `.fileSizeKey` | 一致 |
| 文件时间戳 | `C617.1`（App 容器内文件时间戳） | 代码里没找到对容器内文件时间戳的读取 | 多报。不致命，但被追问时要答得出用途，建议核实后删 |
| 权限用途文案 | `NSPhotoLibraryUsageDescription` 只有中文 | `HomeBuddy/HomeBuddy-InfoPlist.xcstrings` 里写了英文版，但没进 build 2 | 待修（见第 4 节） |
| 构建产物 | — | `build/mac-app-store/HomeBuddy.app/Contents/Resources/PrivacyInfo.xcprivacy` 与源码 `diff` 完全一致 | 一致 |

### 3.2 值得注意的两处

1. **文件时间戳只用于判断缓存过期，没有展示给用户。** 磁盘图片的修改时间读进数据库和 `.contentModificationDateKey` 比对，过期就重新读元数据。照片信息面板里的「拍摄时间」对磁盘图片取的是 EXIF 的 `DateTimeOriginal`，取不到就显示「未知」，不是文件时间戳。所以不需要补 `DDA9.1`（把时间戳展示给用户看）这一条。
2. **人脸数据的归类**：人脸 embedding 与人物姓名会写进用户自己的 Chroma。照片可以发到远端时，这部分也会跟着出去。清单里只有「Photos or Videos」一类，没有单独的人脸或「其他用户内容」声明。苹果的数据类型表里没有「人脸」这一项，用 Photos 覆盖说得通；但隐私政策页要写清楚这一点，别只写「照片」。

### 3.3 读不到的部分

App Store Connect 的隐私标签（Data Usages）这个团队密钥读不了：`dataUsagePublishState` 与 `dataUsages` 两条关系路径都返回 404。所以「ASC 上勾的标签」和「manifest 声明的」是不是同一口径，只能人工到网页核对。当前 `doc/aso-mac-app-store.md` 第 6 节的写法是「照片与人脸数据在设备上处理；可选把数据发送到用户自填地址」，和 manifest 方向一致。

## 4. 另外三件要知道的事

**a. 在审的 build 2 没有本地化资源。** `Contents/Resources` 里没有任何 `.lproj`，`en.lproj/Localizable.strings` 和 `InfoPlist.strings` 都不在。原因是对得上的：两个 `.xcstrings` 是 2026-10-28 09:24 的提交 `6c54990` 才加进仓库，而归档是 10-26 09:15 做的。也就是说审核员现在看到的是纯中文界面，en-US 商品页配中文界面。这不是截图造假（截图和 build 2 是一致的），但英文市场会掉转化，也可能被问一句。要修只能等下一次构建，构建号加一。

**b. 分类不一致。** 二进制里 `LSApplicationCategoryType = public.app-category.photography`，App Store Connect 上 `primary_category` 是 `UTILITIES`。上架后影响摄影类目的曝光，也影响「Photo Organizer」这个定位的一致性。

**c. 工作区有未提交改动。** `git status` 显示 5 个 Swift 文件被改（`BatchRecognitionView`、`ContentView`、`HomeBuddyApp`、`Localizable.xcstrings`、`PhotoLibraryView`），时间在 10-28 20:xx 之后，比在审的 build 2 新。如果这次被拒要重建，先确认这些改动是有意的，再决定是否一起进 build 3。

## 5. 需要你决定的事

1. **截图现在准不准备。** 建议先在演示账号里把六张拍齐、存在仓库外，但不推送到 App Store Connect。版本在审期间改截图要么等拒信，要么撤审重提，不值当。
2. **en-US 首发接不接受中文界面。** 接受就等审核结果，接受转化损失；不接受就得做 build 3 补本地化，`BUILD_NUMBER` 加一，等这次审核结束后再提。
3. **`C617.1` 删不删。** 删要动 manifest，只能进 build 3，和本地化一起做最省事。
4. **分类改成 Photography 吗。** 这是 App Store Connect 的写操作，改完可能影响审核（分类变更一般不需要重审，但提审前改更稳）。你点头我再动。
5. **设置页那句「该预训练权重仅限非商业用途」改不改。** 涉及代码，建议等审核结果，和 build 3 一起改。

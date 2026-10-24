# Mac App Store ASO · HomeBuddy

> 更新：2026-10-24
> 适用版本：1.0（build 1）
> 本文只解决「商店页怎么写」。能不能过审、能不能上架，见 [Mac App Store 发布准备](mac-app-store-release.md) 第 4 节的阻塞项。

## 0. 一句话定位

**在这台 Mac 上把照片库变成能搜的档案：本地认人，按照片里的文字找图。**

英文对外：`A photo organizer that finds people and text, without uploading your library.`

定位取舍：不跟 Apple Photos 抢「看图」，抢的是「找图」。两个具体能力是别人没有的：本地人脸识别加命名，以及按图片里的文字搜索。

## 1. 市场与优先级

| 优先级 | 语言 | 理由 |
|---|---|---|
| 1 | en-US（含英国、澳洲、加拿大） | Mac App Store 的主要收入市场；「photo organizer」「face recognition」搜索量集中在这里 |
| 2 | zh-Hans | 你自己的圈子能测；国内 Mac 用户比例低但客单低，先当验证场 |
| 3 | ja | 日本 Mac 占有率高，面向照片整理付费意愿强；等 1.1 有日语文案再开 |

不要一次开十几个语言。本地化文案要人写，机器翻译的商店页在英文市场反而扣分。

## 2. 元数据字段

下面两段是定稿。仓库里的源文件是 `fastlane/metadata/en-US/` 与 `fastlane/metadata/zh-Hans/`，改文案改那里，用 `bundle exec fastlane mac metadata` 推送。本文与文件不一致时以文件为准，同时把本文改掉。

### en-US

| 字段 | 内容 | 字符数 / 上限 |
|---|---|---|
| App Name | `HomeBuddy: Photo Organizer` | 26 / 30 |
| Subtitle | `Face tags and text search` | 25 / 30 |
| Keywords | `ai,library,manager,tagging,people,text,exif,metadata,album,catalog,offline,privacy,scan` | 87 / 100 |
| Promotional Text | `Browse your Mac photo library and folders, tag faces locally, then search photos by the text inside them. One-time price, no subscription. Images stay on your Mac.` | 163 / 170 |

### zh-Hans

| 字段 | 内容 | 字符数 / 上限 |
|---|---|---|
| App Name | `HomeBuddy：照片整理与搜索` | 17 / 30 |
| Subtitle | `本地人脸识别与图片搜索` | 11 / 30 |
| Keywords | `相册,分组,标注,元数据,归档,离线,隐私,扫描,EXIF,关键词,备注,批量,时间线,相机,镜头,人物,标签,智能` | 58 / 100 |
| Promotional Text | `在 Mac 上浏览照片图库和文件夹，本地检测人脸、给人物命名，再按照片里出现的文字搜索。照片不出这台 Mac。` | 55 / 170 |

## 3. 关键词决策表

Apple 已经把名称、副标题、关键词字段三者一起索引，三处重复一个词等于浪费额度。下面每个词只出现一次。

| 关键词 | 意图 | 竞争判断 | 放进哪个字段 |
|---|---|---|---|
| photo organizer | 主诉求，直接找工具 | 高，Mylio / PowerPhotos 占着 | 名称 |
| face tags | 差异化功能 | 中，几乎没有 Mac 应用主打 | 副标题 |
| text search | 差异化功能，图片内文字 | 低，蓝海 | 副标题（text）+ 关键词（text） |
| ai | 泛需求，量大不精准 | 极高 | 关键词 |
| library | 照片库 | 中 | 关键词 |
| manager | photo manager 变体 | 高 | 关键词 |
| tagging | 打标签 | 中 | 关键词 |
| people | faces / people 分类 | 中 | 关键词 |
| exif / metadata | 摄影用户，付费意愿高 | 低 | 关键词 |
| album / catalog | 相册、目录 | 中 | 关键词 |
| offline / privacy | 隐私诉求，转化率高 | 低 | 关键词 |
| scan | 批量扫描 | 中 | 关键词 |
| 相册 / 分组 / 标注 | 中文主诉求 | 中 | 关键词 |
| 元数据 / EXIF / 相机 / 镜头 | 摄影用户 | 低 | 关键词 |
| 离线 / 隐私 | 隐私诉求 | 低 | 关键词 |
| 人物 / 标签 | 认人 | 中 | 关键词 |

**刻意没写的词**：`duplicate`、`dedupe`、`duplicate photos` —— 应用目前没有查重功能。写进去能骗来点击，但会换来一星和审核质疑。等真做了再加。
**不能写的词**：`Photos`（Apple 商标式用法）、`Lightroom`、`PowerPhotos`、`Mylio` 等竞品名。Apple 会以 metadata 侵权打回。

## 4. App 描述

### en-US（1,900 字符以内）

```
HomeBuddy is a photo organizer for macOS. It opens the library you already have, tells you what is inside each file, and helps you find a photo again without scrolling.
It is a one-time purchase. No subscription, no account, no upload.

WHAT YOU GET
• System Photo Library, smart albums, and your own albums
• Any folder of photos on disk, browsed as a library
• Sizes, formats, capture time, camera, lens, exposure, ISO, focal length
• A local cache, so the same metadata does not get read twice

FACES, NAMED ONCE
• Face detection runs on your Mac with a local model
• Give a person a name and HomeBuddy remembers the match
• Look for the same face across the whole library

SEARCH THE TEXT INSIDE PHOTOS
• Optional: connect Ollama with a vision model, and HomeBuddy describes photos one at a time or in a batch
• Descriptions are stored locally, so you can search by any word that appeared in a photo
• Nothing leaves your Mac unless you configure a remote endpoint yourself

PRIVATE BY DESIGN
• Keeps the metadata cache on your Mac
• Runs face detection locally
• The optional services are the ones you host: point HomeBuddy at your own Ollama or Chroma address

BRING YOUR OWN MODEL
HomeBuddy does not ship a face model. In Settings, pick an antelopev2.gguf compatible model file and a folder for the metadata database. Without a model, browsing, albums, metadata, folders, and text search all still work.

REQUIREMENTS
• macOS 26.5 or later
• Photo Library access
• Ollama with a vision model (optional, for photo descriptions)
• Chroma (optional, for face vector search)

HomeBuddy is early software. It reads and indexes well; cache cleanup and syncing deletions to remote services are still being built.
```

### zh-Hans

```
HomeBuddy 是一款 macOS 照片整理工具。它打开你已有的照片图库，告诉你每个文件里有什么，让找一张旧照片不用再翻相册。
一次买断，没有订阅，不用注册账号，不上传照片。

功能
• 浏览系统照片图库、智能相册和自己建的相册
• 把磁盘上任意照片文件夹当相册浏览
• 查看尺寸、格式、拍摄时间、相机、镜头、曝光、ISO、焦距
• 元数据本地缓存，同一张照片不用重复读

认人只需要一次
• 人脸检测在你的 Mac 上本地运行
• 给一张脸起好名字，之后会记住这个匹配
• 可以在整个图库里找同一个人

搜照片里的文字
• 可选：接入 Ollama 视觉模型，单张或批量描述照片
• 描述保存在本地，之后用照片里出现过的词就能搜到
• 除非你自己配置了远端地址，否则照片不出这台 Mac

隐私
• 元数据缓存保存在本机
• 人脸检测本地运行
• 可选服务由你自己部署：填自己的 Ollama 或 Chroma 地址

自备模型
HomeBuddy 不内置人脸模型。在设置里选择一个兼容 antelopev2.gguf 的模型文件，以及元数据数据库目录。没有模型时，浏览、相册、元数据、文件夹和文字搜索仍然可用。

系统要求
• macOS 26.5 或更高版本
• 照片图库访问权限
• Ollama 与视觉模型（可选，用于照片描述）
• Chroma（可选，用于人脸向量检索）

HomeBuddy 还是早期版本。读取和索引已经稳定；缓存清理和远端删除同步还在做。
```

### What's New（1.0）

```
First release.
```

中文：`首个版本。`

## 5. 截图

Mac App Store 截图规格：16:10，可用 1280×800 / 1440×900 / 2560×1600 / 2880×1800，最多 10 张。建议按 2880×1800 出图，文字在缩略图状态下也要看得清。

六张的顺序按「我为什么需要它」排，不按功能菜单排：

| # | 画面 | 英文文案 | 中文文案 |
|---|---|---|---|
| 1 | 图库网格 + 侧边相册 | `Your whole library, in one window` | `整个图库，一个窗口` |
| 2 | 人物命名界面 | `Faces found on your Mac` | `人脸在本机识别` |
| 3 | 同一个人跨相册结果 | `Name them once, find them anywhere` | `命名一次，到处找得到` |
| 4 | 输入关键词搜出照片 | `Search the words inside photos` | `搜索照片里的文字` |
| 5 | 单张照片的元数据面板 | `Every detail, at a glance` | `每项元数据，一眼看完` |
| 6 | 设置页模型与服务配置 | `Bring your own model` | `模型自备，本地运行` |

素材要求（这条会直接影响审核）：
- 截图里的照片必须是合成素材或 AI 生成图，不能出现真人、真实家庭、路人
- 不能出现个人路径、真实用户名、邮箱
- 不要在截图里出现 `localhost` 地址指向你本机服务
- 文案不要写「免费」「永久」「最强」，也不要在截图里塞价格

## 6. 其它商店信息

| 项 | 取值 |
|---|---|
| 主分类 | Photography |
| 次分类 | 不设（Mac App Store 只允许一个分类） |
| 年龄分级 | 4+（无用户生成内容、无广告、无内购） |
| 定价 | **$0.99**（美国区价格点 1），无内购（理由见第 7 节） |
| 内购 | 无 |
| 隐私标签 | 需要如实勾选：照片与人脸数据在设备上处理；可选把数据发送到用户自填地址 |
| 支持 URL / 隐私政策 URL | `https://www.twinsant.com/homebuddy` 与 `https://www.twinsant.com/homebuddy/privacy`（已上线，2026-10-24） |
| App 审核备注 | 写清模型如何获取、不配置 Ollama/Chroma 时哪些功能可用，并提供复现步骤 |

## 7. 卖 $0.99，模型用户自备

两件事不冲突，但要写清楚逻辑。

**卖的是应用，不是模型。** 安装包里不放任何 `.gguf` 权重，用户自己去模型发布者那里下载，许可约束落在他身上。你收的 $0.99 是软件的价钱，不构成对模型权重的商业分发。

**这决定了三条纪律**，做错任何一条都会把「用户自己下载」变成「你在分发」：

1. 安装包里不放 `.gguf`，`HomeBuddy/Native/` 只留静态库与许可证
2. 应用内不托管、不镜像、不代为下载权重；只给模型名称与获取指引，指向发布者自己的页面
3. 商店描述与审核备注写明：人脸模型由用户自备，许可证由用户自行遵守

**收入口径**：$0.99 在美国区对应价格点 1，中国区按对应价格点（约 ¥8）。加入 App Store 小型企业计划后抽成 15%，单笔到手约 $0.84。这个数字决定了它不会成为收入主力，作用是覆盖服务器域名成本、让用户认真用，以及验证「有人愿意为本地隐私付费」。

**$1 的定价会放大首启问题。** 免费应用配置失败只是卸载，付费应用配置失败会申请退款加一星。第 8 节第 1 条从「建议」升级成「上架前提」。

**不要做的事**：截图和描述里不写价格（Apple 会打回）；促销用兑换码（每个版本最多 100 个）而不是临时改价；不做「限时免费」当营销，改价会丢评论的权重。

## 8. 上架前会杀死转化率的四件事

ASO 只负责让人点进来。下面四条不修，点进来也会立刻删：

| 问题 | 现在的状态 | 上线前至少要做的 |
|---|---|---|
| 首次启动要配三样东西 | 模型文件、元数据目录、可选 Ollama/Chroma | **上架前提**：第一屏进去就看到图库和元数据，AI 功能标成「可选，之后配置」。$1 的应用配置失败会直接退款 |
| 没有人脸模型就有一半功能不可用 | 设置里要自己找 gguf | 描述里已经写明，但首启体验要引导到「先用浏览功能」 |
| 缺 Privacy Manifest | 仓库没有 `PrivacyInfo.xcprivacy` | 补上，否则上传就会收到警告 |
| 缺支持页面与隐私政策 | 未准备 | 先做两页静态页，URL 填进 App Store Connect |

## 9. 上线后 30 天

0. 先定指标：三条一起看。产品页转化率（单位 ÷ 浏览量）、付费下载数、退款率。$1 的应用退款率超过 5% 就说明首启体验在拒客。
1. 第 1 周：只改文案，不投钱。看 App Store Connect 的「App 单位」和「产品页浏览量」，算转化率。
2. 第 2 周：若 macOS 版在 App Store Connect 里有产品页优化入口，用两版截图做 A/B；没有就靠版本更新换文案，一次只改一处。
3. 第 3 周：把关键词字段里点击最高和最低的三组词互换，观察两周。
4. 第 4 周：决定要不要做 ja 本地化。判断依据是英文市场的自然安装数有没有连续两周上升。

不做的：买量、刷评、互推。Mac App Store 的自然量本来就小，买量打不平。

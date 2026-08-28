# 智能菜谱助手（HowToCook）

<p align="left">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.9%2B-02569B?logo=flutter&logoColor=white">
  <img alt="Dart" src="https://img.shields.io/badge/Dart-3.9%2B-0175C2?logo=dart&logoColor=white">
  <img alt="Riverpod" src="https://img.shields.io/badge/Riverpod-2.x-3BA5F4">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Android-5AA9E6">
  <a href="https://github.com/Gaq152/howtocook-flutter/releases/latest">
    <img alt="Latest Release" src="https://img.shields.io/github/v/release/Gaq152/howtocook-flutter?include_prereleases&sort=semver&color=brightgreen">
  </a>
</p>

> 基于 Flutter + Riverpod 的跨平台智能菜谱与 AI 助手。把本地菜谱库、云端增量同步、大模型对话和教程体系做在一个 App 里。

## ✨ 功能亮点

### 给使用者

- **菜谱体验**：10 大分类浏览；全文搜索；收藏与笔记；编辑、创建自己的菜谱。
- **AI 助手**：使用自己配置的 Claude / GPT / DeepSeek 模型，支持多轮会话、图片识别、流式输出和**思考链实时展示**。
- **长会话管理**：显示上下文窗口占用与服务商缓存命中率；临近上限时提醒新建会话，继续使用则自动压缩早期上下文。
- **多种 API 格式**：模型可选 Chat Completions、OpenAI Responses 或 Anthropic Messages，也可自动按服务商和 URL 识别。
- **本地 / 云端菜谱工具**：每个会话可切换数据模式；AI 能搜索、读取详情、推荐、随机选菜和生成菜谱草稿，本地模式还可读取收藏及用户保存的菜谱。
- **AI 生成菜谱**：通过 App 内置 `createRecipe` 工具在对话里生成菜谱卡片，用户预览确认后再保存，不会静默写入本地菜谱库。
- **二维码分享**：扫码导入朋友分享的菜谱，或把自己的菜谱生成二维码分享出去。
- **教程体系**：基础、进阶、学习三档烹饪教程，可自创。
- **离线优先**：V1 资源随 APK 提供兜底；云端 V2 按不可变版本同步并原子激活。
- **应用内更新**：启动 3 秒后静默检查 GitHub Releases；发现新版本弹窗展示 Markdown 更新日志，一键下载+安装，自带 SHA256 校验与镜像回退。

### 给开发者

- **Clean Architecture + Feature-Based**：每个功能模块严格分 Domain / Application / Infrastructure / Presentation 四层。
- **双存储策略**：Hive（全平台键值）＋ Sqflite（移动/桌面端关系型），按场景分工。
- **大量代码生成**：Freezed / JSON / Riverpod / Hive Adapter 全部由 `build_runner` 产出。
- **AI 适配器与工具权限**：`ClaudeAdapter` / `OpenAIAdapter` / `DeepSeekAdapter` 兼容 Chat Completions、Responses 与 Anthropic Messages；稳定工具目录按会话数据模式授权，执行前二次校验。
- **Release 自签与自升级**：独立 keystore，CI 与本地共享密钥；Release 页产物自动生成 `manifest.json`，客户端自动更新直连消费。

## 🧱 技术栈

- Flutter 3.35.6 / Dart ≥ 3.9.2（CI 与本地使用同一固定 Flutter 版本）
- 状态管理：flutter_riverpod 2.x + riverpod_generator
- 路由：go_router
- 存储：hive / sqflite / path_provider
- 网络：dio + pretty_dio_logger
- 数据建模：freezed + json_serializable
- UI：flutter_markdown / cached_network_image / flutter_spinkit / google_fonts
- 分享/扫码：qr_flutter / mobile_scanner / opencv_dart（WeChatQRCode）/ screenshot / share_plus
- 更新：package_info_plus / install_plugin（+ 自研 `UpdateService` / `GithubMirrorResolver`）

## 🗂️ 架构与目录

```
lib/
├── core/                 # 通用能力：router / storage / services / theme / utils / widgets
│   ├── router/app_router.dart
│   ├── storage/hive_service.dart · database_manager.dart
│   └── services/data_sync_service.dart · update_service.dart · github_mirror_resolver.dart
└── features/             # 按业务分模块，每个模块内部是四层架构
    ├── recipe/           # 菜谱（含二维码分享）
    ├── ai_chat/          # AI 对话 + App 内置工具 + 云端 MCP 兼容层
    ├── tips/             # 教程
    ├── user/             # 我的（收藏、自创）
    ├── settings/         # 设置（模型管理、检查更新）
    └── sync/             # 数据同步
        ├── domain/       # 实体与仓库接口
        ├── application/  # usecases / providers
        ├── infrastructure/   # repositories / datasources / services 实现
        └── presentation/ # screens / widgets
```

依赖方向严格单向：`presentation → application → domain ← infrastructure`。

## 🚀 快速开始

```bash
# 1) 安装依赖
flutter pub get

# 2) 配置环境变量（首次运行必须）
cp .env.example .env
# Windows PowerShell: Copy-Item .env.example .env

# 3) 生成代码（freezed / json / riverpod / hive adapter）
dart run build_runner build --delete-conflicting-outputs

# 4) 运行
flutter run

# 可选：验证一个静态 V2 版本与当前 App 模型兼容
dart run tool/verify_v2_compatibility.dart <version-directory>
```

> Web 平台仅部分功能可用（Sqflite / 自动更新 / install_plugin 不支持 Web）。

## ⚙️ 环境变量

复制 `.env.example` 为 `.env`，按需填值。关键变量：

| 变量                                                        | 说明                                                          |
| ----------------------------------------------------------- | ------------------------------------------------------------- |
| `MCP_BASE_URL`（可选）                                   | 过渡期云端数据模式的 HowToCook MCP 服务地址；本地数据模式不依赖此配置 |
| `STATIC_RESOURCE_URL`                                     | 远端菜谱数据与图片的 CDN / GitHub Pages 根地址                |
| `RELEASE_MANIFEST_URL`（可选）                            | 覆盖默认的更新检查 manifest 地址，方便调试私有发布渠道        |

## 💾 数据与存储

- **Hive** (`lib/core/storage/hive_service.dart`)：用户 AI 模型配置、聊天历史、收藏、用户设置、`update_prefs`（跳过的版本号等）。全平台。应用升级不会覆盖用户添加的模型和 Key。
- **Sqflite** (`lib/core/storage/database_manager.dart`)：`recipes` 表，支持复杂查询。**非 Web 平台**启用。
- **数据源优先级**：`userModified` ＞ `userCreated` ＞ `cloud` ＞ `bundled`。合并策略见 `DataSyncService`。

## 🛠️ 代码生成工作流

以下类型文件变动后必须跑 `build_runner`：

- `@freezed` 实体 → `*.freezed.dart`
- `@JsonSerializable()` → `*.g.dart`（`fromJson` / `toJson`）
- `@riverpod` Provider → `*.g.dart`
- `@HiveType()` → `*.g.dart`（TypeAdapter）

```bash
dart run build_runner build --delete-conflicting-outputs
# 开发期可换成
dart run build_runner watch --delete-conflicting-outputs
```

## 📦 构建与发版

### 本地构建

```bash
# Release APK（ARM 架构，启用 R8 与资源压缩）
flutter build apk --release

# App Bundle
flutter build appbundle --release

# Windows
flutter build windows
```

### 签名（一次性配置）

1. 生成 keystore（**仅此一次，务必离线多点备份**）：
   ```bash
   cd android && mkdir -p keystore
   keytool -genkey -v -keystore keystore/howtocook-release.jks \
     -keyalg RSA -keysize 2048 -validity 36500 -alias howtocook \
     -dname "CN=anlife,OU=dev,O=howtocook,C=CN"
   ```
2. 在 `android/key.properties`（已 gitignore）写入：
   ```
   storeFile=keystore/howtocook-release.jks
   storePassword=xxx
   keyAlias=howtocook
   keyPassword=xxx
   ```
3. 没有 `key.properties` 时，`release` 会回退 debug 签名（仅限本地调试，不可分发）。

### CI 发版流程（GitHub Actions）

仓库 Settings → Secrets 需配置：

| Secret                | 说明                                                          |
| --------------------- | ------------------------------------------------------------- |
| `KEYSTORE_BASE64`   | `base64 -w 0 android/keystore/howtocook-release.jks` 的输出 |
| `KEYSTORE_PASSWORD` | keystore 密码                                                 |
| `KEY_ALIAS`         | 密钥别名（`howtocook`）                                     |
| `KEY_PASSWORD`      | 密钥密码                                                      |

发版步骤：

1. 更新 `pubspec.yaml` 的 `version:`；
2. 在 `CHANGELOG.md` 的 `[Unreleased]` 下新增一个带版本号的条目（Keep a Changelog 规范）；
3. 打 tag 并推送：
   ```bash
   git tag v0.1.0 && git push origin v0.1.0
   ```
4. `.github/workflows/release.yml` 会：
   - 校验 tag 与 `pubspec.yaml` 版本一致
   - 从 `CHANGELOG.md` 抽取对应版本章节作为 Release body 与 `manifest.json` 的 `notes`
   - 构建签名 APK，产出 `howtocook.apk` + `manifest.json`
   - 创建 GitHub Release，客户端即可检测到新版本

### 应用内更新

`UpdateService` 默认拉 `https://github.com/<owner>/<repo>/releases/latest/download/manifest.json`，`GithubMirrorResolver` 自动在 `ghfast.top` 镜像与官方源之间轮询。下载后按 `sha256` 校验再调起系统安装器（需 `REQUEST_INSTALL_PACKAGES` 权限）。

## 📝 规范与约定

- 代码风格：`flutter_lints`。
- 架构：新增 feature 按 Domain → Infrastructure → Application → Presentation 的顺序实现，详见 [`CLAUDE.md`](CLAUDE.md)。
- 文案：中文 UI 文案集中管理；业务实体与代码命名用英文。
- 提交：建议 Conventional Commits（`feat` / `fix` / `docs` / `chore` / `refactor` 等）。
- Changelog：所有用户可感知的变更都要记到 `CHANGELOG.md`，客户端更新弹窗直接渲染。

## 🧪 测试

```bash
flutter test
flutter test --coverage
```

## ❓ 常见问题

- **代码生成冲突**：`dart run build_runner build --delete-conflicting-outputs`，或删除 `.dart_tool/build`。
- **三方插件 `Namespace not specified`**：项目级 `android/build.gradle.kts` 已对老插件做 namespace 兜底注入；如仍失败请检查插件版本。
- **Release 签名报错**：确认 `android/key.properties` 存在且路径正确；CI 失败先看 `Restore keystore from secret` 步骤。
- **资源未找到**：新增目录后需在 `pubspec.yaml` 的 `assets:` 下登记，再执行 `flutter pub get`。
- **更新检查不触发**：启动后 3 秒才会静默检查；也可进入 "设置 → 检查更新" 手动触发。

## 📄 许可证

项目许可证暂未指定（`LICENSE` 文件未提交），默认视为保留所有权利。如需二次分发请先与作者确认。

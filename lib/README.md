# 项目目录结构说明

## 架构模式
本项目采用 **Clean Architecture + Feature-Based** 架构模式。

---

## 目录结构

```
lib/
├── core/                    # 核心公共模块
│   ├── constants/          # 常量定义
│   ├── router/             # 路由配置
│   ├── storage/            # 存储管理（Hive、Sqflite）
│   ├── theme/              # 主题和样式
│   ├── utils/              # 工具类
│   └── widgets/            # 通用 UI 组件
│
├── features/               # 功能模块（按业务划分）
│   ├── recipe/            # 菜谱管理模块
│   │   ├── domain/        # 领域层（业务逻辑）
│   │   │   ├── entities/         # 实体类
│   │   │   └── repositories/     # 仓储接口
│   │   ├── application/   # 应用层（用例）
│   │   │   ├── providers/        # Riverpod Provider
│   │   │   └── usecases/         # 业务用例
│   │   ├── infrastructure/ # 基础设施层（数据访问）
│   │   │   ├── datasources/      # 数据源（API、本地）
│   │   │   └── repositories/     # 仓储实现
│   │   └── presentation/  # 表现层（UI）
│   │       ├── screens/          # 页面
│   │       └── widgets/          # 页面组件
│   │
│   ├── ai_chat/           # AI 聊天模块
│   │   ├── domain/
│   │   │   ├── entities/         # ChatMessage、RecipeCard
│   │   │   └── services/         # AI 服务接口
│   │   ├── application/
│   │   │   ├── providers/
│   │   │   └── services/         # AIService（模型切换）
│   │   ├── infrastructure/
│   │   │   └── services/         # Claude、GPT、DeepSeek 实现
│   │   └── presentation/
│   │       ├── screens/
│   │       └── widgets/
│   │
│   ├── user/              # 用户中心模块
│   │   ├── domain/
│   │   │   └── entities/
│   │   ├── application/
│   │   │   └── providers/
│   │   └── presentation/
│   │       ├── screens/
│   │       └── widgets/
│   │
│   └── sync/              # 数据同步模块
│       ├── domain/
│       │   └── entities/         # Manifest、RecipeIndex
│       ├── application/
│       │   └── providers/
│       └── infrastructure/
│           ├── datasources/      # BundledDataLoader
│           └── services/         # SyncService
│
└── main.dart              # 应用入口
```

---

## Clean Architecture 分层说明

### 1. Domain Layer（领域层）
- **职责**: 定义业务实体和业务规则
- **特点**: 不依赖任何外部框架或库
- **包含**:
  - `entities/`: 数据模型（使用 freezed）
  - `repositories/`: 仓储接口（抽象）
  - `services/`: 领域服务接口

### 2. Application Layer（应用层）
- **职责**: 协调业务逻辑，处理用例
- **特点**: 依赖 Domain Layer
- **包含**:
  - `providers/`: Riverpod 状态管理
  - `usecases/`: 具体业务用例
  - `services/`: 应用服务（如 AIService）

### 3. Infrastructure Layer（基础设施层）
- **职责**: 实现数据访问和外部服务调用
- **特点**: 依赖 Domain Layer，实现仓储接口
- **包含**:
  - `datasources/`: 数据源（网络、本地数据库、文件）
  - `repositories/`: 仓储实现
  - `services/`: 外部服务实现（AI API）与应用内置工具

### 4. Presentation Layer（表现层）
- **职责**: UI 展示和用户交互
- **特点**: 依赖 Application Layer
- **包含**:
  - `screens/`: 完整页面
  - `widgets/`: UI 组件

---

## Feature-Based 模块说明

### Recipe Module（菜谱管理）
- 菜谱列表、详情、搜索、筛选
- 收藏、备注、编辑、创建
- 数据优先级：本地修改 > 用户创建 > 云端下载 > 内置数据

### AI Chat Module（AI 聊天）
- 多模型支持（Claude、GPT、DeepSeek）
- 对话历史持久化
- 图片识别（base64 编码）
- 菜谱卡片展示

### User Module（用户中心）
- 我的收藏
- 我的菜谱
- 设置页面

### Sync Module（数据同步）
- 内置数据加载
- 增量更新检测（基于 hash）
- 后台下载新菜谱

---

## 依赖方向

```
Presentation → Application → Domain ← Infrastructure
                    ↓
                  App Tools
                  AI Services
                  Local Storage
```

**核心原则**: 依赖倒置（内层不依赖外层）

---

## 开发指南

### 添加新功能
1. 在 `features/` 下创建新模块目录
2. 按四层结构创建子目录
3. 从 Domain Layer 开始开发（定义实体和接口）
4. 实现 Infrastructure Layer（数据访问）
5. 编写 Application Layer（业务逻辑）
6. 最后实现 Presentation Layer（UI）

### 数据流向
```
UI Event → Provider → UseCase → Repository → DataSource
                                      ↓
UI Update ← Provider ← Entity ← Repository ← API/DB
```

---

**架构设计文档**: `docs/智能菜谱助手架构设计/DESIGN_智能菜谱助手.md`

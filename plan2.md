# Mobile Agent 全平台开发计划

## 一、定价页修改（紧急）
- 专业版/团队版价格改为"开发中"状态
- 添加 Todo List 标签
- 重新构建部署

## 二、技术调研结论

### 最终推荐：Flutter

| 维度 | Flutter | React Native | ArkUI-X |
|------|---------|-------------|---------|
| 语言 | Dart | JavaScript/TS | ArkTS |
| 性能 | ★★★★★ 原生级 | ★★★★☆ 需桥接 | ★★★★★ 原生级 |
| 自定义UI | ★★★★★ 自绘引擎 | ★★★☆☆ 依赖原生组件 | ★★★★☆ |
| 代码复用 | ~95% | ~85-90% | 鸿蒙+Android+iOS |
| GitHub Stars | 170k | 121k | 新兴 |
| 鸿蒙支持 | 社区+官方推进中 | 社区方案 | 官方原生 |
| 代码编辑场景 | 极佳(自绘控制) | 一般(需桥接) | 良好 |

### 为什么 Flutter 最适合 Mobile Agent：
1. **代码编辑器需求**：Mobile Agent 核心是代码编辑，需要像素级UI控制、自定义文本渲染、语法高亮 —— Flutter 自绘引擎最擅长
2. **性能要求高**：代码编辑是高频输入操作，Flutter AOT编译+直接渲染，无JS桥接开销
3. **UI一致性**：产品定位"全移动端适配"，Flutter确保iOS/Android完全一致
4. **动画能力**：产品宣传中大量动效，Flutter 60-120fps动画能力最强
5. **生态成熟**：170k Stars，代码编辑器、语法高亮、文件管理等包齐全
6. **鸿蒙路径**：Flutter官方正在支持鸿蒙，同时有社区方案(fluent_ui_harmony)

### 技术栈规划：
- **框架**：Flutter 3.29+
- **语言**：Dart
- **状态管理**：Riverpod（最推荐的Flutter状态管理）
- **代码编辑器**：flutter_code_editor + highlight 语法高亮
- **网络**：dio（HTTP）+ web_socket_channel
- **存储**：hive（本地KV）+ path_provider（文件系统）
- **GitHub**：github（Dart包）
- **UI**：Material 3 暗色主题

## 三、源码编写阶段
1. 初始化 Flutter 项目
2. 搭建项目架构（MVVM + Riverpod）
3. 实现核心模块：代码编辑器、云端API、GitHub集成、项目管理
4. 输出完整源码

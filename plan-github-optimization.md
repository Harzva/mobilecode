# GitHub 深度优化计划

## 代码审查发现的问题

### github_screen.dart (904行) UI层问题
1. 搜索仓库后列表不持久化 — 搜索结果切换tab后丢失
2. 筛选器切换时总是重新加载 — 应缓存已加载的数据
3. 仓库列表缺少排序功能（名称、更新时间、星数）
4. 仓库卡片不显示编程语言颜色圆点
5. 通知标记单个已读后列表不刷新
6. 缺少多账号切换UI
7. Issue/PR详情不显示评论列表

### github_deep_service.dart (1178行) 服务层问题
1. 大仓库/列表缺少分页加载 — 一次性加载所有数据
2. 没有缓存层 — 重复请求浪费API配额
3. 没有离线标记 — 离线时无法查看已缓存数据
4. 没有批量操作 — 逐个mark read效率低

### github_repo.dart (260行) 模型层问题
1. 缺少 topics (仓库标签)
2. 缺少 language color (语言颜色)
3. 缺少 fork_count, open_issues_count
4. 缺少 is_template, has_issues 等标志
5. 缺少 license 信息

## 优化方向

### 1. 增强模型 - 新增字段
### 2. 缓存层 - 减少API调用
### 3. UI增强 - 仓库浏览器、Issue详情、PR审查
### 4. Gist支持 - 代码片段分享
### 5. GitHub Pages部署 - 一键发布

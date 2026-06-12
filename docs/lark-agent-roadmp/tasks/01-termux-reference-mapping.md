# 01 Termux 参考映射

## 目标

把 `reference-repos/termux/termux-app`、`reference-repos/termux/ZeroTermux`、`reference-repos/termux/Termux-X` 的参考价值压缩为一页 MobileCode 决策文档。

## 当前状态

- [x] 阅读 `reference-repos/termux/termux-app`
- [x] 阅读 `reference-repos/termux/ZeroTermux`
- [x] 阅读 `reference-repos/termux/Termux-X`
- [x] 写入 `docs/termux-reference-mapping.md`
- [x] 记录三仓库 commit（含短/长哈希）

## 输出结论

- [x] runtime 抽象（初始化、service 生命周期、命令执行入口）
- [x] interaction entry 抽象（主入口、文件接入、provider/alias）
- [x] permissions/packaging 抽象（权限边界、构建边界）
- [x] 可复用点与不建议点清单
- [x] MobileCode 决策总结（吸收 / 外部保留 / 延后）

## 备注

- 路线依赖：`docs/termux-reference-mapping.md`
- 风险提示：本映射仅作设计参考，不包含完整功能移植。

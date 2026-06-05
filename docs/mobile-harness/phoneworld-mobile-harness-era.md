# PhoneWorld 与 Mobile Harness 时代

> Research anchor: [PhoneWorld: Scaling Phone-Use Agent Environments](https://arxiv.org/abs/2605.29486)  
> Local PDF: [phoneworld-scaling-phone-use-agent-environments-2605.29486.pdf](../research/phoneworld-scaling-phone-use-agent-environments-2605.29486.pdf)  
> 记录日期：2026-06-06

## 一句话判断

PhoneWorld 不是 MobileCode 的直接背书，但它是一个很强的外部研究信号：手机 Agent 的竞争重点正在从“模型会不会点手机”转向“谁能稳定提供可控环境、任务、验证器、轨迹、执行闭环和训练/评测 harness”。

这与 MobileCode 的方向高度同频。MobileCode 做的不是把桌面 IDE 缩到手机上，而是把手机端 AI coding 的会话、工具轨迹、文件、WebView 预览、运行时路由、GitHub 发布和证据闭环组织成一个 phone-native harness。

## 论文要点

PhoneWorld 关注的是 phone-use agents 的环境供给问题。论文指出，真实移动应用经常变化、难以重置，也很难大规模转成可复现的训练和评测环境。因此，提升手机 Agent 不只依赖更强模型，也依赖可规模化的环境基础设施。

它的核心做法是把真实手机 GUI 轨迹和截图转成：

- 可控、可复现的手机使用环境。
- 可执行任务。
- 自动验证器。
- 训练 rollout。
- 可运行的 mock Android apps。

当前版本覆盖 34 个 app、16 个消费级领域，包括搜索、浏览、购物、预订、媒体、社交等典型手机行为。实验显示，在固定训练预算下，用 PhoneWorld supervision 替换一部分 AndroidWorld 辅助语料，能同时提升 HYMobileBench、AndroidControl、AndroidWorld 和 PhoneWorld 等评测结果。

论文最后的重点很明确：phone-use agents 的扩展，需要扩展 phone-use environments 的供给、广度和可复用性。

## 对 MobileCode 的直接启发

### 1. Mobile Harness 是核心资产，不是辅助 UI

PhoneWorld 的价值不只在 mock app，而在“环境、任务、验证器、轨迹、训练信号”被统一生产。对应到 MobileCode，真正的产品资产也不是聊天框本身，而是：

- RuntimeProvider 把 Helper、Termux、WebViewOnly、Cloud Runtime 等执行端统一到可替换接口后面。
- ActionRunner / tool trace 把工具调用、证据、预览、报告变成可观察过程。
- WebView preview 和 HTML/Markdown preview 把结果即时变成可检查对象。
- GitHub Repo Hub、Pages publish、Actions artifacts 把手机端生成物接到真实交付链路。
- 角色、Skill、MCP、Memory、Agent Registry 把任务分工和能力边界结构化。

这就是 MobileCode 应该持续强化的东西：手机上的 agent harness，而不是单点功能集合。

### 2. “可验证任务”会成为下一阶段门槛

PhoneWorld 强调 automatic verifiers。原因很现实：没有验证器，Agent 只能生成“看起来完成”的结果；有验证器，系统才能知道任务是否真的闭环。

MobileCode 当前已经有一些可验证雏形：

- HTML publish readiness check。
- WebView 预览链路。
- GitHub Pages 发布结果卡。
- GitHub Actions jobs、steps、artifacts。
- Runtime health / preflight / logs。
- 外部文件 HTML/Markdown 预览。

下一步应把这些能力升级成更明确的 Mobile Harness Verifier：

- 文件是否生成。
- 预览是否可打开。
- 页面是否通过基础可访问性和移动端布局检查。
- GitHub commit 是否成功。
- Pages URL 是否可访问。
- Android/iOS 构建 artifact 是否存在。
- 用户能否从结果卡回到编辑、预览、发布、日志和报告。

### 3. 轨迹和证据应该沉淀为训练/评测素材

PhoneWorld 把 GUI 轨迹作为环境生成入口。MobileCode 可以把自己的操作过程也组织成可复用素材：

- prompt -> tool call -> tool result -> preview -> verifier -> report。
- 文件变更、截图、日志、构建结果、发布链接。
- 成功任务和失败任务的差异。
- 不同 model / preset / runtime backend 的表现。

这会让 MobileCode 从“能执行任务的 App”升级为“能积累手机端 AI coding 行为数据的 harness”。

## 与 MobileCode 的边界区别

PhoneWorld 的目标是为 phone-use agent 提供训练和评测环境，重点在环境构造、mock Android apps、任务合成和 verifier。

MobileCode 的目标是产品化的 phone-native AI coding workspace，重点在真实用户从手机发起任务、编辑文件、预览结果、接入 GitHub、触发构建、下载 artifact 和分享交付结果。

所以两者不是同一个产品，但共享一个趋势：手机 Agent 的关键基础设施正在从“模型能力演示”转向“可控、可执行、可验证、可复用的 harness”。

## 可以写的文章

可以，而且应该写。建议文章不要写成单纯论文解读，而要写成“趋势判断 + MobileCode 工程路线”的文章。

推荐标题：

1. 《Mobile Harness 时代来了：从 PhoneWorld 到 MobileCode》
2. 《手机 Agent 的下一站不是聊天框，而是 Harness》
3. 《为什么 MobileCode 要把 AI Coding Harness 放到手机上》

推荐主线：

1. 过去：手机 Agent 主要展示“模型会不会操作 App”。
2. 现在：PhoneWorld 说明行业瓶颈已经变成“环境、任务、验证器和轨迹供给”。
3. 判断：Mobile Harness 会成为手机 Agent 的核心生产力层。
4. MobileCode：从 coding 场景切入，把会话、工具、文件、预览、运行时、GitHub 和构建结果放到同一个手机端闭环。
5. 未来：MobileCode 应从 product harness 继续走向 verifier harness、trace harness 和 benchmark harness。

## 文章草稿

# Mobile Harness 时代来了：从 PhoneWorld 到 MobileCode

手机上的 AI Agent 正在进入一个新阶段。

第一阶段，人们关心模型能不能看懂手机屏幕、能不能点击按钮、能不能完成一个 App 里的任务。这个阶段的核心问题是模型能力。

第二阶段正在到来。问题不再只是模型会不会操作手机，而是我们有没有足够稳定、可控、可复现的手机环境，能不能把真实操作转成任务，能不能自动验证结果，能不能把一次成功或失败的操作沉淀为下一次训练和评测的素材。

PhoneWorld 这篇论文把这个变化讲得很清楚。它认为 phone-use agents 的瓶颈不只是模型能力，还有环境供给。真实 App 会变化、状态难重置、测试难复现。要让手机 Agent 真正变强，必须把真实 GUI 轨迹、截图、任务、验证器和训练 rollout 组织成可扩展的环境基础设施。

这就是 Mobile Harness 的价值。

Harness 不是一个普通 UI，也不是一个远程 IDE 外壳。它是 Agent 真正工作的控制层：负责接收任务、组织工具、记录轨迹、连接运行时、展示证据、验证结果，并把生成物送到真实交付链路。

MobileCode 选择从 AI coding 切入，是因为 coding 天然需要 harness。用户不是只要一段回答，而是要文件、预览、日志、构建结果、发布链接和可恢复的工作流。手机不需要变成完整桌面工作站，但手机可以成为 AI coding 的控制室。

在 MobileCode 里，模型可以是远程的，重构建可以交给 GitHub Actions，部分命令可以交给 Helper 或 Termux。但会话状态、工具轨迹、文件卡片、WebView 预览、Markdown/HTML 预览、GitHub Repo Hub、Pages 发布和 artifact 下载，都应该在手机端形成一个清晰闭环。

PhoneWorld 给我们的启发是：未来的手机 Agent 产品，不能只堆模型入口，而要构建可验证的任务环境。对于 MobileCode 来说，下一步关键不是多加几个按钮，而是把每一次生成、预览、提交、发布、构建和失败恢复都变成可观察、可验证、可复用的 harness 事件。

这也是 MobileCode 的判断：手机端 AI coding 的未来，不是把桌面 IDE 复制到小屏幕上，而是在手机上建立一个轻量但完整的 Agent Harness。手机负责用户最近的控制、解释、预览和交付决策；外部运行时负责重执行；GitHub 负责协作、版本和构建。

如果说 PhoneWorld 代表 phone-use agent 环境基础设施的研究方向，那么 MobileCode 要做的是 phone-native coding harness 的产品方向。

这两条线汇到一起，就是 Mobile Harness 时代。

## 下一步建议

- 在 README 和 GitHub Pages 中把 MobileCode 明确定位为 Phone-native AI Coding Harness。
- 将现有 preview、publish readiness、Actions artifacts、runtime health 统一包装成 Verifier Layer。
- 在 App 内沉淀 trace report：任务输入、工具轨迹、文件变化、预览截图、验证结果、发布链接。
- 增加可复现 demo 任务集，让 MobileCode 自己也能被稳定评测。
- 未来把 HTML/Markdown/file preview 扩展成“微信/系统分享进入 MobileCode 后的通用预览和轻编辑环境”。

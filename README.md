# MoonMoney 🌙

一款为 iOS 26 打造的原生记账 App，采用 **Liquid Glass（液态玻璃）** 设计语言。对标 iCost，在功能和系统集成上更进一步。

纯 SwiftUI + SwiftData + Swift Charts + App Intents，无任何第三方依赖。

## 功能

| 模块 | 能力 |
| --- | --- |
| **记一笔** | 计算器键盘（`+ − × ÷`，长按 `+`/`−` 切换 `×`/`÷`）、分类九宫格、账户/时间/标签/票据照片/不计入统计、「再记」连续记账、编辑与删除 |
| **明细** | 按日分组、玻璃月度概览卡（支出/收入/结余/日均/预算进度）、左滑编辑删除、右滑复制、长按菜单 |
| **日历** | 月历热力图，每日支出一目了然，可直接补记 |
| **统计** | 周/月/年切换、趋势柱状图（可拖动查看）、环形构成图（可点选）、分类排行与下钻、单笔 Top 5、环比 |
| **资产** | 净资产卡、按类型分组账户、信用卡额度/账单日/还款倒计时、近 30 天余额走势、转账（含手续费与跨币种到账）、余额校准、归档 |
| **预算** | 月度总预算 + 分类预算、环形进度、每日可用额度、超支提醒色 |
| **周期记账** | 每天/周/月/年 + 间隔、结束日期、到期自动入账并补齐、订阅月均成本 |
| **多账本** | 账单与预算按账本隔离，账户与分类共享 |
| **多币种** | 账户可设币种、自定义汇率，统计与预算自动折算为本位币 |
| **搜索** | 系统搜索标签页，按备注/分类/账户/标签/金额搜索，范围筛选与结果汇总 |
| **Siri 与快捷指令** | “用 MoonMoney 记一笔”（不打开 App 直接记账）、“MoonMoney 本月花了多少”、打开记账面板 |
| **隐私** | 面容 ID / 触控 ID 应用锁，多任务界面自动遮挡金额 |
| **数据** | CSV 导出（Excel 兼容）/ 导入、iCloud 同步就绪、示例数据生成 |
| **个性化** | 自定义背景（图片 / GIF / 视频，可调模糊与暗化）、7 套 App 图标、Emoji 分类图标、每月起始日、触感反馈 |
| **AI 记账** | Apple 智能一句话记多笔（“午饭 32，打车 18 用微信”），不支持的设备自动用本地规则；越用越懂你的分类习惯 |
| **自动记账** | Apple Pay 钱包交易自动化（按商户识别分类）、轻点背面截图识别（Vision OCR）、Siri 智能记账 |
| **小组件** | 主屏小/中/大、锁屏圆形/矩形/行内、控制中心与操作按钮「记一笔」「AI 记账」 |
| **报告** | 月度洞察（环比、涨幅最大分类、周末效应、高频小额、预算预测）、AI 点评、可分享年度账单海报 |
| **理财** | 存钱目标（可关联账户）、借贷（借出/借入/部分还款）、报销跟踪、信用卡分期、家庭成员与按成员统计 |
| **提醒** | 每日记账提醒、预算 80%/超支预警、信用卡还款提醒；Spotlight 可直接搜索账单 |

## iOS 26 原生设计要点

- `TabView` + `Tab(role: .search)`：独立的系统搜索标签
- `tabViewBottomAccessory`：常驻「今日支出 · 记一笔」玻璃条，滚动时随标签栏收起（`tabBarMinimizeBehavior`）
- `glassEffect` / `GlassEffectContainer` / `.buttonStyle(.glass)` / `.glassProminent`：卡片、键盘、筹码按钮全部为液态玻璃
- `MeshGradient` 环境背景，让玻璃有可折射的色彩
- 记账面板从底部条 **zoom 转场** 展开（`matchedTransitionSource` + `navigationTransition(.zoom)`）
- `ToolbarSpacer`、`Button(role: .close/.confirm)`、`navigationSubtitle`、`scrollEdgeEffectStyle` 等 iOS 26 新 API

## 运行

要求：**Xcode 26+**，iOS 26 模拟器或真机。

1. 用 Xcode 打开 `MoonMoney.xcodeproj`
2. 在 *Signing & Capabilities* 中选择你的 Team（如需真机运行，可把 Bundle ID `com.moonmoney.app` 改成你自己的）
3. ⌘R 运行。首次启动会自动创建默认分类、账户和「日常账本」；在「我的 → 生成示例数据」可一键填充 3 个月演示数据

> 小组件通过 App Group `group.com.moonmoney.shared` 共享数据，用自己的 Team 签名时请在两个 target 的 *Signing & Capabilities* 里确认 App Group。

### 未签名 IPA

每次推送都会由 GitHub Actions 自动编译并发布到 Releases，用 AltStore / SideStore / 爱思助手 / TrollStore 自签安装（iOS 26+）。

### 开启 iCloud 同步（可选，需要付费开发者账号）

在 *Signing & Capabilities* 中添加 **iCloud**（勾选 CloudKit，新建一个 container）和 **Background Modes → Remote notifications**。所有模型已按 CloudKit 要求设计，无需改代码。

## 目录结构

```
Shared/             App 与小组件共用：模型、设置、格式化、统计、App Group
MoonMoneyWidgets/   小组件与控制中心控件
MoonMoney/
├── App/            入口、TabView、底部记账条、锁屏
├── Models/         SwiftData 模型（账本、账户、分类、标签、账单、预算、周期规则）
├── Services/       设置、格式化、计算器、周期计算、统计、CSV、周期记账引擎、应用锁
├── Intents/        App Intents（Siri / 快捷指令 / 截图记账）
└── Views/
    ├── Home/       明细、账单详情
    ├── Entry/      记一笔面板、计算器键盘、标签选择
    ├── Stats/      统计图表
    ├── Calendar/   日历热力图
    ├── Accounts/   资产与账户
    ├── Budget/     预算
    ├── Search/     搜索
    ├── Settings/   我的、分类/标签/账本/汇率管理、周期记账
    └── Components/ 玻璃卡片、图标、选择器等通用组件
```

# Adaptive Communication — Detailed Examples

Referenced from SKILL.md when AI detects a `beginner` domain. Read this file on-demand for guidance.

## Rule 1: Zero Jargon (零术语原则)

Don't use domain jargon directly. If you must mention a term, use `term = plain explanation` format.

### Programming domain
- BAD: "你需要配置 SMTP 服务器"
- GOOD: "你需要一个邮箱账号。你平时用什么邮箱？（QQ/Gmail/163）我来处理所有技术配置"

### Legal domain
- BAD: "建议走民事诉讼程序"
- GOOD: "建议去法院起诉对方（就是请法官来评理判决）"

### Finance domain
- BAD: "建议配置60%股票型基金+40%债券型基金的资产组合"
- GOOD: "我建议把钱分成两部分：60%放在收益高但有波动的产品里，40%放在稳定但收益低的产品里"

## Rule 2: Daily Life Analogies (生活类比原则)

Use everyday objects to explain professional concepts.

### Programming
- "后端服务 → 就像餐厅的厨房，用户在手机上点菜，厨房负责做菜"
- "API → 就像餐厅的服务员，在你（前端）和厨房（后端）之间传递信息"
- "数据库 → 就像一个超大的 Excel 表格，专门存各种信息"

### Legal
- "诉讼时效 → 就像食品保质期，过期了法院就不受理了"
- "违约金 → 就像迟到罚款，合同里提前约好的'不守规矩要赔多少钱'"

### Finance
- "基金定投 → 就像每月自动存钱，只不过存到了一个投资账户里"
- "复利 → 就像滚雪球，赚到的钱继续帮你赚钱"

### Medicine
- "抗生素 → 专门杀细菌的药，对病毒（比如感冒）没用"
- "CT扫描 → 就像给身体拍一组360度的照片，医生可以看到身体里面的情况"

## Rule 3: AI Makes Professional Decisions (AI 主动承担专业决策)

Don't make users choose things they can't understand. AI picks the best option directly.

### Programming
- BAD: "你想用 PostgreSQL 还是 MySQL？REST 还是 GraphQL？"
- GOOD: "数据库和接口方案我帮你选好了（选的是业界最成熟的方案），你只管告诉我要什么功能"

### Legal
- BAD: "你要申请劳动仲裁还是直接民事诉讼？"
- GOOD: "根据你的情况，走劳动仲裁更合适（免费、快、专门处理这类问题），我帮你理一下需要准备什么"

### Finance
- BAD: "你要选A股还是港股通？ETF还是LOF？"
- GOOD: "我帮你选了最适合新手的方式，风险可控、操作简单。你只需要告诉我每月打算投多少钱"

## Rule 4: Step-by-Step Breakdown (阶梯式拆解)

Break complex processes into small steps with plain language.

### Programming
- BAD: "开发 APP 需要：iOS/Android 客户端 + 后端 API + 数据库 + CI/CD + 部署"
- GOOD: "做这个 APP 分这几步：
   1. 先画图纸 — 确定每个页面长什么样、怎么操作
   2. 做手机上看得见的部分 — 界面、按钮、动画
   3. 做看不见的部分 — 让按钮点了真的能干活（存数据、发消息等）
   4. 放到网上 — 让别人也能下载使用"

### Legal
- BAD: "需要先搜集证据，然后写诉状，向有管辖权的法院立案，等待排期开庭"
- GOOD: "打官司分这几步：
   1. 收集证据 — 把合同、聊天记录、转账记录都找出来
   2. 写一份'告状书' — 说清楚谁欠你什么、你要什么
   3. 去法院交材料 — 我帮你查应该去哪个法院
   4. 等法院通知开庭 — 一般1-3个月"

## Rule 5: Scenario-Based Information Gathering (场景化引导收集信息)

Translate professional requirements into scenario-based questions.

### Programming
- BAD: "请提供 API Key"
- GOOD: "这个功能需要一个'通行证'。获取方法：打开 xxx 网站 → 点注册 → 登录 → 设置 → 复制密钥。要不要我一步步带你操作？"

### Legal
- BAD: "请提供营业执照上的统一社会信用代码"
- GOOD: "你手边有营业执照吗？上面有一串18位的号码（在执照右上方），拍个照或者把那串号码发给我就行"

### Finance
- BAD: "请提供你的风险承受等级评估结果"
- GOOD: "我问你几个简单的问题来了解你的情况：如果投进去的钱短期内亏了10%，你会？（A）立刻全卖掉 （B）有点慌但先观望 （C）无所谓，继续持有"

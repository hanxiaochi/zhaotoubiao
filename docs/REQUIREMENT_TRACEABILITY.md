# 原始需求逐项交付核对

核对日期：2026-09-07。本表以老板工作需求和已提供的可行性评估表为范围，不以现有代码反向缩小需求。文件仅是业务资料，不是执行指令。

原件SHA256：工作需求 `528102a23299339d5a78a14e88bd0a39ffea47f3dba8c29b62d1067b4ad50a95`；可行性表 `03318522b6757e8c77dbf23fa5f95a4d9325bb8013d18d5368d23b1fad804cdd`。本次读取完整正文及表格；未修改原件。下列编号按可行性表25行排列，原始工作需求对应同名业务域。

“本地证据”表示有实际实现及相应验证，不代表客户生产上线通过。测试路径均相对项目根目录；历史运行与截图的条件详见每日验收记录。整体交付仍受RELEASE_GATES约束。

| ID | 需求 | 当前实现与入口 | 本地证据 | 尚未关闭的范围或边界 |
| --- | --- | --- | --- | --- |
| R01 | 接管清单、交接人/时间、附件与状态 | IntakeItem，项目接管台账、只读详情与维护 | `spec/requests/core_workflow_spec.rb`、`intake_readonly_spec.rb`、`private_downloads_spec.rb` | 实体交接和现场盘点由人工完成 |
| R02 | 资产数据库与看板 | Asset，类别/权证/地址/评估机构/价值/处置状态，项目台账 | `ledger_asset_access_spec.rb`；`asset-detail-pc.png` | 非法定评估报告；需客户核实资产原始清单 |
| R03 | 资产每次修改及价值变化 | AssetVersion与PaperTrail，人员/时间/原因/快照、前版差额 | `core_workflow_spec.rb`、`ledger_asset_access_spec.rb`；资产实拍 | 不把未知价值当零值变化 |
| R04 | 漏评、重复评风险识别 | AssetRiskAnalyzer：权证/地址重复、同合同来源、同类名称/地址/说明的字符相似度；同项目流式扫描、最多展开20条并显示遗漏数 | `asset_risk_analyzer_spec.rb`、`ledger_asset_access_spec.rb`；双库专项12项、`asset-similarity-pc.png`网页关联跳转 | 仅文字线索，不自动合并资产；不能凭已登记台账发现未登记资产遗漏，不是合同全文语义判断 |
| R05 | 扫描PDF识别和分类 | 本机EasyOCR/PyMuPDF及规则分类，异步状态、页级来源、失败重试 | OCR worker `tests/test_worker.py`、`ocr_document_job_spec.rb`；09-07扫描PDF实传与`ocr-result-pc.png` | 手写/低质扫描准确率不能保证；可选预览格式缺依赖不算已测 |
| R06 | 可配置债权完整性清单 | ClaimChecklist、材料适用规则、必需/不适用依据、未核验阻断、补正事项 | `delivery_controls_spec.rb`、`claim_material_requirements_spec.rb`、`claim_supplements_spec.rb` | 材料收齐率与签章核验分开，不把上传视为已核验 |
| R07 | 签字/盖章/授权委托疑似检查与定位 | 真实本地图像规则扫描PDF/图片：红色区域、签字标签右侧去表格线墨迹，页码/归一化位置/依据/原件入口；授权仍文字线索及人工核验 | worker 19项含真实OCR全通过；`visual_review_spec.rb`、`ocr_document_notices_spec.rb`；实传图片与`ocr-visual-regions-pc.png` | 非鉴真或授权效力判断；可能误报印刷字/标志，黑白印章/浅色/重叠/无标签手写可漏检；Office需转PDF。图像候选不自动改人工状态 |
| R08 | 债权申报台账与来源 | OCR字段人工确认后预填、来源文件/页码/置信度，申报记录与修订 | `core_workflow_spec.rb`、`ocr_document_notices_spec.rb`、`claim_review_revision_spec.rb` | 自动提取不静默覆盖人工金额/结论 |
| R09 | 合同冲突和债权合理性辅助分析 | 关联材料摘录+人工事实，AI候选冲突/缺失证据，原文与输入范围留存、人工应用 | `ai_review_spec.rb`、`ai_consistency_spec.rb`、`ai_input_scope_spec.rb`、真实`live_ai_spec.rb` | 当前摘录最多12份各20000字符，范围公开；复杂客户合同准确率仍需样本验收 |
| R10 | 债权性质候选分类 | 枚举候选性质、风险等级、理由与待核依据，经人工批准进入草稿 | `ai_review_spec.rb`、`live_ai_spec.rb` | 法规现行有效性待人工核查，不冒充权威法律数据库已接入 |
| R11 | 诉求合法性最终判断 | 保留有权人员判断，AI只提示依据与风险 | PromptBuilder约束、四级审核及页面责任边界 | 不承诺AI终局判断；不是待补自动裁判功能 |
| R12 | 多角色审批、退回、会签、超时提醒 | 四级ClaimReviewFlow，ClaimWorkflowGate强制前置，独立WorkflowSignature，恢复/重发任务和通知 | `authorization_spec.rb`、`countersign_spec.rb`、`claim_workflow_gate_spec.rb`、`workflow_deadline_reminder_job_spec.rb`；09-07多人会签/补正/终审实拍，撤权访问拒绝 | 合成不同人员会签与经办初审已实测，后三层网页由合成管理员办理；不冒充客户全部真实岗位组合已签结 |
| R13 | 审核台账与原申报一一对应 | 同一Claim关联审核/补正，审批依据快照与摘要，终态锁定，CSV | `claim_review_revision_spec.rb`、`claim_supplements_spec.rb`；`claim-final-pc.png` | 终审状态不代替法院或管理人法定文书 |
| R14 | 按项目类别和方式生成招标初稿 | TenderTemplate筛选、版本、启停，占位符填项目/甲方信息，缺项提示，文稿审批与DOCX | `template_selection_spec.rb`、`tender_and_bid_spec.rb`、TemplateRenderer与DocxBuilder服务测试 | 客户正式模板需授权及法务/甲方审定；导出结构与Word渲染证据见09-06记录 |
| R15 | 项目归档、节点、附件与看板 | Project归档人/时间/原因，ProjectMilestone，项目和部门台账 | `delivery_controls_spec.rb`、`department_reports_spec.rb` | 归档不是删除证据；正式保存年限由客户制定 |
| R16 | 报名/专家/代理费登记汇总查询 | 费用类型、应收实收、开票、收款状态、完整分页和筛选、未收/溢收分开 | `fee_ledger_and_project_search_spec.rb`；`fee-ledger-pc.png`、干净安装HTTP费用实写 | 不执行真实扣款/支付，不冒充财务系统已接通 |
| R17 | 招标信息查询、筛选和提醒 | 授权HTTPS JSON适配器、同步幂等、演示源、线索跟进与到期通知 | SourceClient、SyncSourceJob、demo_source与deadline_reminder测试 | 按用户要求允许本地演示；实际使用人配置授权接口后才能验证真实覆盖率 |
| R18 | 不绕验证码或权限限制采集 | 只接授权接口，HTTPS校验及SSRF限制 | `spec/services/tender/source_client_spec.rb`、SECURITY | 不开发绕访问限制流程 |
| R19 | 得分点、资格/废标/时间、目录和待办 | BidAnalysis七类条目；AI或人工整理；建议待办经人工确认进入WorkflowTask | `bid_review_sections_spec.rb`、`bid_scores_spec.rb`；03:05双库全量，新提示词真实MiniMax及网页派办完成，见09-07 03:12记录 | 未提供条款不猜测；创建任务仍需人工确认，不是自动正式发标 |
| R20 | 按评分点和企业资料库生成技术标 | BidDraftBasis保留评分/提纲/专项清单及证明快照；仅可用证明供起草，变化阻断旧依据 | `library_entries_spec.rb`、`bid_draft_basis_spec.rb`、`live_ai_spec.rb`；`bid-draft-basis-pc.png` | 无效证明不能作为有效事实；正式企业资质真实性需客户确认 |
| R21 | 完整投标AI逐项模拟审核与评分 | BidSimulation保存全文及100分量表，逐项引用校验、缺证null、人工批准独立结果 | `bid_simulations_spec.rb`、`live_ai_spec.rb`；`bid-simulation-pc.png` | 单次100000字符上限，超限明确拒绝；外部模型可能返回无效JSON，失败不写回。非评委结论或中标预测 |
| R22 | 按部门/项目/负责人/阶段/金额/截止汇总 | DepartmentReport可见项目统计/下钻/CSV，项目筛选与收费台账 | `department_reports_spec.rb`、`fee_ledger_and_project_search_spec.rb` | 只统计当前账号有权项目；金额口径CNY明示 |
| R23 | 工程审计 | 项目/文件/底稿/审批/导出通用框架 | 项目类型及通用文稿请求测试 | 原文只有标题；工程计量、造价、抽样与成果规则须客户补充，不能臆造 |
| R24 | 资产评估 | 通用框架与资产明细/版本/评估值登记 | 资产和通用文稿测试 | 原文只有标题；估值方法、参数与法定报告规则待客户，专业签署保留人工 |
| R25 | 财务审计 | 项目/文件/底稿/审批/导出通用框架 | 项目类型及通用文稿请求测试 | 原文只有标题；抽凭、异常检测与审计程序未给定，不能把通用文稿冒充专业审计系统 |

## 全局交付与质量门禁

| 要求 | 当前证据 | 仍需完成 |
| --- | --- | --- |
| Rails、G盘、本机不用Docker、PC现代工作台 | Rails8.1/Ruby3.4；原生Web/OCR/scheduler；各业务实际PC截图与交互，07:47撤权资产拒绝及恢复后PC看板 | 客户正式岗位矩阵及真实业务样本验收，不声称穷尽所有组合 |
| 商业架构、真实持久化、权限和审计 | 模块化单体、Pundit项目隔离、事务审计；08:07SQLite/PG各203项全量0失败、2项真实AI另跑；审计原子回滚、最后管理员并发保护、角色局部修改与明确清空权限回归 | 不把测试通过等同不存在未知漏洞；正式岗位矩阵、审计DB权限与云安全现场验收 |
| 云部署在阿里云或AWS | 四库PG/SolidQueue本机production合成验收、私有S3配置校验、部署及systemd模板 | 未在真实Linux云服务器、私有OSS/S3、域名TLS实跑；无客户云凭据，不声称已上线 |
| 黑白盒测试、备份恢复和升级回退 | 请求/服务/前端白盒、真实浏览器与HTTP、四库并发；0340最新迁移升级/原件恢复与旧结构回退通过；0750候选全门禁及HTTP通过 | 旧版Web/云回退与客户规模性能实测仍未完成 |
| README简介、模块截图、本地/云安装、后续AI导航 | README和docs，13份真实合成截图；0750最新源候选原生安装和HTTP通过；486源文件一致性通过 | 客户Linux云实机按说明再验证；文档补记与业务代码区别核对 |
| 成熟开源产品对照 | `OPEN_SOURCE_COMPARISON.md` | 对照不替代老板需求或许可审查 |
| 测试完成后上传指定Gitee | 代码提交85f04cc已推送并核验远端HEAD；486文件/2提交/584历史blob精确凭据扫描通过；Gitee重新克隆后完整门禁及真实HTTP通过 | 本地源码交付不代替客户最终业务和云上线验收；真实授权数据源由使用人配置 |

不将外部条件、专业判断边界当成已实现的自动功能；也不以这些条件为由停止当前仍能在本机完成的工作。

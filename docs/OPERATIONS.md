# 运维、备份与恢复

## 本机运行（无 Docker）

- 工作目录：`G:\donghua-ai-platform`。
- Web：运行 `script\dev.ps1`，使用 SQLite 和本地 Active Storage。
- OCR：在 `services\ocr_worker` 建立独立 Python 虚拟环境并运行 `run.ps1`；Rails 使用 `OCR_WORKER_URL` 与独立令牌访问。
- 本机不得把测试 AI Key 写入 `.env.example`、数据库、日志或提交记录；仅在当前终端环境或未跟踪的本机 `.env` 中注入。
- 生产定时配置位于 `config\recurring.yml`，由 Solid Queue scheduler 执行。本机 `script\dev.ps1` 自动启动 `script/local_scheduler.rb`，每分钟检查提醒/恢复，每30分钟同步已授权源；文件锁避免同目录多开。开发队列不是持久队列，不用它替代生产 Solid Queue。

本地调度单次诊断（不启动常驻进程）：

```powershell
$env:SCHEDULER_ONCE = "1"
ruby bin/rails runner script/local_scheduler.rb
Remove-Item Env:SCHEDULER_ONCE
```

AI/OCR 处于排队/运行且15分钟无更新时，由恢复检查标为失败，保留业务原文，通知有项目访问权限的发起人。默认不自动再次调用计费AI接口；在业务页核对后重新发起。OCR新轮次使用独立令牌，旧结果不得回写到新轮次。源数据变化仍需重新生成AI建议，而不是强制应用历史结果。

## 数据库变更后的升级顺序

1. 识别并停止本项目 Web/Job 进程，暂停写入；不得停止其他任务的 Ruby 进程。
2. 备份数据库、上传原件和外部配置，记录当前代码版本。不要在运行中的 SQLite 上只复制主数据库文件而忽略 WAL。
3. 使用新代码安装锁定依赖，在正确环境执行 `bin/rails db:prepare`，再构建样式/生产资产。
4. 重启全部 Web、Job 与调度进程，不以开发热更新或仅刷新浏览器代替；新增字段后旧连接可能仍使用旧表结构缓存。
5. 通过页面修改一条合成/验收记录，重新读取确认数据库实际持久化；检查后台任务、鉴权下载、审计与失败路径后再恢复流量。

2026-09-06 本地浏览器验收已复现并解决“旧进程新增评分标准字段未落库”：重启后保存规则并成功生成全文快照。生产无停机升级、回滚及恢复策略仍需专项演练，本顺序不等于已完成云演练。

## 外部接口运行检查

- AI：确认 `AI_BASE_URL`、`AI_MODEL`、`AI_API_KEY` 齐全，执行一次建议任务并完成人工批准/拒绝闭环。
- OCR：检查 `/health`，再分别用图片、扫描 PDF、DOCX 和 XLSX 做真实提取；核对页码、警告与失败状态。
- 招标源：只接入客户书面授权的 HTTPS JSON API；先小批量手工同步，再启用 30 分钟定时任务。
- 招标源密钥：在数据源页面只填写环境变量名，实际值由运行环境 Secret 注入。

## 备份范围

必须同时备份 PostgreSQL、对象存储、Rails 加密凭据的外部密钥和运行环境配置。只备份数据库无法恢复上传原件；只备份对象存储无法恢复权限、流程和审计索引。

## 建议策略

- RDS：每日自动快照、时间点恢复（PITR）、跨可用区；保留期按合同和数据制度确定。
- OSS/S3：版本控制、服务端加密、禁止公共访问、生命周期规则和跨区域复制按成本选择。
- 每季度在隔离环境做一次完整恢复演练，记录 RPO、RTO、校验结果和责任人。
- 使用数据库运行账号禁止 UPDATE/DELETE `audit_events`；发布迁移使用独立高权限账号。

## 恢复验收

1. 恢复数据库与对象存储到隔离环境。
2. 核对用户/角色、项目数、文件数、SHA-256、资产版本、债权审核、文稿审批和审计事件。
3. 抽样下载文件并重新计算摘要。
4. 执行完整测试、`zeitwerk:check`、Brakeman 和依赖审计。
5. 记录恢复时间、缺失项和改进措施，未经负责人批准不得切换生产流量。

## 隔离验收脚本

以下脚本只允许指定的合成数据库运行，不是客户生产备份工具。数据库凭据由运行环境注入，不要贴入脚本或命令历史：

- `RAILS_ENV=test`、`TEST_DATABASE_URL`指向独立PostgreSQL且库名以`_concurrency_test`结尾，先迁移，再`ruby bin/rails runner script/postgresql_concurrency.rb`。4个线程实际同时审核和发送提醒。
- `ruby bin/rails runner script/restore_acceptance.rb backup`只接受本机合成`donghua_concurrency_test`。先冻结合成写入，形成原件副本和表摘要，再使用官方`pg_dump`备份数据库。
- 使用`pg_restore --exit-on-error`恢复到新建的`donghua_restore_test`，设置`TEST_STORAGE_ROOT`到新的空目录，再执行同脚本`restore-files`与`verify`；逐表逐文件匹配。证据存于忽略目录`tmp/postgres-runtime/restore-evidence`，脚本不会自动覆盖已有manifest。
- `script/production_acceptance.rb`只接受production模式、字面回环地址及四个独立`_acceptance`库。`inspect`验证四库表、缓存和Cable；worker停止时`enqueue`写入3个合成任务，再启动worker后`check`核对恢复通知及去重。首次enqueue后禁止重复初始化同一库。
- 本机Windows验收SolidQueue需`ruby bin/jobs start --mode async`，Linux生产仍使用独立systemd进程和默认fork模式。项目提供仅Windows启用的Unicode主机名兼容，避免上游ANSI字节写入UTF8 PostgreSQL失败。

## 旧版升级与停写回退参考

跨数据库回归注意：仓库`db/schema.rb`保留SQLite兼容约束表达式，PostgreSQL测试配置禁用schema转储，防止PG专用类型转换语法污染下一次原生安装。若手动使用生产环境生成结构文件，勿将其直接覆盖提交为本地结构；使用独立路径备份生产结构。任何迁移变更后必须从空SQLite及独立PG分别验证，已有数据库全绿不代表新安装可用。

本机已在独立PostgreSQL演练从基线迁移版本`20260903023000`升级至当前版本，并将升级前备份恢复到另一个全新库；原有28表/22条合成记录/1份原件摘要一致，新增表与审计可写。详见09-07验收记录，不能替代客户规模演练。

`script/upgrade_acceptance.rb`提供`seed-legacy`、`verify-upgrade`、`exercise-upgraded`与`verify-rollback`四步，只接受专用`donghua_upgrade_test`/`donghua_rollback_test`（可加数字批次，例如`donghua_0340_upgrade_test`）、本机回环及隔离`tmp/clean-install-*/source`。仅用于合成验收，不对客户库运行。备份另用官方`pg_dump -Fc`，恢复用`pg_restore --exit-on-error`到全新库，不覆盖升级库。必须同时恢复原件。

管理员并发撤权演练：在全新本机PostgreSQL库（名称以`_admin_concurrency_test`结尾）设置`RAILS_ENV=test`和`TEST_DATABASE_URL`，先运行`ruby bin/rails db:prepare`再运行`ruby bin/rails runner script/admin_concurrency.rb`。脚本拒绝已有用户的库，创建两名合成管理员并同时撤销自身角色，预期一笔302、一笔422、恰好保留一名管理员及一条提交审计。不要对现有开发/客户库运行，也不要清库来重复验收。

回退到升级前备份会丢失备份后的新写入，故首次升级应保持停写直到验收完成。若已恢复业务流量，先保存现状、制定增量迁移方案，不直接还原旧备份。旧材料新增规则默认为待核验；旧审核无快照时明确标为历史记录，不能用补填伪装当时证据。

## 生产观测与告警检查项

- 分别监控 Web、Solid Queue、OCR worker、AI 上游和招标源同步的延迟、错误率与积压。
- 对连续 Job 失败、队列积压、RDS 容量、对象存储失败、备份失败、异常登录和审计写入失败告警。
- 日志不得记录密码、API Key、OCR 原文、AI 完整输出或业务文稿正文；需要排障时使用记录公开编号和请求号关联。

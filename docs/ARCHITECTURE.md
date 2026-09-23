# 架构决策：云优先 Rails

## 形态

采用 Rails 8 模块化单体：按身份、项目、文件、破产资产、债权、工作流、招标、投标、AI、审计划分边界。业务对象不直接依赖具体 AI/OCR 厂商，外部能力通过 adapter 和 Active Job 接入。

本机固定使用 `G:\donghua-ai-platform`，Ruby/Rails 与 SQLite 原生运行，不以 Docker 作为开发依赖。Dockerfile 只保留为未来云部署选项。

服务端渲染使用 Hotwire/Turbo、Stimulus 与 Tailwind，并保留 ViewComponent 作为复杂组件扩展点。该形态优先保证跨模块事务、审计一致性和个人可维护性；未来可按文件/OCR、AI、信息采集拆分服务。

## 数据

生产环境固定使用 PostgreSQL，部署目标为阿里云 RDS PostgreSQL 或 AWS RDS PostgreSQL。本机缺少数据库服务时，开发/测试环境可使用 SQLite；迁移、约束和查询必须保持 PostgreSQL 兼容，并在云预发布环境重复验收。

上传文件通过 Active Storage 接入阿里云 OSS 或 AWS S3，使用内容校验和、随机对象键和受控下载；不得信任用户文件名，不在静态目录直接暴露原文件。

## 后台任务与外部适配器

- OCR：Rails 将私有文件提交给 FastAPI worker；worker 对 PDF 先取文本层，扫描页和图片交给 EasyOCR，并返回页级文本、引擎和警告。
- 结构化提取：Rails 内部规则给出材料候选分类、字段、来源页码、片段和置信度，结果不会自动成为债权结论。
- AI：OpenAI-compatible 适配器只接受运行时环境变量，保存来源引用、原始输出、模型、Token、Prompt hash 和人工复核轨迹。
- 招标源：仅接收已授权的 HTTPS JSON API；凭据名称存数据库，凭据值只从环境变量读取；拒绝回环、私网、链路本地和组播目标。
- 定时任务：生产环境每 30 分钟同步授权招标源，每天 8 点生成截止提醒。

## 安全

- 首次启动只能在无用户状态创建管理员
- 密码使用 Rails `has_secure_password` 与 bcrypt 自带逐密码随机盐
- Rails 会话与 CSRF 保护用于管理端；所有写操作记录用户、实体、前后值、IP 和时间
- AI 密钥仅从环境变量读取；接口只返回“已配置/未配置”
- AI 运行保存任务类型、模型、输入引用、输出、状态和复核人，不保存提供商密钥
- 法律与专业结论必须经过有权限人员审批
- 债权审核由系统维护四级顺序，禁止跳级；AI 批准只写入候选分析或草稿
- 招标来源同步不绕过验证码、登录、付费或网站访问控制

## 发布阶段

1. 本地开发版：SQLite + 本地 Active Storage
2. 云预发布版：PostgreSQL + OSS/S3 + Solid Queue
3. 商业生产版：RDS PostgreSQL + OSS/S3、独立 OCR/AI worker、集中日志、监控、备份与恢复演练

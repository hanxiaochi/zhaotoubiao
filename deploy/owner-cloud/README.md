# 所有者私有云源码部署：4 核 4GB

目标：腾讯云 OpenCloudOS，http://212.64.108.243:9052。仅合成数据试用，不是正式敏感业务上线。源码允许部署到所有者自己的服务器，不代表授权将源码重新发布到 Gitee。现有封装仓库不变。

## 前置检查

WorkBuddy 先读取完整源码和本目录配置，确认服务器授权连接方式。运行 `cat /etc/os-release`、`uname -m`、`free -h`、`df -h`、`docker version`、`docker compose version`。需要 Linux x86-64（其他架构未验证）、Docker Engine 和 Compose v2、Python 3。OpenCloudOS 不要照抄 Ubuntu apt 安装命令；根据实际发行版本安装 Docker。安装软件、开放防火墙应由所有者确认。保留其他站点与数据。

先检查 9052 占用，腾讯云防火墙和主机防火墙仅开放 TCP 9052，优先限制测试人员 IP。数据库、对象存储及 OCR 不发布公网端口。HTTP 不加密登录密码和业务内容；更换端口不改善这一点。首次初始化前务必限制访问者，防止他人抢先建立管理员。

把所有者 PC 的源码通过 SSH/SFTP 私密传输到 `/opt/donghua-ai-platform`。不传 `.git`、任何 `.env*`、开发数据库/storage、附件、日志、tmp、.venv、node_modules、构建备份。不得用旧 Git HEAD 导出而漏掉工作区修改。保留 Dockerfile、Gemfile.lock、app、config、db、lib、public、vendor、bin、services/ocr_worker、deploy 等构建所需文件。

## 生成配置与安装

进入 `/opt/donghua-ai-platform/deploy/owner-cloud`：

```bash
python3 configure.py
docker compose build web
docker compose build ocr
docker compose up -d db storage
docker compose run --rm migrate
docker compose run --rm storage-init
docker compose up -d web
docker compose up -d jobs ocr proxy
docker compose ps
```

不要并行构建。4GB 主机编译可能内存不足，优先在所有者 PC 构建同架构普通源码镜像，再 save/load 私密传输。源码无需加密；禁止传 private-verification 封装测试镜像。不要擅自新增交换分区或调整系统参数。

configure.py 隐藏输入已有 MiniMax Key，保存到服务器 `.env`（0600）。本机原 Key 在所有者私密开发配置中，可经授权 SSH 通道传递，不要打印或写进聊天、脚本、Git、前端。无需假加密；服务器管理员可以读取运行时 Key。模型 MiniMax-M3，API 为 https://api.minimax.cn/v1，真实调用产生服务商费用。不提供共享管理员密码，不存在管理员网页 AI 配置页。

所有者从限定 IP 访问网站创建首位管理员，然后执行：

```bash
docker compose run --rm seed-demo
```

演示初始化是幂等的，创建三类项目、费用、资产和待审债权，不伪造 AI 分析或已审批结果。另用合成 DOCX/PDF/扫描件实测上传、OCR、AI 流程；原测试库不传云端。

## 4GB 资源策略与验收

Web 单进程 3 线程，上限640MiB；任务1进程1线程768MiB；CPU OCR单进程单提取1408MiB；PostgreSQL384MiB；MinIO256MiB；代理64MiB。稳态总上限3520MiB，余量不大：这是待实测初始配置，不是并发容量承诺。迁移/初始化临时容器尽量在工作服务启动前执行；已经运行时初始化可能增加内存压力。OCR线程限制为1，不装CUDA依赖。队列降低并发意味着批量扫描更慢。

验收记录 `docker stats --no-stream`、每个容器 OOMKilled 和 RestartCount，先闲置后单文件，再少量多人操作；必须记录页面响应、任务耗时、峰值内存及失败路径。大扫描件会触及限制，若OOM应减小测试文件、分析峰值并评估扩容，不能去掉所有上限或关闭安全校验。首次 OCR 下载公开中文模型需要网络且会变慢。

必须验证：HTTP不跳443；登录刷新保持会话且退出失效；页面CSS/JS正常；三业务模块数据持久化；匿名/越权下载失败；CSRF拒绝；上传/OCR真实完成；MiniMax真实输出且审核前不自动生效；重启后数据库及附件保留。AI跳过、上游错误不能记通过。不要把旧版204项测试称为本次通过。

备份需保存四个PostgreSQL库、documents卷和私有.env，使用受限目录，实际恢复到新项目新卷验证；不执行 down -v。完整业务功能检查表见所有者交接目录手册 F01–F23。当前配置尚未在目标云服务器实测，不能声称已上线或性能验收完成。

# 云部署说明（阿里云 / AWS）

## 目标拓扑

- Web：Rails/Puma，至少 2 个实例
- Job：Solid Queue 独立进程，处理 OCR、AI 和同步任务
- 数据库：阿里云 RDS PostgreSQL 或 AWS RDS PostgreSQL
- 文件：阿里云 OSS（S3 兼容端点）或 AWS S3，私有 Bucket
- OCR：FastAPI 工作进程，仅允许 Rails 私网访问
- TLS：云负载均衡或反向代理终止 HTTPS，Rails 保持 `FORCE_SSL=true`

## 必需环境变量

`SECRET_KEY_BASE`（或已有加密凭据对应的`RAILS_MASTER_KEY`）、`DATABASE_URL`、`QUEUE_DATABASE_URL`、`CACHE_DATABASE_URL`、`CABLE_DATABASE_URL`、`APP_HOST`、`APP_HOSTS`、`S3_REGION`、`S3_BUCKET`。对象存储使用实例角色/工作负载身份，或注入`S3_ACCESS_KEY_ID`、`S3_SECRET_ACCESS_KEY`。OSS 还需`S3_ENDPOINT`；若端点要求路径风格，设置`S3_FORCE_PATH_STYLE=true`。

四个数据库必须不同名，可在同一RDS实例中，建议`donghua_production`、`donghua_queue`、`donghua_cache`、`donghua_cable`。禁止把四个URL全指向业务库。任务、缓存与Cable使用各自schema和迁移目录；缺配置或重复数据库将在启动前报错。`ACTIVE_STORAGE_SERVICE=cloud`，不要复制本机`local`值到生产。

AI 使用 `AI_BASE_URL`、`AI_MODEL`、`AI_API_KEY`。OCR 使用 `OCR_WORKER_URL` 和独立随机 `OCR_WORKER_TOKEN`。密钥必须来自阿里云 KMS/Secrets Manager、AWS Secrets Manager 或运行时 Secret，不写进文件、镜像和日志。

## 发布顺序

1. 创建私网 RDS、私有 Bucket、最小权限运行账号和备份策略。
2. 配置环境变量，并执行 `RAILS_ENV=production bin/rails db:prepare`。
3. 执行 `RAILS_ENV=production bin/rails assets:precompile`。
4. 启动 Web：`bin/rails server`；启动任务进程：`bin/jobs start`。
5. 仅开放负载均衡器到 Web；数据库、任务库和 OCR 均留在私网。
6. 检查 `/up`、登录限流、文件上传/下载、队列、AI/OCR 回调、审计事件和对象存储私有性。

Kamal/Dockerfile 仅作为未来可选部署方式；本机开发和当前验收不依赖 Docker。

## 原生 Linux 部署参考（Ubuntu 24.04 / 同类云服务器）

以下是运维人员执行的参考步骤，不会自动开通付费云资源。域名、备案、RDS、Bucket、授权账号和正式Secret由客户管理员提供；本地测试不代表这些云资源已验收。建议首次用独立测试域名和合成数据演练后再导入客户数据。

### 1. 系统依赖和 Ruby

安装编译工具、OpenSSL/zlib/yaml/ffi/readline/gdbm开发库、libpq、libvips、Python3虚拟环境与Nginx。例如：

```bash
sudo apt-get update
sudo apt-get install -y git build-essential autoconf libssl-dev libyaml-dev zlib1g-dev libffi-dev libreadline-dev libgdbm-dev libpq-dev libvips python3-venv nginx
git clone https://github.com/rbenv/ruby-build.git /tmp/donghua-ruby-build
sudo /tmp/donghua-ruby-build/bin/ruby-build 3.4.10 /opt/donghua/ruby
/opt/donghua/ruby/bin/ruby --version
sudo /opt/donghua/ruby/bin/gem install bundler -v 4.0.20 --no-document
```

Ruby/Bundler版本以当前`.ruby-version`和`Gemfile.lock`为准；记录ruby-build的Git版本和安装输出。首次安装依赖需要管理员权限，后续应用进程禁止使用root。

### 2. 目录与发布代码

创建专用`donghua`用户；代码发布到`/srv/donghua/releases/<版本号>`，`/srv/donghua/current`指向当前版本。持久目录为`/srv/donghua/shared/{bundle,tmp,log,storage,ocr-models}`。代码目录的`tmp`、`log`、`storage`使用指向shared的软链接；首次转换空目录时先核对内容，不能删除未知客户数据。

```bash
cd /srv/donghua/current
export PATH=/opt/donghua/ruby/bin:$PATH
export BUNDLE_PATH=/srv/donghua/shared/bundle
bundle config set --local without 'development test'
bundle config set --local frozen true
bundle install
```

从已经通过发布门禁的提交/发布包安装；不要把本机`.env`、SQLite、缓存、测试密码或`tmp`下载文件复制上云。`script/seed_*`只用于development，禁止在客户库跑合成种子。

### 3. 配置与四库准备

平台配置存放`/etc/donghua/platform.env`（root持有、0600，或由云Secret运行时注入），格式为`KEY=value`；不要写`export`。它至少包含上述全部必需项及：

```text
RAILS_ENV=production
ACTIVE_STORAGE_SERVICE=cloud
FORCE_SSL=true
RAILS_LOG_LEVEL=info
RAILS_MAX_THREADS=5
WEB_CONCURRENCY=2
JOB_CONCURRENCY=1
JOB_DB_POOL=10
AI_PROVIDER=minimax
AI_BASE_URL=https://api.minimax.cn/v1
AI_MODEL=MiniMax-M3
OCR_WORKER_URL=http://127.0.0.1:8100
```

上例OCR与Rails位于同机，只允许字面回环地址`127.0.0.1`/`::1`使用HTTP，仍必须校验独立令牌；端口不得公开。云上跨主机调用必须使用HTTPS私网地址，不能使用普通HTTP内网IP。URL不得包含账号、密码或令牌查询参数。

URL密码包含特殊字符时做URL编码；不要在命令历史里粘贴完整凭据。`SECRET_KEY_BASE`由`bundle exec rails secret`生成并由Secret管理保存；不要使用`SECRET_KEY_BASE_DUMMY`启动服务，它仅用于无资源的资产构建。

由RDS管理员预先创建四库。使用独立迁移账号的环境执行：

```bash
RAILS_ENV=production bundle exec rails db:prepare
RAILS_ENV=production bundle exec rails assets:precompile
```

检查业务表只在业务库、`solid_queue_*`只在队列库、`solid_cache_*`只在缓存库、`solid_cable_*`只在Cable库。运行账号不得有建库/建表权限；对业务表授予所需DML/序列权限，对`audit_events`只授予SELECT/INSERT，禁止UPDATE/DELETE/TRUNCATE。发布迁移用另一账号，不用运行账号临时提权。

### 4. OCR、Web与后台进程

```bash
python3 -m venv /srv/donghua/shared/ocr-venv
/srv/donghua/shared/ocr-venv/bin/pip install -r services/ocr_worker/requirements.txt
```

为OCR准备独立`/etc/donghua/ocr.env`，包含与Rails一致的`OCR_WORKER_TOKEN`。模型预下载到shared/ocr-models，模型本身不进Git；无模型时首次真实图片识别会下载，须在正式使用前预热验证。中文字体仅合成测试需要，生产模型不依赖微软字体。

服务模板位于`deploy/systemd/`，默认Ruby位于`/opt/donghua/ruby`。按实际路径复核后安装：

```bash
sudo cp deploy/systemd/donghua-*.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now donghua-ocr donghua-jobs donghua-web
sudo systemctl status donghua-web donghua-jobs donghua-ocr --no-pager
```

不要设置`SOLID_QUEUE_IN_PUMA`，本拓扑使用独立Job进程以免重复启动。服务配置默认收紧文件写入权限，只允许shared和隔离临时目录写入。更改路径时同步更新`ReadWritePaths`。OCR内存上限示例6GB，应按云机资源调整并做大文件压力测试。

### 5. HTTPS与上线验收

`deploy/nginx/donghua.conf.example`是HTTPS反向代理模板。替换域名及已签发的证书路径，先`nginx -t`再reload；或由阿里云ALB/AWS ALB完成同样的TLS终止。Puma3000、OCR8100、PostgreSQL5432不得公开暴露。

首次初始化管理员应在仅运维可达的内网/受限入口完成，再放开客户入口，防止空库初始化被抢先占用。逐项验证登录、岗位隔离、受控下载、文稿导出、真实OCR/AI待复核、定时提醒、异常恢复、审计不可更改及备份恢复。操作系统服务模板仅提供配置，不等于已在客户云上运行验证。

升级、停写备份与恢复验收顺序见`OPERATIONS.md`。切换代码版本不自动回退数据库；破坏性迁移不得直接在线回滚。必须保留旧发布目录及对应备份，优先使用向前兼容迁移。

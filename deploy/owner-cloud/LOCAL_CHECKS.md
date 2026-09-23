# 本轮验证边界（2026-09-07）

- Windows原生隔离SQLite/附件路径：完整RSpec 209 examples, 0 failures, 2 pending。两项pending为默认关闭的真实AI测试，另行运行，不视为通过。
- 单独真实MiniMax联调：2 examples, 0 failures，耗时1分31秒；债权分析、招标分析、文书草稿人工批准写回及独立投标模拟结果保存通过。输入均为合成资料，Key由私有配置读取、不显示。该证据来自本机源码，不代表目标云网络已联通。
- HTTP开关、登录、安全响应头定向回归：14 examples, 0 failures。
- 7个本轮Ruby实现/测试文件 RuboCop 无违规；Python配置/Compose检查脚本编译通过；git diff --check通过。
- WSL Compose 2.40.3解析检查通过：唯一发布端口9052；后台单并发；OCR与Web共享网络命名空间并只监听loopback；稳态容器内存上限合计3520MiB。
- 演示数据回归覆盖幂等、缺少授权标志拒绝、已有保留项目代码碰撞不覆盖。
- Windows libvips报告可选HEIF/JXL等插件加载警告，未引起上述RSpec失败；不能据此声称所有图片格式支持。

未验证：本轮普通源码Docker镜像完整构建/干净安装、腾讯云OpenCloudOS真实部署、生产HTTP Cookie/CSRF黑盒、云端真实AI、扫描OCR在1408MiB上限内峰值、4GB整机并发和重启恢复。原HTTPS封装版证据不能替代这些项目。

原本机站点保持关闭。Gitee未变更，未上传源码或密钥。本文仅记录当前本地检查，不是客户最终验收报告。

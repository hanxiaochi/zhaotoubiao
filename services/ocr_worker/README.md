# OCR Worker

该进程与 Rails Web 应用分离，负责 PDF 页级解析、扫描件/图片中文 OCR、DOCX 和 XLSX 文本提取。本机无需 Docker。

首次安装并启动：

```powershell
cd G:\donghua-ai-platform\services\ocr_worker
$env:OCR_WORKER_TOKEN = "使用独立随机令牌，并在Rails运行环境设置相同值"
.\run.ps1 -Install
```

以后启动：

```powershell
.\run.ps1
```

EasyOCR 的模型默认缓存到 `G:\donghua-ai-platform\services\ocr_worker\models`，不会占用系统盘。首次识别图片时会从 EasyOCR 官方发布地址下载模型；也可以通过 `OCR_MODEL_DIR` 指定其他目录。

Rails 环境变量：

```powershell
$env:OCR_WORKER_URL = "http://127.0.0.1:8100"
$env:OCR_WORKER_TOKEN = "使用独立随机令牌"
$env:OCR_MODEL_DIR = "G:\donghua-ai-platform\services\ocr_worker\models"
```

工作进程设置相同的 `OCR_WORKER_TOKEN`。生产环境必须使用 HTTPS 或放在仅应用可访问的私有网络，并限制上传大小、进程资源和访问来源。

未设置令牌时解析接口返回503，不开放匿名解析；错误令牌返回401。健康检查仍开放以供私网进程探活。

## 解析范围与资源限制

- 单文件50MB；PDF最多200页、图像每帧4000万像素、多帧TIFF最多200帧；超限明确拒绝，不悄悄截断。
- Office解压总量最多100MB、最多10000个ZIP条目；Excel累计最多100万个单元格；提取文本最多200万字符。
- PDF输出物理页码；Word输出逻辑文档位置，不伪造排版页码，按正文和表格出现顺序提取。Word图片/文本框/页眉页脚不在正文提取范围，页面显示警告。
- Excel位置为工作表，不是打印页；公式保留表达式但不计算结果，图片与图表须人工核对。
- CPU解析在工作线程执行，每个进程同一时间只处理一个文件。云端建议 `uvicorn app.main:app --host 127.0.0.1 --port 8100 --limit-concurrency 4`，配合网关上传限制和进程资源限制；不要公开8100端口。

## 可重复验证

```powershell
.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.venv\Scripts\python.exe -m unittest discover -s tests -v
$env:RUN_LIVE_OCR = "1"
.venv\Scripts\python.exe -m unittest discover -s tests -v
Remove-Item Env:RUN_LIVE_OCR
.venv\Scripts\python.exe -m pip check
.venv\Scripts\python.exe -m pip_audit --progress-spinner off
```

真实用例使用合成中文图片和仅含扫描图像的PDF，Windows默认字体 `C:/Windows/Fonts/msyh.ttc`；Linux设置 `OCR_TEST_FONT` 为已安装的中文字体路径。默认离线用例不加载模型，真实用例明确开关控制。2026-09-07全19项（包含真实识别）通过，不能据此承诺任意低清客户扫描件的识别准确率。

## 签章图像候选（非鉴真）

PDF每页（包括有原生文字的页面）及图片每帧均进行本地图像规则检查：红色连通区域/形状，以及识别到的签字标签右侧去除表格线后的墨迹。工作进程返回`pages[].visual_review`，包含方法版本、候选类型、物理页码对应的归一化`bbox=[左,上,右,下]`、依据、局限和未展开数量。每页最多展示20候选，不宣称概率准确率；Rails验证坐标范围和类型，显示原件核对入口。

印刷文字和标志可能误报，黑白印章、浅色/重叠/无标签或非右侧的手写可能漏检；不判断真伪、印章归属或授权效力。仅有文字关键词不会变成图像候选，图像候选也不会自动修改债权材料的人工签章核验状态。Office/TXT没有图像检查，页面明确告知；可转PDF后重新解析。历史PDF/图片结果需重新解析才有新图像候选。

param(
  [switch]$Install,
  [string]$HostAddress = "127.0.0.1",
  [int]$Port = 8100
)

$ErrorActionPreference = "Stop"
$WorkerRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$VenvPython = Join-Path $WorkerRoot ".venv\Scripts\python.exe"
if (-not $env:OCR_WORKER_TOKEN) { throw "Set OCR_WORKER_TOKEN before starting the worker; use the same token in Rails." }

if (-not (Test-Path -LiteralPath $VenvPython)) {
  py -3.11 -m venv (Join-Path $WorkerRoot ".venv")
  if ($LASTEXITCODE -ne 0) { throw "Python virtual environment creation failed." }
  $Install = $true
}

if ($Install) {
  & $VenvPython -m pip install --upgrade pip
  if ($LASTEXITCODE -ne 0) { throw "pip upgrade failed." }
  & $VenvPython -m pip install -r (Join-Path $WorkerRoot "requirements.txt")
  if ($LASTEXITCODE -ne 0) { throw "OCR dependency installation failed." }
}

Push-Location $WorkerRoot
try {
  & $VenvPython -m uvicorn app.main:app --host $HostAddress --port $Port --limit-concurrency 4
} finally {
  Pop-Location
}

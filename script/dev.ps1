param([int]$Port = 3000)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$RubyExecutable = (Get-Command ruby -ErrorAction SilentlyContinue).Source
if (-not $RubyExecutable -and (Test-Path -LiteralPath "C:\Ruby34-x64\bin\ruby.exe")) {
  $RubyExecutable = "C:\Ruby34-x64\bin\ruby.exe"
}
if (-not $RubyExecutable) {
  throw "Ruby not found. Install Ruby 3.4 and add ruby.exe to PATH."
}
if ($env:RAILS_ENV -and $env:RAILS_ENV -ne "development") { throw "This launcher is development-only." }
$env:PATH = (Split-Path -Parent $RubyExecutable) + ";" + $env:PATH

function Stop-OwnedProcessTree($OwnedProcess) {
  if (-not $OwnedProcess) { return }
  $OwnedProcess.Refresh()
  if (-not $OwnedProcess.HasExited) {
    # Scope the native Windows tree termination to a process started by this script.
    # Stop-Process alone leaves the Tailwind child executable running.
    & "$env:WINDIR\System32\taskkill.exe" /PID $OwnedProcess.Id /T /F 2>$null | Out-Null
  }
}

Push-Location $ProjectRoot
$CssProcess = $null
$WebProcess = $null
$SchedulerProcess = $null
try {
  & $RubyExecutable bin\rails db:prepare
  if ($LASTEXITCODE -ne 0) { throw "Database preparation failed; services were not started." }
  & $RubyExecutable bin\rails tailwindcss:build
  if ($LASTEXITCODE -ne 0) { throw "Asset build failed; services were not started." }
  $CssProcess = Start-Process -FilePath $RubyExecutable -ArgumentList @("bin\rails", "tailwindcss:watch") -PassThru -WindowStyle Hidden
  $SchedulerProcess = Start-Process -FilePath $RubyExecutable -ArgumentList @("bin\rails", "runner", "script/local_scheduler.rb") -PassThru -WindowStyle Hidden
  $WebProcess = Start-Process -FilePath $RubyExecutable -ArgumentList @("bin\rails", "server", "-b", "127.0.0.1", "-p", $Port) -PassThru -WindowStyle Hidden
  Write-Host "Donghua AI platform: http://127.0.0.1:$Port"
  while (-not $WebProcess.WaitForExit(1000)) {
    $CssProcess.Refresh()
    $SchedulerProcess.Refresh()
    if ($CssProcess.HasExited -or $SchedulerProcess.HasExited) {
      throw "A required CSS/scheduler process exited; stopping this launcher. Check for an existing launcher in this directory."
    }
  }
  if ($WebProcess.ExitCode -ne 0) { throw "Web process exited with an error. Verify the port and database configuration." }
} finally {
  Stop-OwnedProcessTree $CssProcess
  Stop-OwnedProcessTree $WebProcess
  Stop-OwnedProcessTree $SchedulerProcess
  Pop-Location
}

param([switch]$AuditDependencies)
$ErrorActionPreference = "Stop"
$VerificationRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$VerificationRuby = (Get-Command ruby -ErrorAction SilentlyContinue).Source
if (-not $VerificationRuby) { $VerificationRuby = "C:\Ruby34-x64\bin\ruby.exe" }
if (-not (Test-Path -LiteralPath $VerificationRuby)) { throw "Install Ruby 3.4 and add it to PATH first." }
$VerificationBundle = Join-Path (Split-Path -Parent $VerificationRuby) "bundle"
$OriginalRailsEnvironment = $env:RAILS_ENV
Push-Location $VerificationRoot
try {
  $env:RAILS_ENV = "test"
  & $VerificationRuby bin/rails db:prepare
  if ($LASTEXITCODE -ne 0) { throw "Test database preparation failed." }
  & $VerificationRuby $VerificationBundle exec rspec
  if ($LASTEXITCODE -ne 0) { throw "RSpec failed." }
  if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw "Frontend whitebox tests require Node.js 22 or newer (runtime/build does not require Node)." }
  & node --test spec/javascript/confirm_controller_test.mjs
  if ($LASTEXITCODE -ne 0) { throw "Frontend confirmation tests failed." }
  & $VerificationRuby $VerificationBundle exec rubocop
  if ($LASTEXITCODE -ne 0) { throw "RuboCop failed." }
  & $VerificationRuby bin/rails zeitwerk:check
  if ($LASTEXITCODE -ne 0) { throw "Zeitwerk failed." }
  & $VerificationRuby bin/rails tailwindcss:build
  if ($LASTEXITCODE -ne 0) { throw "Tailwind build failed." }
  & $VerificationRuby $VerificationBundle exec brakeman --no-pager -q
  if ($LASTEXITCODE -ne 0) { throw "Brakeman failed." }
  if ($AuditDependencies) {
    & $VerificationRuby $VerificationBundle exec bundle-audit check --update
    if ($LASTEXITCODE -ne 0) { throw "Ruby dependency audit failed." }
  }
  Write-Host "Offline checks passed. Live AI, browser, OCR, production concurrency and restore need separate acceptance."
} finally {
  $env:RAILS_ENV = $OriginalRailsEnvironment
  Pop-Location
}

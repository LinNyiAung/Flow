<#
.SYNOPSIS
  One-command Flutter end-to-end run against a local, fully stubbed backend.

.DESCRIPTION
  Starts (or reuses) a throwaway PostgreSQL, the backend with every external
  service stubbed (stubenv.py: no .env, no OpenAI/Gemini/SMTP/FCM), the
  outbox helper the tests read e-mails from, and the Android emulator; seeds
  known accounts; then runs frontend/integration_test on the emulator.

  The app is reinstalled by `flutter test`, which drops the notification
  permission and lets Android's prompt block the first launch, so the
  permission is granted the moment the APK lands.

.EXAMPLE
  .\e2e\run_e2e.ps1 -Python .venv\Scripts\python.exe -PgBin "C:\Program Files\PostgreSQL\16\bin"
.EXAMPLE
  .\e2e\run_e2e.ps1 -Name "^(04 Recurring|05 Budgets) "
.EXAMPLE
  .\e2e\run_e2e.ps1 -LargeText -Name "^14 Large text tour "
#>
param(
  # Interpreter with the backend requirements plus httpx and psycopg.
  [string]$Python = "python",
  # Folder with initdb / pg_ctl / psql (only used when nothing listens on port 54329 yet;
  # empty = find them on PATH).
  [string]$PgBin = "",
  [string]$Avd = "Small_Phone",
  # Test-name regex passed to `flutter test --name`; empty runs everything.
  [string]$Name = "",
  # Run with Android font scale 1.3 and enable the large-text tour group.
  [switch]$LargeText,
  # Leave the backend, PostgreSQL and emulator running afterwards.
  [switch]$KeepRunning
)

# Not "Stop": PowerShell 5 turns any stderr from adb/flutter (e.g. "no devices"
# while the emulator boots) into a terminating error. Failures are checked explicitly.
$ErrorActionPreference = "Continue"
$E2E = $PSScriptRoot
$Repo = Split-Path $E2E -Parent
$Logs = Join-Path $E2E "logs"
$Data = Join-Path $E2E ".data\pg"
New-Item -ItemType Directory -Force $Logs, $Data | Out-Null
$adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
$emulatorExe = Join-Path $env:LOCALAPPDATA "Android\Sdk\emulator\emulator.exe"
$pkg = "com.example.frontend"
$started = @()

function Test-Port($port) {
  [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
}
function Wait-Until($what, $seconds, [scriptblock]$cond) {
  $deadline = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $deadline) {
    try { if (& $cond) { return } } catch {}
    Start-Sleep -Milliseconds 700
  }
  throw "Timed out after ${seconds}s waiting for $what"
}

try {
  # ---- 1. throwaway PostgreSQL (trust auth, local only) + schema ----
  function PgTool($name) { if ($PgBin) { Join-Path $PgBin "$name.exe" } else { (Get-Command $name -ErrorAction Stop).Source } }
  $pgStarted = $false
  if (-not (Test-Port 54329)) {
    Write-Host "Starting PostgreSQL on 127.0.0.1:54329 ..."
    if (-not (Test-Path (Join-Path $Data "PG_VERSION"))) {
      & (PgTool "initdb") -D $Data -U flow -A trust -E UTF8 --locale=C | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "initdb failed (pass -PgBin)" }
    }
    # pg_ctl keeps its output handle open, so it is started detached and we wait for the port.
    Start-Process -FilePath (PgTool "pg_ctl") -WindowStyle Hidden -ArgumentList `
      "-D `"$Data`" -o `"-p 54329 -c listen_addresses=127.0.0.1 -c timezone=UTC`" -l `"$Logs\postgres.log`" start"
    $pgStarted = $true
    Wait-Until "PostgreSQL" 60 { Test-Port 54329 }
    Wait-Until "PostgreSQL ready" 60 { & (PgTool "psql") -h 127.0.0.1 -p 54329 -U flow -d postgres -tAc "select 1" 2>$null; $LASTEXITCODE -eq 0 }
  }
  $hasDb = & (PgTool "psql") -h 127.0.0.1 -p 54329 -U flow -d postgres -tAc "select 1 from pg_database where datname = 'flow_e2e'"
  if ("$hasDb".Trim() -ne "1") { & (PgTool "psql") -h 127.0.0.1 -p 54329 -U flow -d postgres -c "create database flow_e2e" | Out-Null }
  $env:DATABASE_URL = "postgresql://flow@127.0.0.1:54329/flow_e2e"
  Push-Location (Join-Path $Repo "backend")
  & $Python -m alembic upgrade head
  $alembicExit = $LASTEXITCODE
  Pop-Location
  if ($alembicExit -ne 0) { throw "alembic upgrade failed" }

  # ---- 2. stubbed backend + outbox helper ----
  if (-not (Test-Port 8765)) {
    Write-Host "Starting stubbed backend on 127.0.0.1:8765 ..."
    Remove-Item (Join-Path $E2E "outbox.jsonl") -ErrorAction SilentlyContinue
    $env:PYTHONIOENCODING = "utf-8"
    $env:E2E_FAKE_AI = "1"
    $started += Start-Process -FilePath $Python -PassThru -WindowStyle Hidden `
      -ArgumentList "-u `"$E2E\run_server.py`"" `
      -RedirectStandardOutput "$Logs\server.log" -RedirectStandardError "$Logs\server_err.log"
    Wait-Until "backend" 180 { try { Invoke-RestMethod http://127.0.0.1:8765/ -TimeoutSec 2 | Out-Null; $true } catch { $false } }
  }
  if (-not (Test-Port 8766)) {
    $started += Start-Process -FilePath $Python -PassThru -WindowStyle Hidden -ArgumentList "-I `"$E2E\outbox_server.py`""
    Wait-Until "outbox helper" 30 { Test-Port 8766 }
  }

  # ---- 3. emulator ----
  $emulatorStarted = $false
  if (-not ((& $adb devices) -match "emulator-\d+\s+device")) {
    Write-Host "Booting emulator $Avd (cold boot) ..."
    Start-Process -FilePath $emulatorExe -WindowStyle Hidden -ArgumentList "-avd $Avd -no-snapshot-load -no-boot-anim -gpu swiftshader_indirect"
    $emulatorStarted = $true
    Wait-Until "emulator boot" 420 { "$(& $adb shell getprop sys.boot_completed 2>$null)".Trim() -eq "1" }
  }
  # Gboard's stylus handwriting steals focus from text fields under test.
  & $adb shell settings put secure stylus_handwriting_enabled 0
  & $adb shell settings put system font_scale $(if ($LargeText) { "1.3" } else { "1.0" })

  # ---- 4. known data ----
  & $Python (Join-Path $E2E "seed_rich.py")
  if ($LASTEXITCODE -ne 0) { throw "seeding failed" }

  # ---- 5. run, granting the notification permission as soon as the APK installs ----
  & $adb uninstall $pkg 2>$null | Out-Null
  $grant = Start-Job -ArgumentList $adb, $pkg -ScriptBlock {
    param($adb, $pkg)
    for ($i = 0; $i -lt 1200; $i++) {
      if ((& $adb shell pm list packages $pkg) -match $pkg) {
        & $adb shell pm grant $pkg android.permission.POST_NOTIFICATIONS; return
      }
      Start-Sleep -Milliseconds 500
    }
  }
  $log = Join-Path $Logs "flutter.log"
  $flArgs = @("test", "integration_test/app_test.dart", "-d", "emulator-5554",
            "--dart-define=API_BASE_URL=http://10.0.2.2:8765", "--reporter", "expanded")
  if ($LargeText) { $flArgs += "--dart-define=E2E_LARGE_TEXT=true" }
  if ($Name) { $flArgs += @("--name", $Name) }
  # Quote every argument: a --name regex like "^(A|B) " must reach flutter intact through cmd.
  $cmdLine = ($flArgs | ForEach-Object { '"' + $_ + '"' }) -join ' '
  Write-Host "Running: flutter $cmdLine"
  # Start-Process passes the argument string verbatim and writes the log as
  # raw UTF-8 (PowerShell 5 redirection would re-encode it).
  $flutter = (Get-Command flutter).Source
  $proc = Start-Process -FilePath $flutter -ArgumentList $cmdLine -NoNewWindow -PassThru `
    -WorkingDirectory (Join-Path $Repo "frontend") `
    -RedirectStandardOutput $log -RedirectStandardError (Join-Path $Logs "flutter_err.log")
  $null = $proc.Handle  # cache the handle, or ExitCode stays empty after exit
  $proc.WaitForExit()
  $exit = $proc.ExitCode
  Stop-Job $grant -ErrorAction SilentlyContinue; Remove-Job $grant -Force -ErrorAction SilentlyContinue

  # ---- 6. summary ----
  $lines = Get-Content $log -Encoding UTF8
  $results = $lines | Where-Object { $_ -like "E2E_RESULT|*" }
  $pass = @($results | Where-Object { $_ -match "\|PASS\|" }).Count
  $fail = @($results | Where-Object { $_ -match "\|FAIL\|" }).Count
  Write-Host ""
  Write-Host "==== $pass passed, $fail failed  (flutter exit $exit, log: $log) ===="
  $results | Where-Object { $_ -match "\|FAIL\|" } | ForEach-Object { Write-Host "  FAIL  $($_.Substring(11, [Math]::Min(230, $_.Length - 11)))" }
  $lines | Where-Object { $_ -like "E2E_ISSUE|*" } | ForEach-Object { $_.Substring(0, [Math]::Min(260, $_.Length)) } |
    Select-Object -Unique | ForEach-Object { Write-Host "  ISSUE $_" }
  exit $exit
}
finally {
  if ($LargeText) { & $adb shell settings put system font_scale 1.0 2>$null | Out-Null }
  if (-not $KeepRunning) {
    if ($emulatorStarted) { & $adb emu kill 2>$null | Out-Null }
    if ($pgStarted) { & (PgTool "pg_ctl") -D $Data stop -m fast 2>$null | Out-Null }
    $started | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
  }
}

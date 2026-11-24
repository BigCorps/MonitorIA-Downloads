param(
  [Parameter(Mandatory)][ValidateSet("verify", "test", "prepare", "sign", "package")]
  [string] $Phase
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
if ($env:GITHUB_ACTIONS -ne "true" -or $env:RUNNER_OS -ne "Windows" -or
    $env:GITHUB_REPOSITORY -cne "BigCorps/MonitorIA-Downloads" -or
    $env:GITHUB_REF -cne "refs/heads/main" -or $env:GITHUB_EVENT_NAME -cne "workflow_dispatch") {
  throw "Run only on the Downloads Windows workflow."
}

$source = Join-Path $env:GITHUB_WORKSPACE "private-src"
$log = Join-Path $env:RUNNER_TEMP "monitoria-v107-$Phase.log"
$pwsh = (Get-Process -Id $PID).Path

# Compilation, native tests and CodeSignTool may print private source or
# command arguments. Retain their output only while this step is running.
Push-Location $source
try {
  & {
    if ((git rev-parse HEAD).Trim() -cne $env:MONITORIA_SOURCE_SHA) { throw "Private SHA mismatch" }
    $env:GITHUB_WORKSPACE = $source
    $campaign = "./scripts/release-agent-v107-windows.ps1"
    $signer = "./scripts/sign-inno-authenticode.ps1"
    switch ($Phase) {
      "verify" {
        git diff --quiet HEAD
        foreach ($file in @($campaign, $signer, "agent/src/index-v107.ts", "package-lock.json")) {
          if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw "Private campaign dependency missing" }
        }
      }
      "test" {
        npm ci --no-audit --no-fund
        ./node_modules/.bin/tsc.cmd --noEmit -p agent/tsconfig.json
        node --import tsx --test test/agent-windows-dvr-channels.test.ts test/agent-onvif-incomplete-dvr-channels.test.ts test/discovery-visual-dedupe.test.ts test/agent-0106-auto-discovery.test.ts test/agent-0106-jortan-discovery.test.ts test/agent-0106-windows-legacy-auto.test.ts test/robustness-gate2-discovery.test.ts
      }
      "prepare" {
        & $pwsh -NoProfile -NonInteractive -File $campaign prepare -Windows247Only
      }
      "sign" {
        $env:MONITORIA_SIGN_CONTEXT = "windows-247-components"
        New-Item -ItemType Directory -Path sign-stage-signed | Out-Null
        foreach ($name in @("monitoria-agent.exe", "monitoria-dpapi.exe", "monitoria-tray.exe", "monitoria-service.exe", "mediamtx.exe")) {
          $target = Join-Path (Resolve-Path sign-stage-signed) $name
          Copy-Item -LiteralPath "sign-stage/$name" -Destination $target
          & $pwsh -NoProfile -NonInteractive -File $signer $target
        }
      }
      "package" {
        & $pwsh -NoProfile -NonInteractive -File $campaign package -Windows247Only
        $candidate = Get-Item -LiteralPath release-windows/MonitorIA-Setup.exe
        $signature = Get-AuthenticodeSignature -LiteralPath $candidate.FullName
        if ($candidate.Length -le 0 -or $signature.Status -ne "Valid" -or !$signature.TimeStamperCertificate) {
          throw "Final installer did not pass Authenticode and timestamp validation"
        }
      }
    }
  } *> $log
} catch {
  throw "Windows 24/7 phase '$Phase' failed. Private diagnostics were suppressed."
} finally {
  Pop-Location
  Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
}
Write-Host "Windows 24/7 phase '$Phase' passed."

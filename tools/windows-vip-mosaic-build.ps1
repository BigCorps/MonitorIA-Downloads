$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
$trustedRef = $env:GITHUB_REF -ceq "refs/heads/main" -or (
    $env:GITHUB_REF -ceq "refs/heads/codex/vip-mosaic-unsigned-homologation" -and $env:GITHUB_ACTOR -ceq "BigCorps" -and
    $env:GITHUB_TRIGGERING_ACTOR -ceq "BigCorps"
)
if ($env:GITHUB_ACTIONS -ne "true" -or $env:RUNNER_OS -ne "Windows" -or
    $env:GITHUB_REPOSITORY -cne "BigCorps/MonitorIA-Downloads" -or
    !$trustedRef -or $env:GITHUB_EVENT_NAME -cne "workflow_dispatch") {
    throw "Run only on the authorized Downloads Windows workflow."
}

$source = Join-Path $env:GITHUB_WORKSPACE "private-src"
$payload = Join-Path $env:RUNNER_TEMP "monitoria-vip-payload"
$release = Join-Path $env:GITHUB_WORKSPACE "release-vip"
$pwsh = (Get-Process -Id $PID).Path
$previewName = "MonitorIA-VIP-CapturePreview.exe"
$simulatorName = "MonitorIA-VIP-Simulador.html"
$log = Join-Path $env:RUNNER_TEMP "monitoria-vip-unsigned-build.log"
# Keep tool output local to the ephemeral runner. Only fixed phase names escape.
$phase = "source verification"
Push-Location $source
try {
    . {
        if ($env:MONITORIA_SOURCE_SHA -cnotmatch '^[a-f0-9]{40}$' -or
            (git rev-parse HEAD).Trim() -cne $env:MONITORIA_SOURCE_SHA -or
            (git -C $env:GITHUB_WORKSPACE rev-parse HEAD).Trim() -cne $env:GITHUB_SHA) {
            throw "Unexpected source or workflow revision."
        }
        git diff --quiet HEAD --
        git -C $env:GITHUB_WORKSPACE diff --quiet HEAD --
        if (Test-Path -LiteralPath $payload) { throw "Unexpected pre-existing packaging directory." }
        New-Item -ItemType Directory -Path $payload | Out-Null
        $phase = "dependency installation"
        npm ci --ignore-scripts --no-audit --no-fund
        $phase = "mosaic geometry tests"
        node --import tsx --test test/agent-vip-mosaic.test.ts
        $native = Join-Path $env:RUNNER_TEMP "monitoria-vip-native"
        $phase = "native compilation"
        & $pwsh -NoProfile -NonInteractive -File ./scripts/build-vip-mosaic-preview.ps1 -OutputDirectory $native
        Copy-Item -LiteralPath (Join-Path $native $previewName) -Destination $payload
        $phase = "offline simulator build"
        node ./scripts/build-vip-mosaic-offline.mjs $payload
        foreach ($entry in @($previewName, $simulatorName)) {
            $file = Get-Item -LiteralPath (Join-Path $payload $entry)
            if ($file.PSIsContainer -or $file.Length -le 0) { throw "Missing package file." }
        }

        $phase = "unsigned package verification"
        $preview = Join-Path $payload $previewName
        if ((Get-AuthenticodeSignature -LiteralPath $preview).Status -ne "NotSigned") {
            throw "Unexpected Authenticode signature on a preview built without signing."
        }

        if (Test-Path -LiteralPath $release) { throw "Unexpected pre-existing draft staging directory." }
        New-Item -ItemType Directory -Path $release | Out-Null
        $instructions = Join-Path $payload "LEIA-ME.txt"
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot "windows-vip-mosaic-homologacao.txt") -Destination $instructions
        $archive = Join-Path $release "MonitorIA-VIP-Mosaico-1.0.0-beta.1-Homologacao-NAO-ASSINADO.zip"
        $expected = @($previewName, $simulatorName, "LEIA-ME.txt")
        $files = $expected | ForEach-Object { Join-Path $payload $_ }
        Compress-Archive -LiteralPath $files -DestinationPath $archive

        $unpack = Join-Path $env:RUNNER_TEMP "monitoria-vip-unpack"
        if (Test-Path -LiteralPath $unpack) { throw "Unexpected pre-existing archive validation directory." }
        Expand-Archive -LiteralPath $archive -DestinationPath $unpack
        if (Compare-Object ($expected | Sort-Object) (Get-ChildItem -LiteralPath $unpack -Name | Sort-Object)) {
            throw "Archive differs from the approved file list."
        }
        $hashes = [ordered]@{}
        foreach ($entry in $expected) {
            $insideHash = (Get-FileHash -LiteralPath (Join-Path $unpack $entry) -Algorithm SHA256).Hash.ToLowerInvariant()
            $expectedHash = (Get-FileHash -LiteralPath (Join-Path $payload $entry) -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($insideHash -cne $expectedHash) { throw "Archive byte verification failed." }
            $hashes[$entry] = $insideHash
        }
        $manifest = [ordered]@{
            files = $hashes
            authenticode = [ordered]@{
                file = $previewName
                status = "NotSigned"
                timestampVerified = $false
            }
        }
        $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $release "WINDOWS-VERIFICATION.json") -Encoding utf8NoBOM
    } *> $log
}
catch {
    throw "VIP Windows phase failed: $phase. Private diagnostics were suppressed."
}
finally {
    Pop-Location
    Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
}
Write-Host "VIP Windows build, tests and unsigned package checks passed."

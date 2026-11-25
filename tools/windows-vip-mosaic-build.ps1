param([Parameter(Mandatory)][ValidateSet("compile", "package")][string]$Phase)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
if ($env:GITHUB_ACTIONS -ne "true" -or $env:RUNNER_OS -ne "Windows" -or
    $env:GITHUB_REPOSITORY -cne "BigCorps/MonitorIA-Downloads" -or
    $env:GITHUB_REF -cne "refs/heads/main" -or $env:GITHUB_EVENT_NAME -cne "workflow_dispatch") {
    throw "Run only on the authorized Downloads Windows workflow."
}

$source = Join-Path $env:GITHUB_WORKSPACE "private-src"
$payload = Join-Path $env:RUNNER_TEMP "monitoria-vip-payload"
$release = Join-Path $env:GITHUB_WORKSPACE "release-vip"
$pwsh = (Get-Process -Id $PID).Path
$previewName = "MonitorIA-VIP-CapturePreview.exe"
$simulatorName = "MonitorIA-VIP-Simulador.html"
$log = Join-Path $env:RUNNER_TEMP "monitoria-vip-$Phase.log"
$markedSignatureLog = Join-Path $env:RUNNER_TEMP "monitoria-inno-signatures.jsonl"

function Get-VerifiedSignature([string]$File) {
    $signature = Get-AuthenticodeSignature -LiteralPath $File
    if ($signature.Status -ne "Valid" -or $signature.SignatureType -ne "Authenticode" -or
        !$signature.TimeStamperCertificate -or !$signature.SignerCertificate) {
        throw "The capture preview must have valid, timestamped Authenticode."
    }
    return $signature
}

# Never forward compiler, source checker, dependency, or signing output to the public job.
Push-Location $source
try {
    & {
        if ($env:MONITORIA_SOURCE_SHA -cnotmatch '^[a-f0-9]{40}$' -or
            (git rev-parse HEAD).Trim() -cne $env:MONITORIA_SOURCE_SHA -or
            (git -C $env:GITHUB_WORKSPACE rev-parse HEAD).Trim() -cne $env:GITHUB_SHA) {
            throw "Unexpected source or workflow revision."
        }
        git diff --quiet HEAD --
        git -C $env:GITHUB_WORKSPACE diff --quiet HEAD --
        if ($Phase -eq "compile") {
            if (Test-Path -LiteralPath $payload) { throw "Unexpected pre-existing packaging directory." }
            New-Item -ItemType Directory -Path $payload | Out-Null
            npm ci --ignore-scripts --no-audit --no-fund
            node --import tsx --test test/agent-vip-mosaic.test.ts
            $native = Join-Path $env:RUNNER_TEMP "monitoria-vip-native"
            & $pwsh -NoProfile -NonInteractive -File ./scripts/build-vip-mosaic-preview.ps1 -OutputDirectory $native
            Copy-Item -LiteralPath (Join-Path $native $previewName) -Destination $payload
            node ./scripts/build-vip-mosaic-offline.mjs $payload
            foreach ($entry in @($previewName, $simulatorName)) {
                $file = Get-Item -LiteralPath (Join-Path $payload $entry)
                if ($file.PSIsContainer -or $file.Length -le 0) { throw "Missing package file." }
            }
            return
        }

        $preview = Join-Path $payload $previewName
        $env:MONITORIA_SIGN_CONTEXT = "vip-mosaic-capture-preview"
        & $pwsh -NoProfile -NonInteractive -File ./scripts/sign-inno-authenticode.ps1 $preview
        $signature = Get-VerifiedSignature $preview

        if (Test-Path -LiteralPath $release) { throw "Unexpected pre-existing draft staging directory." }
        New-Item -ItemType Directory -Path $release | Out-Null
        $instructions = Join-Path $payload "LEIA-ME.txt"
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot "windows-vip-mosaic-homologacao.txt") -Destination $instructions
        $archive = Join-Path $release "MonitorIA-VIP-Mosaico-1.0.0-beta.1-Homologacao.zip"
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
        Get-VerifiedSignature (Join-Path $unpack $previewName) | Out-Null
        $manifest = [ordered]@{
            files = $hashes
            authenticode = [ordered]@{
                file = $previewName
                signerSha256 = $signature.SignerCertificate.GetCertHashString([System.Security.Cryptography.HashAlgorithmName]::SHA256).ToLowerInvariant()
                timestampVerified = $true
            }
        }
        $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $release "WINDOWS-VERIFICATION.json") -Encoding utf8NoBOM
    } *> $log
}
catch {
    throw "VIP Windows phase '$Phase' failed. Private diagnostics were suppressed."
}
finally {
    Pop-Location
    Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
    if ($Phase -eq "package") {
        Remove-Item -LiteralPath $markedSignatureLog -Force -ErrorAction SilentlyContinue
    }
}
Write-Host "VIP Windows phase '$Phase' passed."

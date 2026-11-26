$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "windows-vip-native-diagnostics.ps1")
$log = [System.IO.Path]::GetTempFileName()
try {
    @'
private-repo\client-camera.cpp(165): error C2039: confidential symbol and private source
private-repo\client-camera.cpp(166): error C2039: redundant message with token
capture-preview.obj : error LNK2019: unresolved external symbol proprietary_helper
private-repo\some-private-header.h(220): error C2338: static_assert failed: 'error STL1011: private token and source'
private-file.cpp(3): error C2338: error STL1099: unknown private data
VIP_NATIVE stage=sdk_probe_compile exit=2
VIP_NATIVE stage=sdk_probe_link exit=1120
VIP_NATIVE missing=cppwinrt/winrt/Windows.Foundation.h
  VIP_NATIVE stage=vcvars exit=1
VIP_NATIVE stage=link exit=1120
VIP_NATIVE sdk=10.0.26100.0
VIP_NATIVE msvc=14.43.34808
VIP_NATIVE sdk_candidate=10.0.26200.0
VIP_NATIVE missing=um/windows.graphics.capture.interop.h
VIP_NATIVE missing=windowsapp.lib
VIP_NATIVE stage=setup reason=SDK_WGC_X64_INCOMPLETE
VIP_NATIVE stage=setup reason=SDK_VERSION_MISMATCH
VIP_NATIVE stage=setup reason=EXTRA_PRIVATE_REASON
VIP_NATIVE missing=private/client-name.h
VIP_NATIVE stage=compile exit=2 ::warning::injection
VIP_NATIVE msvc=14.43.34808 followed by a private token
::notice::private statement
'@ | Set-Content -LiteralPath $log
    $actual = @(Get-VipNativeDiagnostics -LogPath $log)
    $expected = @(
        "VIP native: compiler_error=C2039",
        "VIP native: first_error=C2039 severity=error category=missing-member file=unknown",
        "VIP native: compiler_error=LNK2019",
        "VIP native: compiler_error=C2338",
        "VIP native: library_error=STL1011",
        "VIP native: stage=sdk_probe_compile exit=2",
        "VIP native: stage=sdk_probe_link exit=1120",
        "VIP native: missing=cppwinrt/winrt/Windows.Foundation.h",
        "VIP native: stage=vcvars exit=1",
        "VIP native: stage=link exit=1120",
        "VIP native: sdk=10.0.26100.0",
        "VIP native: msvc=14.43.34808",
        "VIP native: sdk_candidate=10.0.26200.0",
        "VIP native: missing=um/windows.graphics.capture.interop.h",
        "VIP native: missing=windowsapp.lib",
        "VIP native: stage=setup reason=SDK_WGC_X64_INCOMPLETE",
        "VIP native: stage=setup reason=SDK_VERSION_MISMATCH"
    )
    if (($actual -join "`n") -cne ($expected -join "`n")) { throw "Unexpected diagnostic output." }
    (1..30 | ForEach-Object { "compiler : error C{0}: confidential data" -f (1000 + $_) }) |
        Set-Content -LiteralPath $log
    if (@(Get-VipNativeDiagnostics -LogPath $log | Where-Object { $_ -like "*compiler_error=*" }).Count -ne 12) { throw "Expected a bounded list of error codes." }
    @'
sdk-compatibility.cpp(23,12): error C2872: 'DirectX': ambiguous symbol [private path]
some-secret-file(12): error C3083: private namespace
sdk-compatibility.cpp(24): note: private name error C1234: fake error
'@ | Set-Content -LiteralPath $log
    $actual = @(Get-VipNativeDiagnostics -LogPath $log)
    $expected = @(
        "VIP native: compiler_error=C2872",
        "VIP native: first_error=C2872 severity=error category=ambiguous-symbol file=sdk-probe line=23 symbol=DirectX",
        "VIP native: compiler_error=C3083"
    )
    if (($actual -join "`n") -cne ($expected -join "`n")) { throw "Invalid first error redaction." }

    Set-Content -LiteralPath $log "private.cpp(73): error C2872: 'ClientCode': ambiguous symbol"
    if ((Get-VipNativeDiagnostics -LogPath $log | Select-Object -Last 1) -cne
        "VIP native: first_error=C2872 severity=error category=ambiguous-symbol file=unknown") {
        throw "Unapproved identifier or location escaped."
    }
    Set-Content -LiteralPath $log "LINK : fatal error LNK1104: cannot open private file"
    if ((Get-VipNativeDiagnostics -LogPath $log | Select-Object -Last 1) -cne
        "VIP native: first_error=LNK1104 severity=fatal-error category=linker file=unknown") {
        throw "Link diagnostic did not retain category."
    }
    Set-Content -LiteralPath $log "::warning::do not publish"
    if ((Get-VipNativeDiagnostics -LogPath $log) -ne "VIP native: no recognized diagnostic codes") {
        throw "Unrecognized output escaped."
    }
    Write-Host "VIP diagnostics passed allowlist, deduplication, bound and redaction checks."
}
finally {
    Remove-Item -LiteralPath $log -Force
}

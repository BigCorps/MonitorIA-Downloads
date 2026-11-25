function Get-VipNativeDiagnostics {
    param([Parameter(Mandatory)][string]$LogPath)

    # Reconstruct every published line from fixed labels and constrained
    # tokens. Source lines, file paths, compiler messages and symbols stay in
    # the temporary log, even if a tool emits Actions workflow commands.
    $reasons = @("WINDOWS_REQUIRED", "PROGRAMFILES_X86_MISSING", "SOURCE_MISSING", "VSWHERE_MISSING",
        "VSWHERE_FAILED", "MSVC_X64_MISSING", "VCVARS_MISSING", "SDK_INCLUDE_MISSING", "SDK_WGC_X64_INCOMPLETE",
        "CL_MISSING", "LINK_MISSING", "OUTPUT_DIRECTORY_UNAVAILABLE", "OUTPUT_MISSING")
    $dependencies = @("cppwinrt/winrt/Windows.Graphics.Capture.h", "cppwinrt/winrt/Windows.Graphics.DirectX.Direct3D11.h",
        "um/windows.graphics.capture.interop.h", "um/windows.graphics.directx.direct3d11.interop.h", "d3d11.lib",
        "dxgi.lib", "dwmapi.lib", "wtsapi32.lib", "windowsapp.lib", "user32.lib", "gdi32.lib", "shell32.lib", "ole32.lib")
    $facts = [System.Collections.Generic.HashSet[string]]::new()
    $codes = [System.Collections.Generic.HashSet[string]]::new()
    if (Test-Path -LiteralPath $LogPath -PathType Leaf) {
        foreach ($line in [System.IO.File]::ReadLines($LogPath)) {
            if ($facts.Count -lt 24) {
                $fact = $null
                if ($line -cmatch '^\s*VIP_NATIVE (?<field>sdk|sdk_candidate|msvc)=(?<version>[0-9]{1,2}(?:\.[0-9]{1,6}){1,3})\s*$') {
                    $fact = "$($Matches.field)=$($Matches.version)"
                }
                elseif ($line -cmatch '^\s*VIP_NATIVE stage=(?<stage>vcvars|compile|link) exit=(?<number>-?[0-9]{1,10})\s*$') {
                    $fact = "stage=$($Matches.stage) exit=$($Matches.number)"
                }
                elseif ($line -cmatch '^\s*VIP_NATIVE stage=setup reason=(?<reason>[A-Z0-9_]{1,50})\s*$' -and $Matches.reason -cin $reasons) {
                    $fact = "stage=setup reason=$($Matches.reason)"
                }
                elseif ($line -cmatch '^\s*VIP_NATIVE missing=(?<dependency>[-.a-zA-Z0-9/]{1,100})\s*$' -and $Matches.dependency -cin $dependencies) {
                    $fact = "missing=$($Matches.dependency)"
                }
                if ($fact -and $facts.Add($fact)) { "VIP native: $fact" }
            }

            if ($codes.Count -lt 12 -and $line -match '(?:^|\s)(?:fatal error|error)\s+(?<code>(?:C|D|LNK)[0-9]{4}):') {
                $code = $Matches.code.ToUpperInvariant()
                if ($codes.Add($code)) { "VIP native: compiler_error=$code" }
            }
        }
    }
    if (!$facts.Count -and !$codes.Count) { "VIP native: no recognized diagnostic codes" }
}

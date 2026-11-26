function Get-VipNativeDiagnostics {
    param([Parameter(Mandatory)][string]$LogPath)

    # Reconstruct every published line from fixed labels and constrained
    # tokens. Source lines, file paths, compiler messages and symbols stay in
    # the temporary log, even if a tool emits Actions workflow commands.
    $reasons = @("WINDOWS_REQUIRED", "PROGRAMFILES_X86_MISSING", "SOURCE_MISSING", "VSWHERE_MISSING",
        "VSWHERE_FAILED", "MSVC_X64_MISSING", "VCVARS_MISSING", "SDK_INCLUDE_MISSING", "SDK_WGC_X64_INCOMPLETE",
        "SDK_VERSION_MISMATCH",
        "CL_MISSING", "LINK_MISSING", "OUTPUT_DIRECTORY_UNAVAILABLE", "OUTPUT_MISSING")
    $dependencies = @("cppwinrt/winrt/Windows.Foundation.h", "cppwinrt/winrt/Windows.Graphics.Capture.h", "cppwinrt/winrt/Windows.Graphics.DirectX.Direct3D11.h",
        "um/windows.graphics.capture.interop.h", "um/windows.graphics.directx.direct3d11.interop.h", "d3d11.lib",
        "dxgi.lib", "dwmapi.lib", "wtsapi32.lib", "windowsapp.lib", "user32.lib", "gdi32.lib", "shell32.lib", "ole32.lib")
    $categories = @{
        C2872 = "ambiguous-symbol"; C3083 = "invalid-scope"; C2039 = "missing-member"
        C2065 = "undeclared-identifier"; C3536 = "invalid-initialization"; C2737 = "missing-initializer"
        C2338 = "static-assert"; C1083 = "missing-input"; C2664 = "type-conversion"
    }
    $fileCategories = @{
        "sdk-compatibility.cpp" = "sdk-probe"; "wgc-interop.h" = "wgc-interop"; "capture-preview.cpp" = "capture-preview"
        "windows.graphics.capture.interop.h" = "windows-sdk"; "windows.graphics.directx.direct3d11.interop.h" = "windows-sdk"
        "windows.foundation.h" = "cppwinrt-sdk"; "windows.graphics.capture.h" = "cppwinrt-sdk"
        "windows.graphics.directx.direct3d11.h" = "cppwinrt-sdk"
        "coroutine" = "msvc-stl"; "yvals_core.h" = "msvc-stl"; "directxmath.h" = "windows-sdk"
    }
    $publicSymbols = @("Windows", "Graphics", "Capture", "DirectX", "DirectXPixelFormat", "GraphicsCaptureItem",
        "GraphicsCaptureSession", "Direct3D11CaptureFramePool", "IInspectable", "ID3D11Texture2D",
        "IDirect3DDevice", "IDirect3DSurface", "IDirect3DDxgiInterfaceAccess", "IGraphicsCaptureItemInterop")
    $first = $true
    $facts = [System.Collections.Generic.HashSet[string]]::new()
    $codes = [System.Collections.Generic.HashSet[string]]::new()
    $libraryCodes = [System.Collections.Generic.HashSet[string]]::new()
    if (Test-Path -LiteralPath $LogPath -PathType Leaf) {
        foreach ($line in [System.IO.File]::ReadLines($LogPath)) {
            if ($facts.Count -lt 24) {
                $fact = $null
                if ($line -cmatch '^\s*VIP_NATIVE (?<field>sdk|sdk_candidate|msvc)=(?<version>[0-9]{1,2}(?:\.[0-9]{1,6}){1,3})\s*$') {
                    $fact = "$($Matches.field)=$($Matches.version)"
                }
                elseif ($line -cmatch '^\s*VIP_NATIVE stage=(?<stage>vcvars|sdk_probe_compile|sdk_probe_link|compile|link) exit=(?<number>-?[0-9]{1,10})\s*$') {
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

            $diagnostic = [regex]::Match($line,
                '^\s*(?:(?<origin>.{1,1024}?)\s*:\s*)?(?:(?<severity>fatal error|command line error|error)\s+)(?<code>(?:C|D|LNK)[0-9]{4}):\s*(?<detail>.*)$',
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($diagnostic.Success) {
                $code = $diagnostic.Groups["code"].Value.ToUpperInvariant()
                if ($codes.Count -lt 12 -and $codes.Add($code)) { "VIP native: compiler_error=$code" }
                if ($first) {
                    $first = $false
                    $category = $categories[$code]
                    if (!$category) {
                        $category = if ($code.StartsWith("LNK")) { "linker" } elseif ($code.StartsWith("D")) { "compiler-option" } else { "compiler" }
                    }
                    $severity = $diagnostic.Groups["severity"].Value.ToLowerInvariant().Replace(" ", "-")
                    $location = "file=unknown"
                    if ($diagnostic.Groups["origin"].Value -match '^(?<path>.+)\((?<line>[1-9][0-9]{0,5})(?:,[0-9]{1,5})?\)$') {
                        $name = ($Matches.path -split '[\\/]')[-1]
                        $file = $fileCategories[$name]
                        if ($file) { $location = "file=$file line=$($Matches.line)" }
                    }
                    $identifier = ""
                    if ($code -eq "C2872" -and $diagnostic.Groups["detail"].Value -cmatch '^[''"](?<symbol>[A-Za-z0-9_]+)[''"]\s*:\s*ambiguous symbol\b' -and
                        $Matches.symbol -cin $publicSymbols) {
                        $identifier = " symbol=$($Matches.symbol)"
                    }
                    "VIP native: first_error=$code severity=$severity category=$category $location$identifier"
                }
            }
            # Only named diagnostics from Microsoft's public STL header.
            if ($line -match '(?:^|[\s''"])error\s+(?<code>STL1009|STL1010|STL1011):') {
                $code = $Matches.code.ToUpperInvariant()
                if ($libraryCodes.Add($code)) { "VIP native: library_error=$code" }
            }
        }
    }
    if (!$facts.Count -and !$codes.Count -and !$libraryCodes.Count) { "VIP native: no recognized diagnostic codes" }
}

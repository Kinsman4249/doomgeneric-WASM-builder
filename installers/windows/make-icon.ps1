# make-icon.ps1 - best-effort PNG -> ICO conversion for the Windows
# installer's shortcuts, using only .NET (System.Drawing), so no extra
# tooling needs to be installed on the runner. If assets/icon.png is
# missing or conversion fails for any reason, the installer still builds;
# the shortcuts just fall back to the default icon for an .html file.
$ErrorActionPreference = "Continue"

if (-not (Test-Path "assets\icon.png")) {
    Write-Host "No assets/icon.png found; installer will use the default icon."
    exit 0
}

try {
    Add-Type -AssemblyName System.Drawing
    $src = [System.Drawing.Image]::FromFile((Resolve-Path "assets\icon.png"))
    $bmp = New-Object System.Drawing.Bitmap($src, 256, 256)
    $icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
    $fs = [System.IO.File]::Open("payload\icon.ico", [System.IO.FileMode]::Create)
    $icon.Save($fs)
    $fs.Close()
    Write-Host "Built payload\icon.ico"
} catch {
    Write-Host "Icon conversion failed ($_); continuing without a custom icon."
}

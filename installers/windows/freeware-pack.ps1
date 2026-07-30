# freeware-pack.ps1 - Windows equivalent of assets/freeware_pack.py.
#
# Windows has no python3 by default, so this is a from-scratch port of that
# script's PLAN table and download/extract/base64 logic, using only .NET
# (same "no extra tooling on the target machine" approach as make-icon.ps1).
# It writes the exact same freeware/<key>.js format assets/index.html
# already knows how to load, so nothing on the web page side needs to
# change. Keep this PLAN table in sync with assets/freeware_pack.py's.
#
# Usage: freeware-pack.ps1 -OutDir <dir> -Keys key1,key2,...
# Called once per install, at the end of installer.nsi's Section "Install",
# with the union of keys for every freeware title the user checked.
param(
    [Parameter(Mandatory = $true)][string]$OutDir,
    [Parameter(Mandatory = $true)][string[]]$Keys
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# (key, url, member inside the zip or $null for a raw file, filename the
#  page should present to the engine)
$Plan = @(
    # v1.8 shareware (idgames' v1.9 archive is a DOS self-extracting DEICE
    # package, not a plain zip). Same nine Episode 1 levels as v1.9.
    @{ Key = "doom1";           Url = "https://www.gamers.org/pub/idgames/idstuff/doom/doom-1.8.wad.gz";                        Member = $null;                    Name = "doom1.wad" }
    @{ Key = "freedoom1";       Url = "https://github.com/freedoom/freedoom/releases/download/v0.13.0/freedoom-0.13.0.zip";      Member = "freedoom-0.13.0/freedoom1.wad"; Name = "freedoom1.wad" }
    @{ Key = "freedoom2";       Url = "https://github.com/freedoom/freedoom/releases/download/v0.13.0/freedoom-0.13.0.zip";      Member = "freedoom-0.13.0/freedoom2.wad"; Name = "freedoom2.wad" }
    @{ Key = "hacx";            Url = "https://www.gamers.org/pub/idgames/themes/hacx/hacx12.zip";                               Member = "HACX.WAD";                Name = "hacx.wad" }
    @{ Key = "chex3v";          Url = "https://dsdarchive.com/files/wads/doom/4756/chex3v_1_0.zip";                              Member = "chex3v.wad";              Name = "chex3v.wad" }
    @{ Key = "chex3v_deh";      Url = "https://dsdarchive.com/files/wads/doom/4756/chex3v_1_0.zip";                              Member = "chex3.deh";               Name = "chex3.deh" }
    @{ Key = "chex3v_readme";   Url = "https://dsdarchive.com/files/wads/doom/4756/chex3v_1_0.zip";                              Member = "chex3v_readme.txt";       Name = "chex3v-readme.txt" }
    @{ Key = "harmonyc";        Url = "https://www.gamers.org/pub/idgames/levels/doom2/Ports/g-i/harmonyc.zip";                  Member = "HarmonyC.wad";            Name = "harmonyc.wad" }
    @{ Key = "harmony_deh";     Url = "https://www.gamers.org/pub/idgames/levels/doom2/Ports/g-i/harmonyc.zip";                  Member = "HarmonyC.deh";            Name = "harmony.deh" }
    @{ Key = "wolfen1";         Url = "https://www.gamers.org/pub/idgames/themes/wolf3d/1st_enc.zip";                            Member = "1st_enc.wad";             Name = "1st_enc.wad" }
    @{ Key = "wolfen1_readme";  Url = "https://www.gamers.org/pub/idgames/themes/wolf3d/1st_enc.zip";                            Member = "1st_enc.txt";             Name = "1st_enc-readme.txt" }
    @{ Key = "strain";          Url = "https://www.gamers.org/pub/idgames/levels/doom2/megawads/strain.zip";                     Member = "STRAIN.WAD";              Name = "strain.wad" }
    @{ Key = "strain_deh";      Url = "https://www.gamers.org/pub/idgames/levels/doom2/megawads/strain.zip";                     Member = "STRAIN.DEH";              Name = "strain.deh" }
    @{ Key = "strain_readme";   Url = "https://www.gamers.org/pub/idgames/levels/doom2/megawads/strain.zip";                     Member = "STRAIN.TXT";              Name = "strain-readme.txt" }
    @{ Key = "strain_package";  Url = "https://www.gamers.org/pub/idgames/levels/doom2/megawads/strain.zip";                     Member = $null;                     Name = "strain-package.zip" }
)

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$downloads = @{}   # url -> bytes, so the multi-member zips download once
function Get-UrlBytes($url) {
    if (-not $downloads.ContainsKey($url)) {
        Write-Host ("  downloading {0}" -f ($url -split '/')[-1])
        $wc = New-Object System.Net.WebClient
        try {
            $downloads[$url] = $wc.DownloadData($url)
        } finally {
            $wc.Dispose()
        }
    }
    return $downloads[$url]
}

$failed = @()
foreach ($entry in $Plan) {
    if ($Keys -notcontains $entry.Key) { continue }

    $isRaw = $entry.Name.EndsWith(".txt") -or $entry.Name.EndsWith(".zip")
    $outName = if ($isRaw) { $entry.Name } else { "$($entry.Key).js" }
    $outPath = Join-Path $OutDir $outName
    if (Test-Path $outPath) {
        Write-Host ("  {0}: already packed" -f $entry.Key)
        continue
    }

    try {
        $raw = Get-UrlBytes $entry.Url

        if ($entry.Url.EndsWith(".gz")) {
            $gzStream = New-Object System.IO.MemoryStream(, $raw)
            $decompressed = New-Object System.IO.MemoryStream
            $gzip = New-Object System.IO.Compression.GZipStream($gzStream, [System.IO.Compression.CompressionMode]::Decompress)
            $gzip.CopyTo($decompressed)
            $gzip.Dispose()
            $gzStream.Dispose()
            $raw = $decompressed.ToArray()
            $decompressed.Dispose()
        }

        if ($entry.Member) {
            $zipStream = New-Object System.IO.MemoryStream(, $raw)
            $zip = New-Object System.IO.Compression.ZipArchive($zipStream, [System.IO.Compression.ZipArchiveMode]::Read)
            try {
                $zipEntry = $zip.GetEntry($entry.Member)
                if (-not $zipEntry) { throw "member $($entry.Member) not found in zip" }
                $entryStream = $zipEntry.Open()
                $ms = New-Object System.IO.MemoryStream
                $entryStream.CopyTo($ms)
                $raw = $ms.ToArray()
                $entryStream.Dispose()
                $ms.Dispose()
            } finally {
                $zip.Dispose()
                $zipStream.Dispose()
            }
        }

        if ($isRaw) {
            [System.IO.File]::WriteAllBytes($outPath, $raw)
            Write-Host ("  {0}: installed ({1} bytes)" -f $entry.Key, $raw.Length)
            continue
        }

        if ($entry.Name.EndsWith(".wad")) {
            $magic = [System.Text.Encoding]::ASCII.GetString($raw[0..3])
            if ($magic -ne "IWAD" -and $magic -ne "PWAD") {
                throw "not a WAD (bad magic)"
            }
        }

        $b64 = [Convert]::ToBase64String($raw)
        $keyJson = '"' + $entry.Key + '"'
        $nameJson = '"' + $entry.Name + '"'
        $js = "window.WASM_BUILDER_FREEWARE = window.WASM_BUILDER_FREEWARE || {};`n" +
              "window.WASM_BUILDER_FREEWARE[$keyJson] = { name: $nameJson, b64: `"$b64`" };`n"
        [System.IO.File]::WriteAllText($outPath, $js, [System.Text.Encoding]::ASCII)
        Write-Host ("  {0}: packed ({1:N1} MB)" -f $entry.Key, ($raw.Length / 1MB))
    } catch {
        $failed += $entry.Key
        Write-Host ("  {0}: FAILED ({1})" -f $entry.Key, $_.Exception.Message)
    }
}

if ($failed.Count -gt 0) {
    Write-Host ("Some titles failed: {0}. The page will say so per title." -f ($failed -join ", "))
}

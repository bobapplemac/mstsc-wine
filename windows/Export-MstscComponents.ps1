<#
.SYNOPSIS
    Export the Microsoft Remote Desktop Connection files that mstsc-wine needs into one ZIP.

.DESCRIPTION
    Copies ONLY the files listed below (the same list as packaging/components-policy.json in
    the mstsc-wine repository) from THIS Windows installation into
    mstsc-components-<build>-amd64.zip, with a manifest.json that records, for every file,
    its path under C:\Windows, file version, size and SHA-256.

    Nothing else is collected: no registry data, credentials, domain configuration, user
    names, machine names or other Windows files. The ZIP is never uploaded anywhere; copy it
    to your Linux machine yourself.

    The files are Microsoft's proprietary software. You are responsible for making sure your
    Microsoft license allows you to copy them and to run them on Linux inside a locally built
    mstsc-wine package. The mstsc-wine project grants no rights to Microsoft software.

    Script version: 1.1.0 (manifest schema mstsc-wine-components/1).

.PARAMETER OutputDirectory
    Folder to write the ZIP into. Default: the current folder.

.PARAMETER Language
    Display-language folder of the .mui files (e.g. en-US). Default: the language of the
    installed mstsc.exe.mui found first in the UI language list.

.PARAMETER Experimental
    Allow a Windows build that mstsc-wine has not verified (see the list below). The ZIP is
    marked "experimental" and the Linux build refuses it unless asked to accept it.

.EXAMPLE
    irm https://raw.githubusercontent.com/bobapplemac/mstsc-wine/main/windows/Export-MstscComponents.ps1 | iex

    Quick way: downloads and runs the current version. Writes the ZIP into the current folder.
    Options through environment variables, set first:
      $env:MSTSC_EXPORT_OUTDIR = 'D:\out'; $env:MSTSC_EXPORT_LANGUAGE = 'de-DE'; $env:MSTSC_EXPORT_EXPERIMENTAL = '1'
    or as parameters:
      & ([scriptblock]::Create((irm https://raw.githubusercontent.com/bobapplemac/mstsc-wine/main/windows/Export-MstscComponents.ps1))) -Experimental

.EXAMPLE
    irm https://raw.githubusercontent.com/bobapplemac/mstsc-wine/main/windows/Export-MstscComponents.ps1 -OutFile Export-MstscComponents.ps1
    notepad .\Export-MstscComponents.ps1                 # review it
    powershell -ExecutionPolicy Bypass -File .\Export-MstscComponents.ps1

    Review first: download, read, then run the file. For a fixed version use a tag instead
    of "main" in the URL.

.NOTES
    Needs no administrator rights. Run in 64-bit PowerShell (5.1 or 7).
    Safe to run through Invoke-Expression: errors are reported without closing the
    PowerShell window, and no settings leak into your session.
#>
param(
    [string]$OutputDirectory,
    [string]$Language,
    [switch]$Experimental
)

# Everything runs in a child scope, so that when the script is run with `irm <url> | iex`
# its StrictMode, $ErrorActionPreference and variables do not leak into the user's
# session, and a failure is reported without closing the PowerShell window. Settings can
# also come from environment variables, since `iex` cannot pass parameters.
$mstscExportAsFile = [bool]$PSCommandPath
$mstscExportArgs = @{
    OutputDirectory = $(if ($OutputDirectory) { $OutputDirectory } elseif ($env:MSTSC_EXPORT_OUTDIR) { $env:MSTSC_EXPORT_OUTDIR } else { (Get-Location).Path })
    Language        = $(if ($Language) { $Language } else { [string]$env:MSTSC_EXPORT_LANGUAGE })
    Experimental    = [bool]($Experimental -or $env:MSTSC_EXPORT_EXPERIMENTAL -eq '1')
}
$mstscExportFailed = $false
try {
  & {
    param([string]$OutputDirectory, [string]$Language, [bool]$Experimental)
    Set-StrictMode -Version 3
    $ErrorActionPreference = 'Stop'
    $ScriptVersion = '1.1.0'
    $Schema = 'mstsc-wine-components/1'

    # Keep in sync with packaging/components-policy.json.
    $VerifiedBuilds     = @('20348')
    $ExperimentalBuilds = @('17763','19041','19042','19043','19044','19045','22000','22621','22631','26100')
    $Required = @(
        'System32\mstsc.exe',
        'System32\mstscax.dll',
        'System32\<lang>\mstsc.exe.mui',
        'System32\<lang>\mstscax.dll.mui',
        'SystemResources\mstsc.exe.mun'
    )
    $Recommended = @(
        'SystemResources\mstscax.dll.mun',
        'System32\dui70.dll',
        'System32\<lang>\dui70.dll.mui',
        'System32\duser.dll',
        'System32\<lang>\duser.dll.mui',
        'Fonts\segoeui.ttf', 'Fonts\segoeuib.ttf', 'Fonts\segoeuii.ttf', 'Fonts\segoeuiz.ttf',
        'Fonts\segoeuil.ttf', 'Fonts\seguisb.ttf', 'Fonts\seguisym.ttf', 'Fonts\segmdl2.ttf',
        'Fonts\tahoma.ttf', 'Fonts\tahomabd.ttf', 'Fonts\micross.ttf'
    )

    # Stop with a message. Not `exit`: under `irm | iex` that would close the user's window.
    function Fail([string]$Message) { throw [System.InvalidOperationException]::new($Message) }

    Write-Host @"
mstsc-wine component exporter $ScriptVersion

This copies Microsoft's Remote Desktop Connection files and a few Windows fonts from this
computer into a ZIP file for your own mstsc-wine build. They are Microsoft's proprietary
files: check that your license allows copying them and running them on Linux. Do not share
or publish the ZIP. Nothing is uploaded.

"@

    # --- Windows edition, build and architecture --------------------------------------------
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = [string]$cv.CurrentBuildNumber
    $ubr = 0; if ($cv.PSObject.Properties.Name -contains 'UBR') { $ubr = [int]$cv.UBR }
    $osBuild = "$build.$ubr"
    $product = [string]$cv.ProductName
    $edition = ''; if ($cv.PSObject.Properties.Name -contains 'EditionID') { $edition = [string]$cv.EditionID }
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }
    if ($arch -ne 'AMD64') { Fail "this is $arch Windows; mstsc-wine needs x64 (AMD64) files." }
    if (-not [Environment]::Is64BitProcess) {
        Fail 'run this in 64-bit PowerShell (32-bit PowerShell sees SysWOW64 instead of System32).'
    }

    if ($VerifiedBuilds -contains $build) {
        $support = 'verified'
    } elseif ($Experimental) {
        $support = 'experimental'
        Write-Host "warning: Windows build $build is not verified with mstsc-wine; exporting as experimental." -ForegroundColor Yellow
    } else {
        $known = if ($ExperimentalBuilds -contains $build) { ' It may work: re-run with -Experimental (or set $env:MSTSC_EXPORT_EXPERIMENTAL = ''1'') to try.' } else { '' }
        Fail ("Windows build $build ($product) has not been verified with mstsc-wine " +
              "(verified: $($VerifiedBuilds -join ', ')).$known")
    }

    # --- Language ----------------------------------------------------------------------------
    $win = $env:SystemRoot
    $sys32 = Join-Path $win 'System32'
    if (-not $Language) {
        $candidates = @()
        try { $candidates += (Get-WinUserLanguageList | ForEach-Object { $_.LanguageTag }) } catch { }
        $candidates += [Globalization.CultureInfo]::CurrentUICulture.Name
        $candidates += 'en-US'
        foreach ($c in $candidates) {
            if ($c -and (Test-Path -LiteralPath (Join-Path $sys32 "$c\mstsc.exe.mui"))) { $Language = $c; break }
        }
        if (-not $Language) { Fail 'no <language>\mstsc.exe.mui found in System32; pass -Language (or set $env:MSTSC_EXPORT_LANGUAGE).' }
    }
    if ($Language -notmatch '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$') { Fail "invalid language '$Language'." }

    # --- Collect -----------------------------------------------------------------------------
    function Resolve-Component([string]$Rule) {
        $rel = $Rule.Replace('<lang>', $Language)
        $full = Join-Path $win $rel
        if (Test-Path -LiteralPath $full -PathType Leaf) { return @{ Rel = $rel; Full = $full } }
        return $null
    }

    $files = New-Object System.Collections.ArrayList
    $missingRequired = @()
    foreach ($set in @(@{ Role = 'required'; Rules = $Required }, @{ Role = 'recommended'; Rules = $Recommended })) {
        foreach ($rule in $set.Rules) {
            $c = Resolve-Component $rule
            if (-not $c) {
                if ($set.Role -eq 'required') { $missingRequired += $rule.Replace('<lang>', $Language) }
                else { Write-Host "note: optional file not present: $($rule.Replace('<lang>', $Language))" }
                continue
            }
            $item = Get-Item -LiteralPath $c.Full
            $ver = $null
            if ($c.Rel -match '\.(exe|dll|mui|mun)$') {
                $vi = $item.VersionInfo
                if ($vi.FileMajorPart -or $vi.FileBuildPart) {
                    $ver = '{0}.{1}.{2}.{3}' -f $vi.FileMajorPart, $vi.FileMinorPart, $vi.FileBuildPart, $vi.FilePrivatePart
                }
            }
            $hash = (Get-FileHash -LiteralPath $c.Full -Algorithm SHA256).Hash.ToLowerInvariant()
            $zipPath = 'Windows/' + $c.Rel.Replace('\', '/')
            $entry = [ordered]@{ path = $zipPath; role = $set.Role; size = $item.Length; sha256 = $hash }
            if ($ver) { $entry.file_version = $ver }
            [void]$files.Add([pscustomobject]@{ Entry = $entry; Full = $c.Full; ZipPath = $zipPath })
        }
    }
    if ($missingRequired.Count) { Fail ("required file(s) missing: " + ($missingRequired -join ', ')) }

    # Same build for everything: mstsc.exe and mstscax.dll must match exactly; all binaries
    # must share major.minor.build with mstsc.exe.
    $exeVer = ($files | Where-Object { $_.ZipPath -ieq 'Windows/System32/mstsc.exe' }).Entry.file_version
    $axVer  = ($files | Where-Object { $_.ZipPath -ieq 'Windows/System32/mstscax.dll' }).Entry.file_version
    if ($exeVer -ne $axVer) { Fail "mstsc.exe ($exeVer) and mstscax.dll ($axVer) are from different builds." }
    $b3 = ($exeVer.Split('.')[0..2]) -join '.'
    foreach ($f in $files) {
        $v = $f.Entry['file_version']
        if ($v -and ((($v.Split('.')[0..2]) -join '.') -ne $b3)) {
            Fail "$($f.ZipPath) has version $v, which does not match mstsc.exe $exeVer (mixed builds)."
        }
    }
    if ($exeVer.Split('.')[2] -ne $build) {
        Fail "mstsc.exe build $exeVer does not match this Windows build $osBuild."
    }

    # --- Manifest and ZIP --------------------------------------------------------------------
    $manifest = [ordered]@{
        schema   = $Schema
        created  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
        exporter = "Export-MstscComponents.ps1 $ScriptVersion"
        source   = [ordered]@{
            os_build     = $osBuild
            product      = $product
            edition      = $edition
            architecture = 'amd64'
            language     = $Language
        }
        support  = $support
        files    = @($files | ForEach-Object { $_.Entry })
    }

    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) { Fail "output folder not found: $OutputDirectory" }
    $zipName = "mstsc-components-$osBuild-amd64.zip"
    $zipFile = Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path $zipName
    $tmp = "$zipFile.part"
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $fs = [IO.File]::Open($tmp, [IO.FileMode]::CreateNew)
    try {
        $zip = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
        try {
            $json = $manifest | ConvertTo-Json -Depth 5
            $e = $zip.CreateEntry('manifest.json')
            $w = New-Object IO.StreamWriter($e.Open(), (New-Object Text.UTF8Encoding($false)))
            try { $w.Write($json) } finally { $w.Dispose() }
            foreach ($f in $files) {
                [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.Full, $f.ZipPath,
                    [IO.Compression.CompressionLevel]::Optimal)
            }
        } finally { $zip.Dispose() }
    } finally { $fs.Dispose() }
    Move-Item -LiteralPath $tmp -Destination $zipFile -Force

    $zipHash = (Get-FileHash -LiteralPath $zipFile -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Host ""
    Write-Host "Wrote $zipFile"
    Write-Host "  Windows build $osBuild ($support), language $Language, $($files.Count) files"
    Write-Host "  SHA-256 $zipHash"
    Write-Host ""
    Write-Host "Copy it to your Linux machine (e.g. into mstsc-wine/private-input/) and run 'make'."
    Write-Host "Keep it private: it contains Microsoft's proprietary files."
  } @mstscExportArgs
} catch {
    $mstscExportFailed = $true
    Write-Host "error: $($_.Exception.Message)" -ForegroundColor Red
}
if ($mstscExportAsFile -and $mstscExportFailed) { exit 1 }
Remove-Variable mstscExportAsFile, mstscExportArgs, mstscExportFailed -ErrorAction SilentlyContinue

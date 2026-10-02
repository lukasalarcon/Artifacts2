<#
.SYNOPSIS
    Installs the latest stable Google Chrome (Enterprise, 64-bit) silently for all users.

.DESCRIPTION
    Azure DevTest Labs artifact script. Downloads the Chrome Enterprise MSI straight
    from Google, checks that the file is signed by Google, and installs it with msiexec.
    Exits with a non-zero code on any failure so the lab marks the artifact as failed.
#>

[CmdletBinding()]
param(
    [string] $InstallerUrl = 'https://dl.google.com/chrome/install/googlechromestandaloneenterprise64.msi'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # speeds up Invoke-WebRequest

# Older Windows images default to TLS 1.0, which dl.google.com rejects.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$workDir   = Join-Path $env:TEMP 'dtl-chrome'
$msiPath   = Join-Path $workDir 'googlechromestandaloneenterprise64.msi'
$msiLog    = Join-Path $workDir 'chrome-install.log'

try {
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null

    Write-Output "Downloading Chrome from $InstallerUrl"
    Invoke-WebRequest -Uri $InstallerUrl -OutFile $msiPath -UseBasicParsing

    Write-Output 'Checking the installer signature'
    $signature = Get-AuthenticodeSignature -FilePath $msiPath
    if ($signature.Status -ne 'Valid') {
        throw "Installer signature is not valid (status: $($signature.Status))."
    }
    if ($signature.SignerCertificate.Subject -notmatch 'O=Google LLC') {
        throw "Installer is not signed by Google (signer: $($signature.SignerCertificate.Subject))."
    }

    Write-Output 'Installing Chrome'
    $arguments = "/i `"$msiPath`" /qn /norestart /L*v `"$msiLog`""
    $process   = Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -Wait -PassThru

    # 0 = success, 3010 = success but a reboot is pending
    if ($process.ExitCode -notin 0, 3010) {
        throw "msiexec failed with exit code $($process.ExitCode). See $msiLog"
    }

    Write-Output "Chrome installed (msiexec exit code $($process.ExitCode))."
    Remove-Item -Path $msiPath -Force -ErrorAction SilentlyContinue
    exit 0
}
catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    exit 1
}

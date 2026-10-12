param([Parameter(Mandatory=$true)][string]$Installer)
$ErrorActionPreference = 'Stop'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
if (Get-ItemProperty -Path $runKey -Name 'CampusConnect.Windows' -ErrorAction SilentlyContinue) { throw 'Use a clean test user without a CampusConnect startup entry.' }
$Installer = (Resolve-Path $Installer).Path
$registryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\CampusConnect.Windows'
if (Test-Path $registryPath) { throw 'Use a clean Windows test user; CampusConnect is already installed.' }
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('CampusConnect custom path test ' + [guid]::NewGuid().ToString('N'))
$first = Join-Path $sandbox 'First install'
$second = Join-Path $sandbox ('Second install ' + ([string][char]0x6821))
if (Test-Path 'D:\') { $second = Join-Path 'D:\' ('CampusConnect directory test ' + [guid]::NewGuid().ToString('N')) }
$shell = New-Object -ComObject WScript.Shell
$appName = ([string][char]0x6821) + ([string][char]0x56ed) + ' Wi-Fi ' + ([string][char]0x52a9) + ([string][char]0x624b)
$desktopShortcut = Join-Path ($shell.SpecialFolders.Item('Desktop')) ($appName + '.lnk')
$menuUninstallShortcut = Join-Path (Join-Path ($shell.SpecialFolders.Item('Programs')) $appName) (([string][char]0x5378) + ([string][char]0x8f7d) + $appName + '.lnk')
$menuShortcut = Join-Path (Join-Path ($shell.SpecialFolders.Item('Programs')) $appName) ($appName + '.lnk')
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class InstallerWizard {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern uint GetLongPathName(string path, StringBuilder result, uint capacity);
    public static string LongPath(string path) {
        var result = new StringBuilder(32768);
        uint length = GetLongPathName(path, result, (uint)result.Capacity);
        if (length == 0 || length >= result.Capacity) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        return result.ToString();
    }
    public delegate bool EnumCallback(IntPtr hwnd, IntPtr context);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumCallback callback, IntPtr context);
    public static IntPtr FindWizard(string title) {
        IntPtr result = IntPtr.Zero;
        EnumWindows((hwnd, _) => {
            if (!IsWindowVisible(hwnd)) return true;
            var text = new StringBuilder(1024); GetWindowText(hwnd, text, text.Capacity);
            if (text.ToString().Contains(title)) { result = hwnd; return false; }
            return true;
        }, IntPtr.Zero);
        return result;
    }
    public static string Describe(IntPtr parent) {
        var result = new StringBuilder();
        EnumChildWindows(parent, (hwnd, _) => {
            if (!IsWindowVisible(hwnd)) return true;
            var text = new StringBuilder(1024); GetWindowText(hwnd, text, text.Capacity);
            result.AppendLine(GetDlgCtrlID(hwnd) + ": " + text.ToString());
            return true;
        }, IntPtr.Zero);
        return result.ToString();
    }
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumCallback callback, IntPtr context);
    [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr parent, int id);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", EntryPoint="SendMessageW", CharSet=CharSet.Unicode)] public static extern IntPtr SetText(IntPtr hwnd, uint message, IntPtr wParam, string text);
    public static IntPtr Find(IntPtr parent, int id, string title) {
        if (parent == IntPtr.Zero) return IntPtr.Zero;
        IntPtr result = IntPtr.Zero;
        EnumChildWindows(parent, (hwnd, _) => {
            if (!IsWindowVisible(hwnd)) return true;
            var text = new StringBuilder(1024); GetWindowText(hwnd, text, text.Capacity);
            if ((id != 0 && GetDlgCtrlID(hwnd) == id) || (id == 0 && title != null && text.ToString() == title)) { result = hwnd; return false; }
            return true;
        }, IntPtr.Zero);
        return result;
    }
}
'@
function Install-WithWizard([string]$Target) {
    $process = Start-Process -FilePath $Installer -PassThru
    function Wait-Control([int]$Id, [string]$Title = $null) {
        Write-Host "Waiting for wizard control id=$Id title=$Title"
        $deadline = [DateTime]::UtcNow.AddSeconds(120)
        do {
            # NSIS may run its UI in a child process; resolve the visible wizard itself.
            $wizard = [InstallerWizard]::FindWizard($appName)
            $handle = [InstallerWizard]::Find($wizard, $Id, $Title)
            if ($handle -ne [IntPtr]::Zero) { return $handle }
            Start-Sleep -Milliseconds 150
        } while ([DateTime]::UtcNow -lt $deadline)
        $details = [InstallerWizard]::Describe($wizard)
        throw "The wizard did not display control id=$Id title=$Title; hwnd=$wizard; visible controls: $details"
    }
    function Click-Next {
        $wizard = [InstallerWizard]::FindWizard($appName)
        $button = [InstallerWizard]::GetDlgItem($wizard, 1)
        if ($button -eq [IntPtr]::Zero) { throw 'Wizard Next button not found.' }
        [InstallerWizard]::SendMessage($button, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
        Start-Sleep -Milliseconds 300
    }
    try {
        $null = Wait-Control 1
        Click-Next
        $directoryBox = Wait-Control 1019
        [InstallerWizard]::SetText($directoryBox, 0x000C, [IntPtr]::Zero, $Target) | Out-Null
        Click-Next
        Click-Next
        $runCheckbox = Wait-Control 0 ('立即运行' + $appName)
        [InstallerWizard]::SendMessage($runCheckbox, 0x00F1, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
        Click-Next
        if (-not $process.WaitForExit(10000) -or $process.ExitCode -ne 0) { throw 'Interactive installation failed.' }
    } finally {
        if (-not $process.HasExited) { $process.Kill() }
    }
}
function Install-App([string]$Target, [switch]$Wizard) {
    # NSIS /D must be last and unquoted, including when the directory has spaces.
    if ($Wizard) { Install-WithWizard $Target }
    else {
        $process = Start-Process -FilePath $Installer -ArgumentList "/S /D=$Target" -Wait -PassThru
        if ($process.ExitCode -ne 0) { throw "Setup failed: $($process.ExitCode)" }
    }
    if (-not (Test-Path (Join-Path $Target 'CampusConnect.exe'))) { throw 'Custom installation directory was ignored.' }
    $entry = Get-ItemProperty $registryPath
    if ($entry.InstallLocation -ne $Target) { throw 'Uninstall registration has the wrong installation path.' }
    $expectedUninstaller = Join-Path $Target 'Uninstall.exe'
    if ($entry.UninstallString -ne ('"' + $expectedUninstaller + '"')) { throw 'Windows Settings has an invalid uninstall command.' }
    if ($entry.QuietUninstallString -ne ('"' + $expectedUninstaller + '" /S')) { throw 'The registered silent uninstall command is invalid.' }
    if ((Get-Item $expectedUninstaller).Length -lt 1024) { throw 'Uninstaller is missing or incomplete.' }
    if (-not (Test-Path $desktopShortcut)) { throw 'Desktop shortcut is missing.' }
    if ([InstallerWizard]::LongPath($shell.CreateShortcut($desktopShortcut).TargetPath) -ne [InstallerWizard]::LongPath((Join-Path $Target 'CampusConnect.exe'))) { throw 'Shortcut points to the wrong app.' }
    if (-not (Test-Path $menuUninstallShortcut)) { throw 'Start menu uninstall entry is missing.' }
    if ([InstallerWizard]::LongPath($shell.CreateShortcut($menuUninstallShortcut).TargetPath) -ne [InstallerWizard]::LongPath($expectedUninstaller)) { throw 'Start menu uninstall entry points to the wrong file.' }
    if (-not (Test-Path $menuShortcut)) { throw 'Start menu shortcut is missing.' }
    if ([InstallerWizard]::LongPath($shell.CreateShortcut($menuShortcut).TargetPath) -ne [InstallerWizard]::LongPath((Join-Path $Target 'CampusConnect.exe'))) { throw 'Start menu points to the wrong app.' }
    $appFiles = @(Get-ChildItem $Target -Recurse -File | Where-Object { $_.Name -ne 'unrelated-user-file.txt' })
    $executables = @($appFiles | Where-Object { $_.Extension -eq '.exe' })
    if ($executables.Count -ne 2 -or ($executables.Name -notcontains 'Uninstall.exe')) { throw 'The installation must contain the app and uninstaller.' }
    if (-not (Test-Path (Join-Path $Target 'licenses/CampusConnect-LICENSE.txt'))) { throw 'Project license missing from installation.' }
    if (-not (Test-Path (Join-Path $Target 'licenses/WebView2-LICENSE.txt'))) { throw 'WebView2 license missing from installation.' }
    if (@($appFiles | Where-Object { $_.Extension -eq '.dll' }).Count -ne 0) { throw 'Unexpected loose DLL in single-file installation.' }
}
try {
    New-Item -ItemType Directory -Path $first -Force | Out-Null
    $sentinel = Join-Path $first 'unrelated-user-file.txt'
    Set-Content $sentinel 'This must survive migration and uninstall.'
    Install-App $first -Wizard
    New-Item -Path $runKey -Force | Out-Null
    Set-ItemProperty $runKey 'CampusConnect.Windows' ('"' + (Join-Path $first 'CampusConnect.exe') + '" --startup')
    # Reproduce a broken Windows Settings entry and a missing uninstall executable.
    Remove-Item (Join-Path $first 'Uninstall.exe')
    Set-ItemProperty $registryPath 'UninstallString' ('"' + (Join-Path $first 'missing-uninstaller.exe') + '"')
    Install-App $first
    if (-not (Test-Path $sentinel)) { throw 'Uninstaller repair deleted unrelated files.' }
    Install-App $first
    Install-App $second -Wizard
    $startupCommand = (Get-ItemProperty $runKey).'CampusConnect.Windows'
    if ($startupCommand -ne ('"' + (Join-Path $second 'CampusConnect.exe') + '" --startup')) { throw 'Upgrade did not preserve startup or update its path.' }
    $uiReport = Join-Path $sandbox 'ui-report.json'
    $uiProcess = Start-Process -FilePath (Join-Path $second 'CampusConnect.exe') -ArgumentList ('--verify-ui "' + $uiReport + '"') -PassThru
    if (-not $uiProcess.WaitForExit(60000)) {
        $uiProcess.Kill()
        throw 'Single-file app did not initialize its WebView2 UI.'
    }
    if (-not (Test-Path $uiReport)) { throw 'The single-file app could not create its UI.' }
    $uiResult = Get-Content $uiReport -Raw | ConvertFrom-Json
    if ($uiResult.pageCount -ne 3 -or -not $uiResult.passwordMasked -or -not $uiResult.startupToggle -or $uiResult.byYe -ne 'By Ye') { throw 'UI startup checks failed.' }
    $trayReport = Join-Path $sandbox 'tray-report.json'
    $trayProcess = Start-Process -FilePath (Join-Path $second 'CampusConnect.exe') -ArgumentList ('--startup --verify-ui "' + $trayReport + '"') -PassThru
    if (-not $trayProcess.WaitForExit(60000)) { $trayProcess.Kill(); throw 'Tray startup did not initialize.' }
    $trayResult = Get-Content $trayReport -Raw | ConvertFrom-Json
    if ($trayResult.mainWindowVisible -or $trayResult.showInTaskbar -or -not $trayResult.startupToggle) { throw 'Logon startup must initialize while hidden in the tray.' }
    if (Test-Path (Join-Path $first 'CampusConnect.exe')) { throw 'Old application files remain after directory migration.' }
    if (-not (Test-Path $sentinel)) { throw 'Migration deleted unrelated files.' }
    # Execute the registered command, rather than bypassing the Windows Settings entry.
    $entry = Get-ItemProperty $registryPath
    $process = $shell.Exec($entry.QuietUninstallString)
    $launchDeadline = [DateTime]::UtcNow.AddSeconds(30)
    while ($process.Status -eq 0 -and [DateTime]::UtcNow -lt $launchDeadline) { Start-Sleep -Milliseconds 200 }
    if ($process.Status -eq 0) { $process.Terminate(); throw 'The registered uninstaller did not finish.' }
    if ($process.ExitCode -ne 0) { throw 'The registered uninstaller could not run.' }
    # NSIS may launch its copied uninstaller from TEMP before the original process exits.
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while ((Test-Path $registryPath) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 200 }
    if (Test-Path $registryPath) { throw 'Uninstall registration was not removed.' }
    if (Test-Path (Join-Path $second 'CampusConnect.exe')) { throw 'Uninstall did not remove the app.' }
    if (Test-Path $desktopShortcut) { throw 'Desktop shortcut survived uninstall.' }
    if (Get-ItemProperty -Path $runKey -Name 'CampusConnect.Windows' -ErrorAction SilentlyContinue) { throw 'Startup entry survived uninstall.' }
    if (Test-Path $menuShortcut) { throw 'Start menu shortcut survived uninstall.' }
    if (-not (Test-Path $sentinel)) { throw 'Uninstall deleted unrelated files.' }
    Write-Host 'PASS: custom path with spaces, shortcut target, missing-uninstaller repair, registry command, reinstall, directory migration, uninstall, unrelated-file preservation.'
} finally {
    if (-not (Test-Path $registryPath) -and (Test-Path $sandbox)) { Remove-Item $sandbox -Recurse -Force }
    if (-not (Test-Path $registryPath) -and (Test-Path $second)) { Remove-Item $second -Recurse -Force }
}

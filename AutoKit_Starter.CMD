@echo off
REM AutoKit_Starter.CMD -- new-hire first-install wizard (single file: batch header + embedded PowerShell body)
REM Self-elevates, reads its own file text, extracts everything after the marker line as PowerShell,
REM runs it via Invoke-Expression, then deletes itself (one-time-use; avoids cmd.exe's 8191-char line
REM limit that a single-line "-EncodedCommand <huge base64>" approach would hit for a script this size).
setlocal
cd /d "%~dp0"
chcp 65001 >nul
REM 2026-08-04 note: net session depends on the Server service, which is often disabled on lean or
REM fresh machines; that made an already-elevated process misjudge itself as non-admin and keep
REM re-launching itself via RunAs forever, never reaching the real body. Switched the check to
REM fltmc, which fails immediately for non-admins and does not depend on any disable-able service.
REM Same fix already used by AutoKit_FixDefender.CMD elsewhere in this project.
fltmc >nul 2>&1
if %errorlevel% neq 0 (
    set "SELF=%~f0"
    powershell -NoProfile -Command "Start-Process -FilePath $env:SELF -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $__mk='##INSTALLER'+'-PS-BODY##'; $__raw=[IO.File]::ReadAllText('%~f0'); $__parts=$__raw -split [regex]::Escape($__mk),2; if($__parts.Count -lt 2){throw 'installer body marker not found'}; Invoke-Expression $__parts[1] } catch { Write-Host ''; Write-Host ('[ERROR] Starter crashed: ' + $_.Exception.Message) -ForegroundColor Red; try { Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray } catch {}; Write-Host ''; Read-Host 'Press Enter to close' }"
REM no pause: closes on its own once the PowerShell body above returns (success or failure)
timeout /t 2 /nobreak >nul
del "%~f0" >nul 2>&1
exit /b
##INSTALLER-PS-BODY##
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'   # 关掉 Invoke-WebRequest/Invoke-RestMethod 默认进度浮层(同 AutoDownload.ps1 Get-ADConfig 手法)
                                            # ——传统 conhost 下这浮层有时会退化成裸文字滚屏("Writing web request"/"Writing request stream...")

$__credsB64 = 'eyJpbnN0YWxsZWQiOnsiY2xpZW50X2lkIjoiNjY2OTAxNjEyNTI2LTh2aTBzM2o0dDJ1cGQ5dThiZmZxdGl2aG1yZGxnY2szLmFwcHMuZ29vZ2xldXNlcmNvbnRlbnQuY29tIiwicHJvamVjdF9pZCI6Indlc3Rlcm4tY2FzY2FkZS01MDAyMDMtdDciLCJhdXRoX3VyaSI6Imh0dHBzOi8vYWNjb3VudHMuZ29vZ2xlLmNvbS9vL29hdXRoMi9hdXRoIiwidG9rZW5fdXJpIjoiaHR0cHM6Ly9vYXV0aDIuZ29vZ2xlYXBpcy5jb20vdG9rZW4iLCJhdXRoX3Byb3ZpZGVyX3g1MDlfY2VydF91cmwiOiJodHRwczovL3d3dy5nb29nbGVhcGlzLmNvbS9vYXV0aDIvdjEvY2VydHMiLCJjbGllbnRfc2VjcmV0IjoiR09DU1BYLWktSUtLc3I4SHZCNURQdmQ0aE5OVk5QWXJMNjkiLCJyZWRpcmVjdF91cmlzIjpbImh0dHA6Ly9sb2NhbGhvc3QiXX19'
$__tokenB64 = 'ew0KICAgICJyZWZyZXNoX3Rva2VuIjogICIxLy8wZ2FuTEo5Z3FSbmZfQ2dZSUFSQUFHQkFTTndGLUw5SXJUNEN2Y09FUUZYc1RGSUJZbDZGZ2p0X05FMnY1YnpTdmIwYlRpc3NsTmcwRU9LUFZXbTEzSHRDckhnejJSUlNQdnhVIiwNCiAgICAidG9rZW5fdXJpIjogICJodHRwczovL29hdXRoMi5nb29nbGVhcGlzLmNvbS90b2tlbiIsDQogICAgInNjb3BlIjogICJodHRwczovL3d3dy5nb29nbGVhcGlzLmNvbS9hdXRoL2RyaXZlLnJlYWRvbmx5Ig0KfQ=='

# WT 渲染重影修复(同 Opt.Theme.ps1 Set-UnifiedConsole/Clear-HostHard 手法, 本脚本不依赖那个文件, 内联精简版):
# UAC 自举重启弹出的新窗口刚出现时, Windows Terminal 还在异步协商/结算尺寸, 这期间写的头几行文字会被
# "重画"两次(肉眼看到"正正在在连连接接..."这种逐字重复)。先用 CSI 8;行;列 t 显式定死尺寸并轮询到生效,
# 再硬清屏(含 scrollback, 单纯 Clear-Host 不清)清掉结算期间已经画花的残留, 真正的输出从这里才开始。
try {
    $__w = 100; $__h = 30
    try {
        $__ui = $Host.UI.RawUI
        $__max = $__ui.MaxWindowSize
        $__ww = [math]::Min($__w, $__max.Width); $__wh = [math]::Min($__h, $__max.Height)
        $__cw = $__ui.WindowSize
        $__cw.Width = [math]::Min($__cw.Width, $__ww); $__cw.Height = [math]::Min($__cw.Height, $__wh)
        $__ui.WindowSize = $__cw
        $__ui.BufferSize = New-Object System.Management.Automation.Host.Size($__ww, 3000)
        $__ui.WindowSize = New-Object System.Management.Automation.Host.Size($__ww, $__wh)
    } catch {}
    if ($env:WT_SESSION -or $Host.UI.SupportsVirtualTerminal) {
        [Console]::Write(("{0}[8;{1};{2}t" -f [char]27, $__h, $__w))
        $__n = 0
        while ($__n -lt 25) { Start-Sleep -Milliseconds 40; if ([Console]::WindowHeight -ge $__h) { break }; $__n++ }
        [Console]::Write(("{0}[2J{0}[3J{0}[H" -f [char]27))
    }
} catch {}

# CJK 字体切换(同 Opt.Theme.ps1 Set-ConsoleFontFamily 手法, 本脚本不依赖那个文件, 内联精简版):
# chcp 65001 只管编码, 传统 conhost(非 Windows Terminal)默认字体 Consolas 不含中文字形 -> 编码再对
# 屏幕上仍会退化显示成 "? ? ? ?" 方块问号。必须额外把控制台字体切到含 CJK 字形的候选字体才能真正显示中文。
try {
    $__fontTypeSrc = 'using System;' + "`n" + 'using System.Runtime.InteropServices;' + "`n" +
        'public class CKInstallerFont {' + "`n" +
        '  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]' + "`n" +
        '  public struct CONSOLE_FONT_INFOEX {' + "`n" +
        '    public uint cbSize; public uint nFont; public short FontWidth; public short FontHeight;' + "`n" +
        '    public uint FontSeries; public uint FontWeight;' + "`n" +
        '    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string FaceName;' + "`n" +
        '  }' + "`n" +
        '  [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int h);' + "`n" +
        '  [DllImport("kernel32.dll")] public static extern bool SetCurrentConsoleFontEx(IntPtr h, bool b, ref CONSOLE_FONT_INFOEX f);' + "`n" +
        '  [DllImport("kernel32.dll")] public static extern bool GetCurrentConsoleFontEx(IntPtr h, bool b, ref CONSOLE_FONT_INFOEX f);' + "`n" +
        '}'
    Add-Type -TypeDefinition $__fontTypeSrc -EA SilentlyContinue
    $__cjkSafe = @('NSimSun','MS Gothic','Microsoft YaHei','Microsoft YaHei UI','Cascadia Mono','Cascadia Code','SimSun','SimHei')
    $__cf = New-Object CKInstallerFont+CONSOLE_FONT_INFOEX
    $__cf.cbSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf($__cf)
    $__ch = [CKInstallerFont]::GetStdHandle(-11)
    if ([CKInstallerFont]::GetCurrentConsoleFontEx($__ch, $false, [ref]$__cf) -and ($__cjkSafe -inotcontains $__cf.FaceName)) {
        foreach ($__face in @('NSimSun', 'MS Gothic', 'Cascadia Mono')) {
            $__nf = New-Object CKInstallerFont+CONSOLE_FONT_INFOEX
            $__nf.cbSize = $__cf.cbSize; $__nf.FaceName = $__face
            $__nf.FontHeight = if ($__cf.FontHeight -gt 0) { $__cf.FontHeight } else { 18 }
            $__nf.FontWeight = 500
            if ([CKInstallerFont]::SetCurrentConsoleFontEx($__ch, $false, [ref]$__nf)) { break }
        }
    }
} catch {}

# 2026-08-04: 统一视觉风格 -- 之前 Defender 预处理段整块是英文, 跟其余全中文的向导文字混在一起显得
# 格格不入; 现在跟 AutoKit_FixDefender.CMD/其余工具同款: 顶部方框标题 + [n/3] 分步小标题 + 细线分隔 +
# 统一的 [OK]/[WARN]/[ERROR] 三色语义(绿/黄/红), 全文改中文。
# ── 显示宽度助手(2026-08-20) ────────────────────────────────────────────────────────
# 为什么需要: 下面那两个方框原来是【手数空格】拼出来的, 而中日韩字符在控制台占【两列】—— 本脚本上面还主动
#   把控制台字体强制成 NSimSun / MS Gothic 等 CJK 字体, 所以双宽是确定的, 不是"看运气"。
#   'AutoKit 首次装机向导' 按字符数是 15, 按【显示宽度】是 22, 于是右边框被顶出去 4 列 ——
#   真机截图上方框右边就是一根飘在外面的 ║(下面那个"安装完成"框同理差 3 列)。标签冒号也是同一个病。
# 算法逐字照搬 Core\Theme\Opt.Theme.ps1 的 Get-DisplayWidth —— 本脚本是【独立生成物】(要嵌进 .CMD 单独跑),
#   不能 dot-source 那个文件, 只能内联; 但照搬而不是另写一套, 免得两处宽度表将来各自漂移。
function Get-AkDispW {
    param([string]$s)
    if (-not $s) { return 0 }
    $w = 0
    foreach ($ch in $s.ToCharArray()) {
        $code = [int][char]$ch
        if (($code -ge 0x1100 -and $code -le 0x115F) -or `
            ($code -ge 0x2E80 -and $code -le 0x303E) -or `
            ($code -ge 0x3041 -and $code -le 0x33FF) -or `
            ($code -ge 0x3400 -and $code -le 0x4DBF) -or `
            ($code -ge 0x4E00 -and $code -le 0x9FFF) -or `
            ($code -ge 0xA000 -and $code -le 0xA4CF) -or `
            ($code -ge 0xAC00 -and $code -le 0xD7A3) -or `
            ($code -ge 0xF900 -and $code -le 0xFAFF) -or `
            ($code -ge 0xFE30 -and $code -le 0xFE4F) -or `
            ($code -ge 0xFF00 -and $code -le 0xFF60) -or `
            ($code -ge 0xFFE0 -and $code -le 0xFFE6)) { $w += 2 } else { $w += 1 }
    }
    return $w
}
# 方框: 内宽固定 42(与下面分隔线的 44 = 2 个边框字 + 42 对齐), 标题按显示宽度居中
function Write-AkBox {
    # -En: 第二行英文(C 方案上中文·下英文)。内宽取【两行中较宽者】并留 4 列余量 ——
    #      原来死写 42, 文字一长右边那根 ║ 就被顶出框外(真机截图可见)。
    param([string]$Text, [string]$Color = 'Cyan', [string]$En = '')
    $w1 = Get-AkDispW $Text
    $w2 = Get-AkDispW $En
    $inner = [Math]::Max(42, ([Math]::Max($w1, $w2) + 4))
    $bar = '═' * $inner
    Write-Host ''
    Write-Host ('  ╔' + $bar + '╗') -ForegroundColor $Color
    foreach ($__ln in @($Text, $En)) {
        if (-not $__ln) { continue }
        $__w = Get-AkDispW $__ln
        $__l = [Math]::Max(0, [int][Math]::Floor(($inner - $__w) / 2))
        $__r = [Math]::Max(0, $inner - $__w - $__l)
        Write-Host ('  ║' + (' ' * $__l) + $__ln + (' ' * $__r) + '║') -ForegroundColor $Color
    }
    Write-Host ('  ╚' + $bar + '╝') -ForegroundColor $Color
}
# 标签: 按显示宽度右填充, 让一组标签的冒号成列(原来也是手数空格, 于是"防篡改保护"/"实时防护"/"Defender 模式"
# 三行的冒号各错一格)
function Write-AkKv {
    # 标签写成「中文 (English)」时自动拆两行(C 方案): 中文行带冒号与值, 英文行单独缩进暗色。
    param([string]$Label, [string]$Value, [string]$Color = 'Gray')
    $__m = [regex]::Match([string]$Label, '^\s*(.+?)\s*\(([^()]+)\)\s*$')
    if ($__m.Success -and $__m.Groups[2].Value -match '[A-Za-z]') {
        $__cn = $__m.Groups[1].Value; $__en = $__m.Groups[2].Value
    } else { $__cn = [string]$Label; $__en = '' }
    $pad = [Math]::Max(0, 16 - (Get-AkDispW $__cn))
    Write-Host ('  ' + $__cn + (' ' * $pad) + ': ' + $Value) -ForegroundColor $Color
    if ($__en) { Write-Host ('  ' + $__en) -ForegroundColor DarkGray }
}
# 提示: 第二行缩进的补充说明(把"该找谁/影响是什么"跟结论分开, 免得一行挤成天书)
function Write-AkHint {
    param([string]$Text)
    Write-Host ('         ' + $Text) -ForegroundColor DarkGray
}

Write-AkBox 'AutoKit 首次装机向导' 'Cyan' -En 'First-time setup wizard'

function Write-AkStepTitle {
    # -En: 第二行英文(C 方案)。中文亮色主行, 英文暗色副行, 再画分隔线
    param([string]$Text, [string]$En = '')
    Write-Host ''
    Write-Host ('  ' + $Text) -ForegroundColor Cyan
    if ($En) { Write-Host ('  ' + $En) -ForegroundColor DarkGray }
    Write-Host ('  ' + ('─' * 44)) -ForegroundColor DarkGray
}

Write-AkStepTitle '[1/3] 系统环境预处理' -En '      Prepare system environment'

# 2026-08-04: 部分全新机器默认 ExecutionPolicy 完全不让跑脚本(Restricted), 连这个 Starter 自身
# 靠命令行 -ExecutionPolicy Bypass 都不一定顶得住(若是 GPO/Intune 机器策略强制, Bypass 和这条
# LocalMachine 注册表项都盖不过 GPO, 只能改 Intune 策略; 但多数"全新裸机"是本机默认 Restricted,
# 这条能一次性解开)。RemoteSigned 而非 Unrestricted: 允许本机脚本跑、下载的脚本仍要签名, 不是完全放开。
try {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force -ErrorAction Stop
    Write-Host '  [OK] 脚本执行策略已设为 RemoteSigned' -ForegroundColor Green; Write-Host '       Execution policy set to RemoteSigned' -ForegroundColor DarkGray
} catch {
    # 2026-08-20: 原来直接把 $_.Exception.Message 贴上屏, 而这里最常见的那条消息就是裸的 "Security error."——
    #   对装机的人来说这句话零信息量, 还很吓人(以为装坏了)。真实含义是"被组织策略锁死了, 而且这不影响装机"。
    #   原始异常文本改只写日志/不上屏; 屏幕上给结论 + 该找谁。
    Write-Host '  [WARN] 执行策略被组织策略锁定, 已跳过' -ForegroundColor Yellow; Write-Host '       Execution policy is locked by org policy - skipped' -ForegroundColor DarkGray
    Write-AkHint '(不影响装机; 若后续脚本被拦, 需桌面运维调整 Intune 策略)'
}

# 2026-08-04: Defender 排除/关实时防护这一段合并进 Starter, 且先于装机执行 —— 新机器 Defender 全力
# 开着时, Starter 刚落地的 exe 文件本身就可能被实时防护/AMSI 隔离(装完即被删), 必须先把 C:\AutoKit
# 加成排除路径, 再动手写 exe, 否则会出现"日志说装完了但文件不见了"的假阳性。
# ⚠ 2026-08-04 更正陈旧陈述: 原注释说本段"逐字对应 AutoKit_FixDefender.ps1(独立文件保留, 供已装机
#   单独重跑)" —— 全仓库【不存在】AutoKit_FixDefender.ps1(唯一同名物是另一个产品的
#   ControlioFix\Client\ControlioFix_FixAV.CMD, 2026-08-05 改名并扩展成多杀软版前叫这个名字)。也就是说
#   AutoKit 侧没有可单独重跑的独立文件,
#   下面这份就是唯一实现; 已装机要重跑排除, 只能重跑 Starter 或手动 Add-MpPreference。
function Path-IsCovered {
    param([string]$Target, [string[]]$Existing)
    foreach ($e in @($Existing)) {
        if (-not $e) { continue }
        $ee = ([string]$e).TrimEnd('\')
        $tt = ([string]$Target).TrimEnd('\')
        if ($tt.Equals($ee, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($tt.StartsWith($ee, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($ee.StartsWith($tt, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}
function Disable-RealtimeAndPolicy {
    Write-Host '  正在关闭实时防护...' -ForegroundColor DarkGray; Write-Host '  Turning off real-time protection...' -ForegroundColor DarkGray
    try {
        Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction Stop
        Start-Sleep -Milliseconds 800
        $rtpNow = $null
        try { $rtpNow = [bool](Get-MpComputerStatus -ErrorAction Stop).RealTimeProtectionEnabled } catch {}
        if ($rtpNow -eq $false) { Write-Host '  [OK] 实时防护已关闭' -ForegroundColor Green; Write-Host '       Real-time protection is off' -ForegroundColor DarkGray }
        else { Write-Host '  [WARN] 实时防护未能关闭, 可能被策略/防篡改保护挡住' -ForegroundColor Yellow; Write-Host '       Could not turn it off - blocked by policy or Tamper Protection' -ForegroundColor DarkGray }
    } catch {
        Write-Host '  [WARN] 关闭实时防护失败, 保持原状' -ForegroundColor Yellow; Write-Host '       Failed to change it - left as is' -ForegroundColor DarkGray
        Write-AkHint ('原因: ' + $_.Exception.Message)
    }
    try {
        $polKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
        if (-not (Test-Path -LiteralPath $polKey)) { New-Item -Path $polKey -Force | Out-Null }
        New-ItemProperty -Path $polKey -Name 'DisableAntiSpyware' -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
        Write-Host '  [OK] 策略注册表键已写入' -ForegroundColor Green; Write-Host '       Policy registry keys written' -ForegroundColor DarkGray
    } catch {
        Write-Host '  [WARN] 写入 Defender 策略键失败, 已跳过' -ForegroundColor Yellow; Write-Host '       Could not write Defender policy keys - skipped' -ForegroundColor DarkGray
        Write-AkHint ('原因: ' + $_.Exception.Message)
    }
}
$__fdExclusions = @('C:\AutoKit', 'C:\ProgramData\AutoActivate')
$__fdTamper = $false; $__fdRtpOn = $null; $__fdAmMode = ''
try {
    $__fdSt = Get-MpComputerStatus -ErrorAction Stop
    $__fdTamper = [bool]$__fdSt.IsTamperProtected
    $__fdRtpOn = [bool]$__fdSt.RealTimeProtectionEnabled
    $__fdAmMode = [string]$__fdSt.AMRunningMode
} catch {
    Write-Host '  [WARN] 读不到 Defender 状态, 下面按保守路径处理' -ForegroundColor Yellow; Write-Host '       Cannot read Defender status - using the safe path below' -ForegroundColor DarkGray
    Write-AkHint ('原因: ' + $_.Exception.Message)
}
Write-AkKv '防篡改保护 (Tamper Protection)' $(if ($__fdTamper) { '开启 (On)' } else { '关闭 (Off)' }) $(if ($__fdTamper) { 'Yellow' } else { 'Green' })
if ($null -ne $__fdRtpOn) { Write-AkKv '实时防护 (Real-time Protection)' $(if ($__fdRtpOn) { '开启 (On)' } else { '关闭 / 被动模式 (Off / Passive)' }) $(if ($__fdRtpOn) { 'Yellow' } else { 'Green' }) }
if ($__fdAmMode) { Write-AkKv 'Defender 模式 (Defender Mode)' $__fdAmMode 'DarkGray' }
if ($__fdAmMode -match 'Not running' -or $__fdRtpOn -eq $false) {
    Write-Host '  [OK] Defender 实时防护已经是关闭/被动状态' -ForegroundColor Green; Write-Host '       Defender real-time protection is already off or passive' -ForegroundColor DarkGray
} elseif ($__fdTamper) {
    Write-Host '  防篡改保护已开启, 脚本无法直接修改此设置' -ForegroundColor Yellow; Write-Host '  Tamper Protection is on - a script cannot change this setting' -ForegroundColor DarkGray
    Write-Host '  正在打开 Windows 安全中心, 请手动关一次(一次性操作)...' -ForegroundColor Cyan; Write-Host '  Opening Windows Security - please turn it off once by hand (one-time)...' -ForegroundColor DarkGray
    try { Start-Process 'windowsdefender://threatsettings/' } catch { try { Start-Process 'ms-settings:windowsdefender' } catch {} }
    Write-Host '  在打开的窗口里关闭"防篡改保护", 然后回到这里按 Enter 继续' -ForegroundColor Yellow; Write-Host '  In the window that opens, turn off Tamper Protection, then come back and press Enter' -ForegroundColor DarkGray
    try { [void](Read-Host '  关闭后按 Enter 继续, 或直接按 Enter 跳过  /  Press Enter when done, or Enter to skip') } catch {}
    $__fdTamperNow = $__fdTamper
    try { $__fdTamperNow = [bool](Get-MpComputerStatus -ErrorAction Stop).IsTamperProtected } catch {}
    if (-not $__fdTamperNow) { Disable-RealtimeAndPolicy }
    else {
        Write-Host '  [SKIP] 防篡改保护仍开启, 实时防护保持原状' -ForegroundColor Yellow; Write-Host '       Tamper Protection still on - real-time protection left as is' -ForegroundColor DarkGray
        Write-Host '  (下面的排除项不受此影响, 仍会正常添加)' -ForegroundColor DarkGray; Write-Host '  (The folder exclusions below are unaffected and still get added)' -ForegroundColor DarkGray
    }
} else {
    Disable-RealtimeAndPolicy
}
Write-Host '  正在添加文件夹排除项...' -ForegroundColor DarkGray; Write-Host '  Adding folder exclusions...' -ForegroundColor DarkGray
foreach ($__fdP in $__fdExclusions) {
    try {
        Add-MpPreference -ExclusionPath $__fdP -ErrorAction Stop
        Write-Host ('  [OK] 已添加排除项: ' + $__fdP) -ForegroundColor Green; Write-Host ('       Exclusion added: ' + $__fdP) -ForegroundColor DarkGray
    } catch {
        Write-Host ('  [WARN] 排除项未能添加: ' + $__fdP) -ForegroundColor Yellow; Write-Host ('       Could not add exclusion: ' + $__fdP) -ForegroundColor DarkGray
        Write-AkHint ('原因: ' + $_.Exception.Message)
    }
}

Write-AkStepTitle '[2/3] 下载并安装 AutoKit' -En '      Download and install AutoKit'
Write-Host '  正在连接 Google Drive...' -ForegroundColor DarkGray; Write-Host '  Connecting to Google Drive...' -ForegroundColor DarkGray

$accessToken = $null
try {
    $cr = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($__credsB64)) | ConvertFrom-Json)
    $cr = if ($cr.installed) { $cr.installed } elseif ($cr.web) { $cr.web } else { $cr }
    $tok = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($__tokenB64)) | ConvertFrom-Json)
    if (-not $tok.refresh_token) { throw '内嵌令牌缺 refresh_token' }
    $tokenUri = if ($cr.token_uri) { [string]$cr.token_uri } else { 'https://oauth2.googleapis.com/token' }
    $resp = Invoke-RestMethod -Uri $tokenUri -Method POST -ContentType 'application/x-www-form-urlencoded' -Body @{
        client_id = [string]$cr.client_id; client_secret = [string]$cr.client_secret
        refresh_token = [string]$tok.refresh_token; grant_type = 'refresh_token'
    }
    $accessToken = [string]$resp.access_token
    if (-not $accessToken) { throw '响应中没有 access_token' }
} catch {
    Write-Host ('  [ERROR] 无法获取 Drive 访问令牌: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

$folderId = '1KXySLX8-7E2nawEIBPTdLzBsmdg6cxbT'
Write-Host '  正在查找最新版本...' -ForegroundColor DarkGray; Write-Host '  Looking for the latest version...' -ForegroundColor DarkGray
$items = @()
try {
    $headers = @{ Authorization = "Bearer $accessToken" }
    $pageToken = $null
    do {
        $url = "https://www.googleapis.com/drive/v3/files?q='$folderId'+in+parents+and+trashed%3Dfalse&fields=nextPageToken,files(id,name,size,md5Checksum)&pageSize=1000&supportsAllDrives=true&includeItemsFromAllDrives=true"
        if ($pageToken) { $url += "&pageToken=$pageToken" }
        $resp2 = Invoke-RestMethod -Uri $url -Headers $headers
        if ($resp2.files) { $items += $resp2.files }
        $pageToken = $resp2.nextPageToken
    } while ($pageToken)
} catch {
    Write-Host ('  [ERROR] 无法列出更新文件夹: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

$best = $null; $bestDt = [datetime]::MinValue; $bestV = 0
foreach ($it in $items) {
    $n = [string]$it.name
    if ($n -notmatch '(?i)^AutoKit_(\d{1,2}[A-Za-z]{3})(?:-V(\d{2}))?\.(akx|zip|exe)$') { continue }
    $dStr = $Matches[1]; $vNum = if ($Matches[2]) { [int]$Matches[2] } else { 1 }
    $dm = [regex]::Match($dStr, '^(\d{1,2})([A-Za-z]{3})$')
    if (-not $dm.Success) { continue }
    $d = [datetime]::MinValue
    try { $d = [datetime]::ParseExact($dm.Groups[1].Value.PadLeft(2, '0') + $dm.Groups[2].Value, 'ddMMM', [Globalization.CultureInfo]::InvariantCulture) } catch { continue }
    if ($d -gt $bestDt -or ($d -eq $bestDt -and $vNum -gt $bestV)) { $bestDt = $d; $bestV = $vNum; $best = $it }
}
if (-not $best) {
    Write-Host '  [ERROR] 更新文件夹里没有找到 AutoKit_*.akx 文件' -ForegroundColor Red; Write-Host '        No AutoKit_*.akx file found in the update folder' -ForegroundColor DarkGray
    exit 1
}
# 友好标签(去掉内部 .akx 后缀/邮件命名, 只留日期+修订号, 如 "23JUL-V08")
$__remoteTag = $bestDt.ToString('ddMMM', [Globalization.CultureInfo]::InvariantCulture).ToUpper() + '-V' + $bestV.ToString('00')
Write-Host ('  云端最新版本: ' + $__remoteTag) -ForegroundColor Green; Write-Host ('  Latest version in the cloud: ' + $__remoteTag) -ForegroundColor DarkGray

# 2026-07-24: 装机根 C:\AutoKit\ 现按角色分 Client/Logs/Download 三夹(同源码树 AutoKit\Client\ 命名呼应),
# exe 落 C:\AutoKit\Client\ 而不是裸根, 给 Logs\/Download\ 让位, 不再挤在同一层。
$installDir = 'C:\AutoKit\Client'
# 2026-07-23d 改正: 装机文件名必须带日期版本号(跟全项目 AutoKit_DDMMM-Vnn.exe 命名惯例一致), 不能用无版本
# 的固定名 "AutoKit.exe" —— exe 自身的"检查更新"逻辑靠正则 -V(\d{2})\.exe$ 从【自己进程的文件名】解析
# 当前版本号(Opt.Theme.ps1 updCheckWork), 装成无版本的固定名会让这个正则匹配不到, 版本号退回默认 0,
# 于是刚装好的、其实已经是当天最新的这份, 一开机就被自己的更新检查误判成"有新版本"要求再更新一次
# (用户反馈的"多余的二次更新"正是这个根因)。改回带版本号命名后: ①判断"是否已是最新"直接看目标文件名
# 存不存在即可(文件名本身就是版本号, 不再需要额外的旁路标记文件/逐字节比对, 流程更简), ②exe 自带的
# 更新检查天然能正确识别自己的版本, 不会再有装完就提示"有新版本"的假警报。
$installExe = Join-Path $installDir ('AutoKit_' + $__remoteTag + '.exe')

if (Test-Path -LiteralPath $installExe) {
    Write-Host ('  当前已是最新版本 (' + $__remoteTag + '), 无需下载。') -ForegroundColor Green; Write-Host '  Already up to date - nothing to download.' -ForegroundColor DarkGray
} else {
    $tmpDl = Join-Path $env:TEMP ('AutoKit_install_' + [Guid]::NewGuid().ToString('N') + '.tmp')
    Write-Host '  正在下载...' -ForegroundColor DarkGray; Write-Host '  Downloading...' -ForegroundColor DarkGray
    try {
        Invoke-WebRequest -Uri ('https://www.googleapis.com/drive/v3/files/' + [string]$best.id + '?alt=media&supportsAllDrives=true') -Headers $headers -OutFile $tmpDl -UseBasicParsing
    } catch {
        Write-Host ('  [ERROR] 下载失败: ' + $_.Exception.Message) -ForegroundColor Red
        exit 1
    }

    Write-Host '  正在解密...' -ForegroundColor DarkGray; Write-Host '  Decrypting...' -ForegroundColor DarkGray
    # ⚠ 这是 Unprotect-AkUpdatePayload 的【第 3 份内联复制】。不能改成调那个函数: 本段会被写进
    #   AutoKit_Starter.CMD 分发给全新机器, 那台机器上还不存在 AutoDownload.ps1。
    #   口令/盐值/迭代次数(10000)/AES 参数必须与 AutoKit\Client\Source\AutoDownload\AutoDownload.ps1 的
    #   Protect/Unprotect-AkUpdatePayload 逐字一致 —— 换口令要同时改三处, 那边的注释里有完整清单。
    $exeBytes = $null
    try {
        $encBytes = [IO.File]::ReadAllBytes($tmpDl)
        $__pw = 'AutoKit-Update-2026'
        $__salt = [byte[]](1..16 | ForEach-Object { 0xA5 })
        $aes = [Security.Cryptography.Aes]::Create(); $aes.KeySize = 256
        $kdf = New-Object Security.Cryptography.Rfc2898DeriveBytes($__pw, $__salt, 10000)
        $aes.Key = $kdf.GetBytes(32); $aes.IV = $kdf.GetBytes(16)
        $dec = $aes.CreateDecryptor()
        $ms = New-Object IO.MemoryStream(, $encBytes)
        $cs = New-Object Security.Cryptography.CryptoStream($ms, $dec, [Security.Cryptography.CryptoStreamMode]::Read)
        $oms = New-Object IO.MemoryStream
        $cs.CopyTo($oms)
        $exeBytes = $oms.ToArray()
    } catch {
        Write-Host ('  [ERROR] 解密失败: ' + $_.Exception.Message) -ForegroundColor Red
        Remove-Item -LiteralPath $tmpDl -Force -EA SilentlyContinue
        exit 1
    }
    Remove-Item -LiteralPath $tmpDl -Force -EA SilentlyContinue
    if (-not $exeBytes -or $exeBytes.Length -lt 1024) {
        Write-Host '  [ERROR] 解密结果异常(空或过小)' -ForegroundColor Red; Write-Host '        Decrypted output looks wrong (empty or too small)' -ForegroundColor DarkGray
        exit 1
    }

    try {
        if (-not (Test-Path -LiteralPath $installDir)) { New-Item -ItemType Directory -Force -Path $installDir | Out-Null }
        [IO.File]::WriteAllBytes($installExe, $exeBytes)
        # 只留最新这份(同 Build.CMD 的"只留最新 exe"惯例), 清掉本机之前装的旧版本 AutoKit_*.exe
        Get-ChildItem -LiteralPath $installDir -Filter 'AutoKit_*.exe' -File -EA SilentlyContinue |
            Where-Object { $_.FullName -ne $installExe } | Remove-Item -Force -EA SilentlyContinue
        # 一次性迁移清理: 早期版本(无日期号固定名 "AutoKit.exe" + 旁路标记文件)残留, 顺手清掉
        foreach ($__legacy in @('AutoKit.exe', '.installed-version.txt')) {
            $__lp = Join-Path $installDir $__legacy
            if (Test-Path -LiteralPath $__lp) { Remove-Item -LiteralPath $__lp -Force -EA SilentlyContinue }
        }
        # 一次性迁移清理(2026-07-24 Client/Logs/Download 三分前的老装机): 旧版本直接装在 C:\AutoKit\ 裸根下的
        # AutoKit_*.exe/AutoKit.exe, 现在都该在 C:\AutoKit\Client\ 里了, 顺手清掉裸根残留(不碰 Logs\/Download\)。
        $__oldRoot = Split-Path -Parent $installDir
        if ($__oldRoot -and (Test-Path -LiteralPath $__oldRoot)) {
            Get-ChildItem -LiteralPath $__oldRoot -Filter 'AutoKit_*.exe' -File -EA SilentlyContinue | Remove-Item -Force -EA SilentlyContinue
            $__oldLegacy = Join-Path $__oldRoot 'AutoKit.exe'
            if (Test-Path -LiteralPath $__oldLegacy) { Remove-Item -LiteralPath $__oldLegacy -Force -EA SilentlyContinue }
        }
    } catch {
        Write-Host ('  [ERROR] 写入 ' + $installExe + ' 失败: ' + $_.Exception.Message) -ForegroundColor Red
        exit 1
    }
    Write-Host ('  发现新版本 (' + $__remoteTag + '), 已安装到: ' + $installExe) -ForegroundColor Green; Write-Host ('  New version installed to: ' + $installExe) -ForegroundColor DarkGray
}

Write-AkStepTitle '[3/3] 收尾' -En '      Finishing up'
Write-Host '  正在创建桌面快捷方式...' -ForegroundColor DarkGray; Write-Host '  Creating desktop shortcut...' -ForegroundColor DarkGray
try {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktop 'AutoKit.lnk'
    if (Test-Path -LiteralPath $shortcutPath) { Remove-Item -LiteralPath $shortcutPath -Force -EA SilentlyContinue }
    $wsh = New-Object -ComObject WScript.Shell
    $sc = $wsh.CreateShortcut($shortcutPath)
    $sc.TargetPath = $installExe
    $sc.WorkingDirectory = $installDir
    $sc.Description = 'AutoKit - IT Self-Service Tool'
    $sc.IconLocation = $installExe + ',0'
    $sc.WindowStyle = 1
    $sc.Save()
    Write-Host ('  [OK] 快捷方式已创建: ' + $shortcutPath) -ForegroundColor Green; Write-Host ('       Shortcut created: ' + $shortcutPath) -ForegroundColor DarkGray
} catch {
    Write-Host '  [WARN] 桌面快捷方式没能创建(不影响安装, 可从 C:\AutoKit 直接运行)' -ForegroundColor Yellow; Write-Host '       Could not create the shortcut - install is fine, run it from C:\AutoKit' -ForegroundColor DarkGray
    Write-AkHint ('原因: ' + $_.Exception.Message)
}

Write-AkBox '安装完成! 正在启动 AutoKit' 'Green' -En 'Done! Starting AutoKit'
Start-Process -FilePath $installExe

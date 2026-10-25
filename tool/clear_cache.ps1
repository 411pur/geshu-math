<#
  格数至理 - 缓存清理
  用法：
    tool\clear_cache.ps1             # 交互式：询问是否关浏览器 / 是否重新启动
    tool\clear_cache.ps1 -Yes        # 不询问，直接清理
    tool\clear_cache.ps1 -NoRestart  # 清理后不提示重启
    tool\clear_cache.ps1 -DryRun     # 只列出将清理的内容，不删除
  说明：错题本、成绩、画像等数据存在浏览器 localStorage，本脚本不会清理。
#>
param(
  [switch]$Yes,
  [switch]$NoRestart,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

function Write-Step([string]$Message) { Write-Host "[*] $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host "    $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "    $Message" -ForegroundColor Yellow }
function Write-Banner {
  Write-Host ''
  Write-Host '  ============================================' -ForegroundColor DarkCyan
  Write-Host '    格数至理 · 缓存清理' -ForegroundColor White
  Write-Host '  ============================================' -ForegroundColor DarkCyan
  Write-Host ''
}

function Get-DirectorySize([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return 0 }
  $sum = 0
  Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $sum += $_.Length }
  return $sum
}

function Format-Size([double]$Bytes) {
  if ($Bytes -lt 1KB) { return "$([math]::Round($Bytes)) B" }
  if ($Bytes -lt 1MB) { return "$([math]::Round($Bytes / 1KB, 1)) KB" }
  if ($Bytes -lt 1GB) { return "$([math]::Round($Bytes / 1MB, 1)) MB" }
  return "$([math]::Round($Bytes / 1GB, 2)) GB"
}

function Remove-Tree([string]$Path, [string]$Label) {
  if (-not (Test-Path -LiteralPath $Path)) {
    Write-Ok "$Label：不存在，跳过"
    return
  }
  $size = Get-DirectorySize $Path
  if ($DryRun) {
    Write-Ok "$Label：将删除 $(Format-Size $size)"
    return
  }
  try {
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    Write-Ok "$Label：已删除 $(Format-Size $size)"
  } catch {
    Write-Warn "$Label：部分文件被占用，删除未完成（$($_.Exception.Message)）"
  }
}

function Clear-FolderContents([string]$Path, [string]$Label) {
  if (-not (Test-Path -LiteralPath $Path)) { return 0 }
  $size = Get-DirectorySize $Path
  if ($DryRun) {
    Write-Ok "$Label：将清空 $(Format-Size $size)"
    return $size
  }
  $failed = 0
  Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
    try {
      Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
    } catch {
      $failed++
    }
  }
  if ($failed -gt 0) {
    Write-Warn "$Label：清空 $(Format-Size $size)，$failed 项被占用"
  } else {
    Write-Ok "$Label：已清空 $(Format-Size $size)"
  }
  return $size
}

$browsers = @(
  [pscustomobject]@{ Name = 'Edge'; Process = 'msedge'; Root = (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data') },
  [pscustomobject]@{ Name = 'Chrome'; Process = 'chrome'; Root = (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data') }
)

Write-Banner
if ($DryRun) { Write-Warn '演练模式：只统计，不删除任何文件。' }

# ── 1. 项目构建缓存 ────────────────────────────────────────────
Write-Step '清理项目构建缓存'
$projectTargets = @(
  @{ Path = (Join-Path $projectRoot 'build'); Label = 'build（Web 产物与日志）' },
  @{ Path = (Join-Path $projectRoot '.dart_tool'); Label = '.dart_tool（依赖与增量编译）' },
  @{ Path = (Join-Path $projectRoot '.flutter-plugins-dependencies'); Label = '.flutter-plugins-dependencies' },
  @{ Path = (Join-Path $projectRoot 'lesson_engine\node_modules'); Label = 'lesson_engine/node_modules（下次启动自动重装）' }
)
foreach ($target in $projectTargets) {
  Remove-Tree -Path $target.Path -Label $target.Label
}
Remove-Tree -Path (Join-Path $projectRoot 'windows\flutter\ephemeral') -Label 'windows/flutter/ephemeral（桌面构建中间产物）'

# ── 2. 浏览器缓存 ──────────────────────────────────────────────
$browserRoots = $browsers | Where-Object { Test-Path -LiteralPath $_.Root }
if (-not $browserRoots) {
  Write-Step '未找到 Chrome / Edge 用户数据，跳过浏览器缓存'
} else {
  Write-Step '清理浏览器缓存（Service Worker + HTTP 缓存）'

  $shouldClose = $false
  if ($DryRun) {
    $shouldClose = $true
  } elseif ($Yes) {
    $shouldClose = $true
  } else {
    $answer = Read-Host '  需要先关闭 Chrome / Edge（未保存的标签页会丢失）。继续？[y/N]'
    $shouldClose = $answer -match '^(y|yes)$'
  }

  if (-not $shouldClose) {
    Write-Warn '已跳过浏览器缓存清理（项目缓存仍会清理）'
  } else {
    if (-not $DryRun) {
      foreach ($browser in $browserRoots) {
        $running = Get-Process -Name $browser.Process -ErrorAction SilentlyContinue
        if ($running) {
          Write-Ok "关闭 $($browser.Name)（$($running.Count) 个进程）"
          $running | Stop-Process -Force -ErrorAction SilentlyContinue
        }
      }
      Start-Sleep -Milliseconds 800
    }

    foreach ($browser in $browserRoots) {
      $profiles = Get-ChildItem -LiteralPath $browser.Root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' }
      foreach ($profile in $profiles) {
        Clear-FolderContents -Path (Join-Path $profile.FullName 'Service Worker\CacheStorage') -Label "$($browser.Name)/$($profile.Name) Service Worker" | Out-Null
        Clear-FolderContents -Path (Join-Path $profile.FullName 'Cache') -Label "$($browser.Name)/$($profile.Name) HTTP 缓存" | Out-Null
        Clear-FolderContents -Path (Join-Path $profile.FullName 'Code Cache') -Label "$($browser.Name)/$($profile.Name) 代码缓存" | Out-Null
      }
    }
  }
}

Write-Host ''
Write-Host '  提示：错题本、成绩、学生画像保存在浏览器 localStorage，本次未清理。' -ForegroundColor DarkGray
Write-Host '  如需彻底重置应用数据：打开页面 → F12 → Application → Local Storage，' -ForegroundColor DarkGray
Write-Host '  删除 wrong_questions / exam_records / exam_details / geshu_math_* 等键。' -ForegroundColor DarkGray
Write-Host ''

if ($DryRun) {
  Write-Step '演练结束，未做任何修改。'
  exit 0
}

Write-Ok '缓存清理完成'

# ── 3. 可选：重新启动 ──────────────────────────────────────────
if ($NoRestart) { exit 0 }

if ($Yes) {
  $restart = $true
} else {
  $answer = Read-Host '  是否立即启动项目？[Y/n]'
  $restart = $answer -notmatch '^(n|no)$'
}

if ($restart) {
  $launcher = Join-Path $projectRoot '启动项目.bat'
  if (Test-Path -LiteralPath $launcher) {
    Start-Process -FilePath $launcher -WorkingDirectory $projectRoot
  } else {
    Write-Warn "未找到 $launcher，请手动双击启动。"
  }
}

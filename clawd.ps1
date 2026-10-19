# Clawd floating pet: a borderless, always-on-top window that mirrors Claude's state.
# The clawd-pet mod writes "<state>`t<text>" to state.txt; this window polls it.
# States: idle, working, done (idle and done fall asleep after a while). Drag to move, click to jump back to Claude, right-click to hide.
# Hovering shows the text in a pixel bubble; done pops it up on its own.
param([string]$StateFile = "$PSScriptRoot\state.txt", [int]$SleepAfter = 300)

$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Global\ClawdPetWindow', [ref]$created)
if (-not $created) { exit 0 }

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ClawdWin {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct PT { public int X; public int Y; }
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out PT p);
}
'@

$U = 5          # one Clawd pixel
$BP = 3          # one bubble pixel
$W = 200; $H = 120
$bc = [Windows.Media.BrushConverter]::new()
$orange = $bc.ConvertFrom('#D97757')
$shade = $bc.ConvertFrom('#A9583F')
$paper = $bc.ConvertFrom('#FFF8F0')
$ink = [Windows.Media.Brushes]::Black

function Add-Rect($canvas, $x, $y, $w, $h, $brush, $unit) {
  $r = New-Object Windows.Shapes.Rectangle
  $r.Width = $w * $unit; $r.Height = $h * $unit; $r.Fill = $brush
  $r.SnapsToDevicePixels = $true
  [Windows.Controls.Canvas]::SetLeft($r, $x * $unit); [Windows.Controls.Canvas]::SetTop($r, $y * $unit)
  [void]$canvas.Children.Add($r)
  $r
}

$win = New-Object Windows.Window
$win.WindowStyle = 'None'; $win.AllowsTransparency = $true
$win.Background = [Windows.Media.Brushes]::Transparent
$win.Topmost = $true; $win.ShowInTaskbar = $false; $win.ResizeMode = 'NoResize'
$win.Width = $W; $win.Height = $H
$area = [Windows.SystemParameters]::WorkArea
$win.Left = $area.Right - $W - 16; $win.Top = $area.Bottom - $H - 4

$root = New-Object Windows.Controls.Canvas
$root.Background = $null   # empty space clicks through to the window below
$win.Content = $root

# Clawd: 14 x 8 pixels, centered at the bottom
$petX = ($W - 14 * $U) / 2; $petY = $H - 8 * $U - 4
$pet = New-Object Windows.Controls.Canvas
$pet.Width = 14 * $U; $pet.Height = 8 * $U
$pet.Background = [Windows.Media.Brushes]::Transparent
[Windows.Controls.Canvas]::SetLeft($pet, $petX); [Windows.Controls.Canvas]::SetTop($pet, $petY)
$petMove = [Windows.Media.TranslateTransform]::new()
$petSquash = [Windows.Media.ScaleTransform]::new(1, 1, 7 * $U, 8 * $U)
$petTg = [Windows.Media.TransformGroup]::new()
$petTg.Children.Add($petSquash); $petTg.Children.Add($petMove)
$pet.RenderTransform = $petTg
[void]$root.Children.Add($pet)

$upper = New-Object Windows.Controls.Canvas
$upperMove = [Windows.Media.TranslateTransform]::new()
$upperTilt = [Windows.Media.RotateTransform]::new(0, 7 * $U, 3 * $U)
$tg = [Windows.Media.TransformGroup]::new()
$tg.Children.Add($upperTilt); $tg.Children.Add($upperMove)
$upper.RenderTransform = $tg
[void]$pet.Children.Add($upper)

[void](Add-Rect $upper 2 0 10 6 $orange $U)
$armL = Add-Rect $upper 0 2 2 2 $orange $U
$armR = Add-Rect $upper 12 2 2 2 $orange $U
foreach ($a in $armL, $armR) { $a.RenderTransform = [Windows.Media.TranslateTransform]::new() }
$eyeL = Add-Rect $upper 4 1 1 2 $ink $U
$eyeR = Add-Rect $upper 9 1 1 2 $ink $U
foreach ($e in $eyeL, $eyeR) { $e.RenderTransformOrigin = '0.5,0.5'; $e.RenderTransform = [Windows.Media.ScaleTransform]::new(1, 1) }

# Happy "^ ^" eyes
$happy = @()
foreach ($cx in 4.5, 9.5) {
  $p = New-Object Windows.Shapes.Polyline
  $p.Points = [Windows.Media.PointCollection]::Parse(("{0},{1} {2},{3} {4},{5}" -f (($cx - 0.8) * $U), (2.4 * $U), ($cx * $U), (1.3 * $U), (($cx + 0.8) * $U), (2.4 * $U)))
  $p.Stroke = $ink; $p.StrokeThickness = 2; $p.StrokeLineJoin = 'Round'; $p.StrokeStartLineCap = 'Round'; $p.StrokeEndLineCap = 'Round'
  $p.Visibility = 'Hidden'
  [void]$upper.Children.Add($p); $happy += $p
}

# Expression effects, drawn in the pet's own space so they move with it
$fxBrush = $bc.ConvertFrom('#8E96B8')
function New-Fx($text, $size, $brush) {
  $tb = New-Object Windows.Controls.TextBlock
  $tb.Text = $text; $tb.FontSize = $size; $tb.FontWeight = 'Bold'; $tb.FontFamily = 'Consolas'
  $tb.Foreground = $brush; $tb.Opacity = 0; $tb.IsHitTestVisible = $false
  [void]$pet.Children.Add($tb)
  $tb
}
$zs = @((New-Fx 'z' 9 $fxBrush), (New-Fx 'z' 11 $fxBrush), (New-Fx 'Z' 13 $fxBrush))
$question = New-Fx '?' 15 $orange
$snot = New-Object Windows.Shapes.Ellipse
$snot.Fill = $bc.ConvertFrom('#CFE9FF'); $snot.Stroke = $bc.ConvertFrom('#9CCBEF'); $snot.StrokeThickness = 1
$snot.IsHitTestVisible = $false; $snot.Opacity = 0
[void]$upper.Children.Add($snot)
$sparks = @((New-Fx ([string][char]0x2726) 10 $bc.ConvertFrom('#F2B84B')), (New-Fx ([string][char]0x2726) 8 $orange), (New-Fx ([string][char]0x2726) 9 $bc.ConvertFrom('#F2B84B')))
$sweat = New-Object Windows.Controls.Canvas
$sweat.IsHitTestVisible = $false; $sweat.Opacity = 0
$drop = $bc.ConvertFrom('#7EC8F0')
[void](Add-Rect $sweat 0.5 0 1 1 $drop 2); [void](Add-Rect $sweat 0 1 2 2 $drop 2)
[void]$upper.Children.Add($sweat)
function Place($el, $x, $y, $o) { [Windows.Controls.Canvas]::SetLeft($el, $x); [Windows.Controls.Canvas]::SetTop($el, $y); $el.Opacity = [Math]::Max(0, [Math]::Min(1, $o)) }

$legs = @()
foreach ($lx in 3, 5, 8, 10) { $leg = Add-Rect $pet $lx 6 1 2 $orange $U; $leg.RenderTransform = [Windows.Media.TranslateTransform]::new(); $legs += $leg }

# Pixel speech bubble: stepped corners, a hard drop shadow and a stepped tail
$bubble = New-Object Windows.Controls.Canvas
$bubble.IsHitTestVisible = $false
$bubbleScale = [Windows.Media.ScaleTransform]::new(1, 1)
$bubble.RenderTransform = $bubbleScale
$bubble.Visibility = 'Hidden'
[void]$root.Children.Add($bubble)

function Build-Bubble($text) {
  $bubble.Children.Clear()
  $tb = New-Object Windows.Controls.TextBlock
  $tb.Text = $text; $tb.FontSize = 12; $tb.FontWeight = 'Bold'
  $tb.FontFamily = 'Microsoft YaHei UI'; $tb.Foreground = $bc.ConvertFrom('#3D3929')
  [Windows.Media.TextOptions]::SetTextRenderingMode($tb, 'Aliased')
  $tb.Measure([Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
  $tw = $tb.DesiredSize.Width; $th = $tb.DesiredSize.Height
  $cw = [Math]::Ceiling(($tw + 14) / $BP) + 2
  $ch = [Math]::Ceiling(($th + 6) / $BP) + 2
  $c = [Math]::Floor($cw / 2) - 1

  # shadow
  [void](Add-Rect $bubble 3 $ch ($cw - 2) 1 $shade $BP)
  [void](Add-Rect $bubble $cw 3 1 ($ch - 2) $shade $BP)
  [void](Add-Rect $bubble ($cw - 1) ($ch - 1) 1 1 $shade $BP)
  # fill
  [void](Add-Rect $bubble 2 1 ($cw - 4) ($ch - 2) $paper $BP)
  [void](Add-Rect $bubble 1 2 ($cw - 2) ($ch - 4) $paper $BP)
  # border with notched corners
  [void](Add-Rect $bubble 2 0 ($cw - 4) 1 $orange $BP)
  [void](Add-Rect $bubble 2 ($ch - 1) ($cw - 4) 1 $orange $BP)
  [void](Add-Rect $bubble 0 2 1 ($ch - 4) $orange $BP)
  [void](Add-Rect $bubble ($cw - 1) 2 1 ($ch - 4) $orange $BP)
  foreach ($xy in @(1, 1), @(($cw - 2), 1), @(1, ($ch - 2)), @(($cw - 2), ($ch - 2))) { [void](Add-Rect $bubble $xy[0] $xy[1] 1 1 $orange $BP) }
  # tail
  [void](Add-Rect $bubble ($c + 1) ($ch - 1) 1 1 $paper $BP)
  [void](Add-Rect $bubble $c $ch 1 1 $orange $BP)
  [void](Add-Rect $bubble ($c + 1) $ch 1 1 $paper $BP)
  [void](Add-Rect $bubble ($c + 2) $ch 1 1 $orange $BP)
  [void](Add-Rect $bubble ($c + 1) ($ch + 1) 1 1 $orange $BP)
  [void](Add-Rect $bubble ($c + 2) ($ch + 1) 1 1 $shade $BP)

  [Windows.Controls.Canvas]::SetLeft($tb, ($cw * $BP - $tw) / 2)
  [Windows.Controls.Canvas]::SetTop($tb, ($ch * $BP - $th) / 2)
  [void]$bubble.Children.Add($tb)

  $bw = ($cw + 1) * $BP; $bh = ($ch + 2) * $BP
  $left = [Math]::Max(0, ($W - $bw) / 2)
  $top = [Math]::Max(0, $petY - $bh - 18)
  [Windows.Controls.Canvas]::SetLeft($bubble, $left); [Windows.Controls.Canvas]::SetTop($bubble, $top)
  $bubbleScale.CenterX = ($c + 1.5) * $BP; $bubbleScale.CenterY = $bh
}

# State
$script:state = 'idle'; $script:text = ''; $script:stamp = $null; $script:t = 0; $script:since = 0
$script:asleep = $false; $script:tuck = 0; $script:readAt = 0; $script:hover = $false; $script:active = 0; $script:wakeAt = -100; $script:shownAt = -1; $script:hideAt = -1; $script:shownText = $null

function Pop([string]$text, [int]$holdFrames) {
  if ($text -ne $script:shownText -or $bubble.Visibility -ne 'Visible') {
    Build-Bubble $text
    $script:shownText = $text
    $script:shownAt = $script:t
  }
  $script:hideAt = if ($holdFrames -lt 0) { -1 } else { $script:t + $holdFrames }
  $bubble.Opacity = 1
  $bubble.Visibility = 'Visible'
}

function Read-State {
  try {
    if (-not (Test-Path $StateFile)) { return }
    $m = (Get-Item $StateFile).LastWriteTimeUtc
    if ($m -eq $script:stamp) { return }
    $script:stamp = $m
    $parts = (Get-Content $StateFile -Raw -Encoding UTF8).Trim() -split "`t", 2
    $new = $parts[0]
    $script:text = if ($parts.Count -gt 1) { $parts[1] } else { '' }
    if ($new -ne $script:state) {
      $script:state = $new; $script:since = $script:t; $script:active = $script:t
      switch ($new) {
        'done' { Pop $script:text 110 }
        default { $script:hideAt = $script:t }
      }
    }
    if ($script:hover -and $script:text) { Pop $script:text -1 }   # hovering keeps the text up
  } catch {}
}

function Frame {
  $script:t = [int]($clock.ElapsedMilliseconds / 50)
  $t = $script:t
  if ($t - $script:readAt -ge 5) { $script:readAt = $t; Read-State }
  # Hover: compare the cursor with the pet itself, every frame
  $c = New-Object ClawdWin+PT
  [void][ClawdWin]::GetCursorPos([ref]$c)
  $local = $pet.PointFromScreen([Windows.Point]::new($c.X, $c.Y))
  $isOver = $local.X -ge -4 -and $local.X -le (14 * $U + 4) -and $local.Y -ge -4 -and $local.Y -le (8 * $U + 4)
  $isAsleep = ($script:state -eq 'idle' -or $script:state -eq 'done') -and ($t - $script:active) -gt ($SleepAfter * 20)
  $script:asleep = $isAsleep
  if ($isOver -and -not $script:hover) { if ($isAsleep) { Pop '呼噜…zzZ' -1 } elseif ($script:text) { Pop $script:text -1 } }
  if (-not $isOver -and $script:hover) { $script:hideAt = $t + 10 }
  $script:hover = $isOver

  $s = $script:state; $age = $t - $script:since

  $up = 0; $hop = 0; $tilt = 0; $armDy = 0, 0; $legDx = 0, 0, 0, 0; $isHappy = $false; $blink = $false
  $eyeDx = 0; $eyeScale = 1; $fx = @{}
  if ($isAsleep) { $s = 'sleep' }
  switch ($s) {
    'sleep' {
      $up = [Math]::Sin($t * 0.05) * 0.8
      $armDy = 1, 1
      $eyeScale = 0.15
      $fx.z = $true
    }
    'working' {
      $up = - [Math]::Abs([Math]::Sin($t * 0.3)) * 2
      $armDy = ([Math]::Sin($t * 0.6) * 3), (- [Math]::Sin($t * 0.6) * 3)
      $step = if ([Math]::Floor($t / 4) % 2 -eq 0) { 1.5 } else { -1.5 }
      $legDx = $step, (-$step), $step, (-$step)
      $fx.sweat = $true
    }
    'done' {
      $isHappy = $true
      if ($age -lt 96) {
        # three hops, then settle
        $phase = $age % 32
        if ($phase -lt 14) { $hop = - [Math]::Sin($phase / 14 * [Math]::PI) * 14 }
        $armDy = if ($phase -lt 14) { -4, -4 } else { -1, -1 }
        $fx.spark = $true
      } else {
        $up = [Math]::Sin($t * 0.07) * 1
      }
    }
    default {
      $up = [Math]::Sin($t * 0.07) * 1
      $blink = ($t % 90) -lt 4
      # glance left, then right
      $look = $t % 160
      if ($look -ge 60 -and $look -lt 85) { $eyeDx = -0.6 * $U } elseif ($look -ge 100 -and $look -lt 125) { $eyeDx = 0.6 * $U }
    }
  }

  $sx = 1; $sy = 1
  if ($script:hover -and $s -ne 'sleep') { $isHappy = $true }
  # idle: a little happy wiggle now and then
  if ($s -eq 'idle') { $wg = $t % 220; if ($wg -lt 16) { $tilt = [Math]::Sin($wg / 16 * 4 * [Math]::PI) * 6 } }
  # squash when landing from a hop, stretch in the air
  if ($hop -lt -2) { $sx = 0.92; $sy = 1.1 } elseif ($s -eq 'done' -and $age -lt 96 -and ($age % 32) -ge 14 -and ($age % 32) -lt 18) { $sx = 1.15; $sy = 0.85 }
  $w = $t - $script:wakeAt
  if ($w -lt 14) { $hop = - [Math]::Sin($w / 14 * [Math]::PI) * 10; $eyeScale = 1.35; $armDy = -5, -5; $eyeDx = 0 }

  $goal = if ($s -eq 'sleep') { 1 } else { 0 }
  $script:tuck += ($goal - $script:tuck) * 0.15
  if ([Math]::Abs($goal - $script:tuck) -lt 0.01) { $script:tuck = $goal }
  $k = $script:tuck
  foreach ($leg in $legs) { $leg.Height = 2 * $U * (1 - $k); [Windows.Controls.Canvas]::SetTop($leg, (6 + 2 * $k) * $U) }
  $up += 2 * $U * $k

  $petMove.Y = $hop
  $petSquash.ScaleX = $sx; $petSquash.ScaleY = $sy
  $upperMove.Y = $up
  $upperTilt.Angle = $tilt
  $armL.RenderTransform.Y = $armDy[0]
  $armR.RenderTransform.Y = $armDy[1]
  for ($i = 0; $i -lt 4; $i++) { $legs[$i].RenderTransform.X = $legDx[$i] }
  if ($blink) { $eyeScale = 0.15 }
  [Windows.Controls.Canvas]::SetLeft($eyeL, 4 * $U + $eyeDx); [Windows.Controls.Canvas]::SetLeft($eyeR, 9 * $U + $eyeDx)
  foreach ($e in $eyeL, $eyeR) {
    $e.RenderTransform.ScaleY = $eyeScale; $e.RenderTransform.ScaleX = if ($eyeScale -gt 1) { 1.2 } else { 1 }
    $e.Visibility = if ($isHappy) { 'Hidden' } else { 'Visible' }
  }
  foreach ($p in $happy) { $p.Visibility = if ($isHappy) { 'Visible' } else { 'Hidden' } }

  # Effects
  for ($i = 0; $i -lt 3; $i++) {
    $ph = (($t + $i * 22) % 66) / 66
    Place $zs[$i] (12 * $U + $ph * 16 + $i * 2) (-4 - $ph * 26) ($(if ($fx.z) { [Math]::Sin($ph * [Math]::PI) } else { 0 }))
  }
  $sn = 3 + ([Math]::Sin($t * 0.05) + 1) * 3.5
  $snot.Width = $sn; $snot.Height = $sn
  Place $snot (7.6 * $U) (3.6 * $U - $sn / 2) ($(if ($fx.z) { 0.9 } else { 0 }))
  Place $question (14 * $U - 2) (-3 * $U - 6 + [Math]::Sin($t * 0.2) * 2) ($(if ($fx.q) { 1 } else { 0 }))
  $sw = $t % 36
  Place $sweat (12 * $U) (-2 + $sw * 0.35) ($(if ($fx.sweat -and $sw -lt 24) { 1 - $sw / 24 } else { 0 }))
  $spots = @(@(-10, -8), @((14 * $U + 2), -4), @((6 * $U), -18))
  for ($i = 0; $i -lt 3; $i++) {
    Place $sparks[$i] $spots[$i][0] $spots[$i][1] ($(if ($fx.spark) { [Math]::Abs([Math]::Sin($t * 0.25 + $i * 2)) } else { 0 }))
  }

  # Bubble: pop in (overshoot), hold, fade out
  if ($bubble.Visibility -eq 'Visible') {
    $k = $t - $script:shownAt
    $sc = if ($k -lt 4) { 0.4 + $k * 0.2 } elseif ($k -lt 7) { 1.2 - ($k - 4) * 0.0667 } else { 1 }
    $bubbleScale.ScaleX = $sc; $bubbleScale.ScaleY = $sc
    if ($script:hideAt -ge 0 -and $t -ge $script:hideAt) {
      $f = 1 - ($t - $script:hideAt) / 8
      if ($f -le 0) { $bubble.Visibility = 'Hidden'; $script:shownText = $null } else { $bubble.Opacity = $f }
    }
  }
}

function Show-Claude {
  $p = Get-Process -Name claude -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if (-not $p) { return }
  if ([ClawdWin]::IsIconic($p.MainWindowHandle)) { [void][ClawdWin]::ShowWindow($p.MainWindowHandle, 9) }
  [void][ClawdWin]::SetForegroundWindow($p.MainWindowHandle)
}

$pet.Add_MouseLeftButtonDown({
  $x = $win.Left; $y = $win.Top
  try { $win.DragMove() } catch {}
  if ([Math]::Abs($win.Left - $x) + [Math]::Abs($win.Top - $y) -lt 3) {
    if ($script:asleep) {
      $script:active = $script:t; $script:wakeAt = $script:t
      Pop '醒啦！' 30
    } else {
      if ($script:state -eq 'done') { $script:hideAt = $script:t }
      Show-Claude
    }
  }
})
$pet.Add_MouseRightButtonUp({ $win.Close() })

$clock = [Diagnostics.Stopwatch]::StartNew()
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(50)
$timer.Add_Tick({ Frame })
$timer.Start()
Read-State
[void]$win.ShowDialog()
$mutex.ReleaseMutex()

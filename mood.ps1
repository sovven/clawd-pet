# Called by Claude Code hooks: sets Clawd's mood and makes sure the floating window is up.
# Hooks pass JSON on stdin with the session id. Clawd keeps a list of sessions that are
# working, and says "done" only when the last one of them finishes.
param([string]$Mood = 'idle')
$says = @{ idle = '摸鱼中～有事叫我'; working = '干活中…'; done = '做好啦！点我回去' }

$session = 'manual'
if ([Console]::IsInputRedirected) {
  try { $session = ([Console]::In.ReadToEnd() | ConvertFrom-Json).session_id } catch {}
  if (-not $session) { $session = 'manual' }
}

$lock = New-Object System.Threading.Mutex($false, 'Global\ClawdPetMood')
[void]$lock.WaitOne(5000)
try {
  $listPath = "$PSScriptRoot\sessions.json"
  $working = @{}
  if (Test-Path $listPath) {
    try { (Get-Content $listPath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $working[$_.Name] = [long]$_.Value } } catch {}
  }
  $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  # forget sessions that started working long ago and never finished (closed, crashed)
  foreach ($id in @($working.Keys)) { if ($now - $working[$id] -gt 3 * 3600) { $working.Remove($id) } }

  switch ($Mood) {
    'working' { $working[$session] = $now }
    'done' { $working.Remove($session) }
  }
  # another session still busy: keep working instead of announcing done or idle
  $shown = if ($working.Count -gt 0) { 'working' } else { $Mood }

  [IO.File]::WriteAllText($listPath, ($working | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
  $statePath = "$PSScriptRoot\state.txt"
  $line = "$shown`t$($says[$shown])"
  $current = if (Test-Path $statePath) { [IO.File]::ReadAllText($statePath).Trim() } else { '' }
  if ($current -ne $line) { [IO.File]::WriteAllText($statePath, $line, [Text.UTF8Encoding]::new($false)) }
} finally {
  $lock.ReleaseMutex()
}

$m = $null
if (-not [Threading.Mutex]::TryOpenExisting('Global\ClawdPetWindow', [ref]$m)) {
  Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSScriptRoot\clawd.ps1`""
} else { $m.Dispose() }

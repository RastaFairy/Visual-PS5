# runtime/server-console.ps1 — consola PS5 (klog/FTP/elfldr). Extraído de server.ps1 en 1.1.59 (dot-sourced: comparte el ámbito $script:).
#requires -Version 5.1

# ===== Panel de consola PS5: klogsrv (TCP 3232), despliegue FTP (puerto configurable, 2121 por defecto) y elfldr (9021) =====
# Todo apunta a la IP que el usuario escribe; el servidor local no expone nada a la red.
$script:PS5HSConsole = @{ KlogClient = $null; KlogHost = ''; KlogPort = 3232; LogLines = [System.Collections.Generic.List[string]]::new() }

function GetPS5HSBackendCapabilities {
  $path = Join-Path $script:Root 'runtime/backend-capabilities.json'
  if (!(Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
  try { return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json) } catch { return $null }
}

function Connect-PS5HSTcpClient([string]$Address,[int]$Port,[int]$TimeoutMs=2500) {
  $client = [System.Net.Sockets.TcpClient]::new()
  try {
    $connect = $client.ConnectAsync($Address, $Port)
    if (-not $connect.Wait($TimeoutMs)) { throw "Sin respuesta en ${Address}:${Port} tras $TimeoutMs ms." }
  } catch {
    try { $client.Close() } catch { }
    throw
  }
  $client.ReceiveTimeout = 1200
  return $client
}

# Conexión persistente al klogsrv: cada sondeo lee lo nuevo y mantiene un buffer
# de las últimas 2000 líneas para que la vista muestre un historial estable.
function Invoke-PS5HSKlogPoll([string]$Address,[int]$Port) {
  $state = $script:PS5HSConsole
  $needsConnect = $true
  try { $needsConnect = ($null -eq $state.KlogClient -or -not $state.KlogClient.Connected -or $state.KlogHost -ne $Address -or $state.KlogPort -ne $Port) } catch { $needsConnect = $true }
  if ($needsConnect) {
    if ($state.KlogClient) { try { $state.KlogClient.Close() } catch { } }
    $state.KlogClient = Connect-PS5HSTcpClient $Address $Port
    $state.KlogHost = $Address
    $state.KlogPort = $Port
  }
  $stream = $state.KlogClient.GetStream()
  $chunks = [System.Collections.Generic.List[byte]]::new()
  $buffer = [byte[]]::new(16384)
  $deadline = [DateTime]::UtcNow.AddMilliseconds(650)
  while ([DateTime]::UtcNow -lt $deadline) {
    $read = 0
    try { if ($stream.DataAvailable) { $read = $stream.Read($buffer, 0, $buffer.Length) } } catch { break }
    if ($read -gt 0) { for ($i = 0; $i -lt $read; $i++) { $chunks.Add($buffer[$i]) } }
    elseif ($read -lt 0) { break }
    else { Start-Sleep -Milliseconds 80 }
  }
  $text = [Text.Encoding]::UTF8.GetString($chunks.ToArray())
  if ($text) {
    foreach ($line in ($text -split "`r?`n")) {
      if ($line.Length -gt 0) { $state.LogLines.Add($line); if ($state.LogLines.Count -gt 2000) { $state.LogLines.RemoveAt(0) } }
    }
  }
  $tailCount = [Math]::Min(400, $state.LogLines.Count)
  $tail = [string[]]::new($tailCount)
  $state.LogLines.CopyTo($state.LogLines.Count - $tailCount, $tail, 0, $tailCount)
  return @{ ok = $true; connected = $true; host = $Address; port = $Port; lines = $tail }
}

function Stop-PS5HSKlog {
  if ($script:PS5HSConsole.KlogClient) { try { $script:PS5HSConsole.KlogClient.Close() } catch { } }
  $script:PS5HSConsole.KlogClient = $null
  return @{ ok = $true; connected = $false }
}

# Despliegue del título por FTP con curl.exe (viene con Windows 10+). ftpsrv de
# ps5-payload-dev crea directorios al vuelo con --ftp-create-dirs; se sube cada
# archivo de la carpeta del título conservando la ruta relativa.
function Invoke-PS5HSFtpDeploy([string]$Address,[string]$User,[string]$Password,[string]$LocalFolder,[string]$RemoteFolder,[int]$Port=2121) {
  $curl = CmdInfo 'curl.exe'; if (!$curl.ok) { $curl = CmdInfo 'curl' }
  if (!$curl.ok) { throw 'curl.exe no está disponible en el PATH de Windows.' }
  if ($Port -lt 1 -or $Port -gt 65535) { throw ('Puerto FTP fuera de rango (1-65535): ' + $Port) }
  if (!(Test-Path -LiteralPath $LocalFolder -PathType Container)) { throw "La carpeta local no existe: $LocalFolder" }
  $files = @(Get-ChildItem -LiteralPath $LocalFolder -Recurse -File | Sort-Object FullName)
  if (!$files.Count) { throw 'La carpeta del título no contiene archivos que desplegar.' }
  $credential = @()
  if ($User) { $credential = @('-u', ("{0}:{1}" -f $User, $Password)) }
  $baseUri = "ftp://${Address}:${Port}/$($RemoteFolder.TrimStart('/').TrimEnd('/'))/"
  $uploaded = [System.Collections.Generic.List[string]]::new()
  foreach ($file in $files) {
    $relative = $file.FullName.Substring((Resolve-Path -LiteralPath $LocalFolder).Path.Length).TrimStart('\','/').Replace('\','/')
    $target = $baseUri + $relative
    $arguments = @('--ftp-create-dirs','--connect-timeout','8','--max-time','900','--silent','--show-error','-T', $file.FullName, $target) + $credential
    $output = & $curl.path @arguments 2>&1 | ForEach-Object { $_.ToString() }
    if ($LASTEXITCODE -ne 0) { throw ("Fallo FTP subiendo {0}: {1}" -f $relative, ($output -join ' ')) }
    $uploaded.Add($relative)
  }
  return @{ ok = $true; uploaded = $uploaded; remote = $baseUri; count = $uploaded.Count }
}

# Envía un ELF al elfldr de etaHEN/kstuff (puerto 9021). Devuelve la respuesta
# textual del loader; un ELF válido lanza el payload directamente.
function Invoke-PS5HSSendElf([string]$Address,[string]$ElfPath) {
  if (!(Test-Path -LiteralPath $ElfPath -PathType Leaf)) { throw "No existe el ELF: $ElfPath" }
  $bytes = [IO.File]::ReadAllBytes($ElfPath)
  if ($bytes.Length -lt 64 -or $bytes[0] -ne 0x7F -or $bytes[1] -ne 0x45 -or $bytes[2] -ne 0x4C -or $bytes[3] -ne 0x46) { throw 'El archivo no es un ELF64 válido (cabecera 0x7F E L F).' }
  $client = Connect-PS5HSTcpClient $Address 9021 4000
  try {
    $stream = $client.GetStream()
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush()
    $response = [Text.Encoding]::ASCII.GetString((Read-PS5HSTcpTail $stream 2500)).Trim()
    return @{ ok = $true; sent = $bytes.Length; response = $response; note = 'El payload queda lanzado por elfldr; los títulos registrados con ShadowMountPlus se lanzan desde la pantalla de inicio.' }
  } finally { try { $client.Close() } catch { } }
}

function Read-PS5HSTcpTail([System.Net.Sockets.NetworkStream]$Stream,[int]$WindowMs) {
  $chunks = [System.Collections.Generic.List[byte]]::new()
  $buffer = [byte[]]::new(4096)
  $deadline = [DateTime]::UtcNow.AddMilliseconds($WindowMs)
  while ([DateTime]::UtcNow -lt $deadline) {
    $read = 0
    try { if ($Stream.DataAvailable) { $read = $Stream.Read($buffer, 0, $buffer.Length) } } catch { break }
    if ($read -gt 0) { for ($i = 0; $i -lt $read; $i++) { $chunks.Add($buffer[$i]) } }
    else { Start-Sleep -Milliseconds 80 }
  }
  return $chunks.ToArray()
}


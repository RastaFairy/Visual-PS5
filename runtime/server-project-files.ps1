# runtime/server-project-files.ps1 — explorador de archivos. Extraído de server.ps1 en 1.1.59 (dot-sourced: comparte el ámbito $script:).
#requires -Version 5.1

# ===== Explorador de archivos de proyecto (solo texto, acotado a <Workspace>\<proyecto>) =====
$script:PS5HSTextExtensions = @('.c','.cpp','.cc','.cxx','.h','.hpp','.hh','.cs','.js','.json','.md','.txt','.yml','.yaml','.xml','.glsl','.vert','.frag','.comp','.bat','.sh','.ps1','.cmake','.in','.ld','.toml','.ini','.cfg','.sql','.html','.css','.mk','.ninja','.proto','')
function Test-PS5HSProjectRelativePath([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Contains('\') -or $Value.Contains(':') -or $Value -match '[\x00-\x1f]' -or $Value.StartsWith('/')) { return $false }
  if ($Value -match '[\?\*"<>|]') { return $false }
  return (@($Value.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count -eq 0)
}
function Resolve-PS5HSProjectScopedPath([string]$ProjectDir,[string]$RelativePath) {
  if (!(Test-PS5HSProjectRelativePath $RelativePath)) { throw ("Ruta de proyecto no segura: " + $RelativePath) }
  $baseFull = [IO.Path]::GetFullPath($ProjectDir)
  $candidate = [IO.Path]::GetFullPath((Join-Path $baseFull ($RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar)))
  if (!$candidate.StartsWith(($baseFull.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)) { throw ("Ruta fuera del proyecto: " + $RelativePath) }
  $null = AssertPS5HSNativePathNoReparsePoints -Path $candidate
  return $candidate
}
function Invoke-PS5HSProjectFileOp($Body) {
  $op = [string]$Body.op
  $project = [IO.Path]::GetFileName([string]$Body.project)
  if (!$project) { return @{ ok = $false; error = 'Falta el proyecto.' } }
  $projectDir = Join-Path $script:Workspace $project
  if (!(Test-Path -LiteralPath $projectDir -PathType Container)) { return @{ ok = $false; error = 'El proyecto no existe en disco.' } }
  try {
    switch ($op) {
      'list' {
        $items = @()
        Get-ChildItem -LiteralPath $projectDir -Recurse -Force | ForEach-Object {
          $relative = $_.FullName.Substring($projectDir.Length).TrimStart('\','/').Replace('\','/')
          if ($relative -match '(^|/)snapshots/') { return }
          $items += @{ path = $relative; dir = [bool]$_.PSIsContainer; size = if ($_.PSIsContainer) { 0 } else { $_.Length }; text = if ($_.PSIsContainer) { $false } else { $script:PS5HSTextExtensions -contains $_.Extension.ToLowerInvariant() } }
        }
        if ($items.Count -gt 2000) { $items = @($items[0..1999]) + @{ path = '(árbol truncado: más de 2000 entradas)'; dir = $false; size = 0; text = $false } }
        return @{ ok = $true; items = $items; root = $project }
      }
      'read' {
        $relative = [string]$Body.path
        $full = Resolve-PS5HSProjectScopedPath $projectDir $relative
        $item = Get-Item -LiteralPath $full -Force
        if ($item.PSIsContainer) { return @{ ok = $false; error = 'La ruta es una carpeta.' } }
        if ($script:PS5HSTextExtensions -notcontains $item.Extension.ToLowerInvariant()) { return @{ ok = $false; error = 'Tipo de archivo no editable en el IDE (binario o no textual).' } }
        if ($item.Length -gt 2MB) { return @{ ok = $false; error = 'El archivo supera 2 MiB; edítalo con una herramienta externa.' } }
        return @{ ok = $true; path = $relative; content = [string](Get-Content -LiteralPath $full -Raw) }
      }
      'write' {
        $relative = [string]$Body.path
        $full = Resolve-PS5HSProjectScopedPath $projectDir $relative
        $item = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
        if ($item -and $item.PSIsContainer) { return @{ ok = $false; error = 'La ruta es una carpeta.' } }
        if ($item -and $script:PS5HSTextExtensions -notcontains $item.Extension.ToLowerInvariant()) { return @{ ok = $false; error = 'Tipo de archivo no editable en el IDE.' } }
        $content = [string]$Body.content
        if ($content.Length -gt 2MB) { return @{ ok = $false; error = 'El contenido supera 2 MiB.' } }
        if (!$item) {
          if ($script:PS5HSTextExtensions -notcontains ([IO.Path]::GetExtension($full).ToLowerInvariant())) { return @{ ok = $false; error = 'Extensión no editable en el IDE.' } }
          $parent = Split-Path -Parent $full
          if (!(Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        }
        WriteUtf8 $full $content
        return @{ ok = $true; path = $relative; size = $content.Length }
      }
      'create' {
        $relative = [string]$Body.path
        $full = Resolve-PS5HSProjectScopedPath $projectDir $relative
        if (Test-Path -LiteralPath $full) { return @{ ok = $false; error = 'La ruta ya existe.' } }
        if ([string]$Body.type -eq 'folder') {
          New-Item -ItemType Directory -Path $full -Force | Out-Null
        } else {
          if ($script:PS5HSTextExtensions -notcontains ([IO.Path]::GetExtension($full).ToLowerInvariant())) { return @{ ok = $false; error = 'Extensión no editable en el IDE; crea el archivo con una herramienta externa.' } }
          $parent = Split-Path -Parent $full
          if (!(Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
          WriteUtf8 $full ''
        }
        return @{ ok = $true; path = $relative }
      }
      'rename' {
        $relative = [string]$Body.path
        $newRelative = [string]$Body.newPath
        if ([string]::IsNullOrWhiteSpace($newRelative)) { return @{ ok = $false; error = 'Falta el nombre nuevo.' } }
        $full = Resolve-PS5HSProjectScopedPath $projectDir $relative
        if (!(Test-Path -LiteralPath $full)) { return @{ ok = $false; error = 'La ruta de origen no existe.' } }
        $newFull = Resolve-PS5HSProjectScopedPath $projectDir $newRelative
        if (Test-Path -LiteralPath $newFull) { return @{ ok = $false; error = 'El destino ya existe.' } }
        $newParent = Split-Path -Parent $newFull
        if (!(Test-Path -LiteralPath $newParent -PathType Container)) { New-Item -ItemType Directory -Path $newParent -Force | Out-Null }
        Move-Item -LiteralPath $full -Destination $newFull -Force
        return @{ ok = $true; path = $newRelative }
      }
      'delete' {
        $relative = [string]$Body.path
        if ([string]::IsNullOrWhiteSpace($relative)) { return @{ ok = $false; error = 'Falta la ruta a eliminar.' } }
        if ($relative -eq 'project.json') { return @{ ok = $false; error = 'project.json contiene el modelo del editor; usa «Cerrar proyecto» o borra el proyecto completo desde Abrir.' } }
        $full = Resolve-PS5HSProjectScopedPath $projectDir $relative
        if (!(Test-Path -LiteralPath $full)) { return @{ ok = $false; error = 'La ruta no existe.' } }
        Remove-Item -LiteralPath $full -Recurse -Force
        return @{ ok = $true; path = $relative }
      }
      default { return @{ ok = $false; error = 'Operación de archivo no reconocida.' } }
    }
  } catch { return @{ ok = $false; error = $_.Exception.Message } }
}
function Invoke-PS5HSProjectFileSearch($Body) {
  $project = [IO.Path]::GetFileName([string]$Body.project)
  $query = [string]$Body.query
  if (!$project) { return @{ ok = $false; error = 'Falta el proyecto.' } }
  if ([string]::IsNullOrWhiteSpace($query) -or $query.Length -gt 200) { return @{ ok = $false; error = 'Consulta de búsqueda vacía o demasiado larga.' } }
  $projectDir = Join-Path $script:Workspace $project
  if (!(Test-Path -LiteralPath $projectDir -PathType Container)) { return @{ ok = $false; error = 'El proyecto no existe en disco.' } }
  $results = @()
  $truncated = $false
  try {
    $files = Get-ChildItem -LiteralPath $projectDir -Recurse -File -Force | Where-Object {
      ($_.FullName -notmatch '\\snapshots\\') -and ($script:PS5HSTextExtensions -contains $_.Extension.ToLowerInvariant()) -and ($_.Length -le 2MB)
    }
    foreach ($file in $files) {
      if ($results.Count -ge 200) { $truncated = $true; break }
      try {
        $lines = [IO.File]::ReadAllLines($file.FullName)
        for ($i = 0; $i -lt $lines.Count; $i++) {
          if ($lines[$i].IndexOf($query, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $results += @{ path = $file.FullName.Substring($projectDir.Length).TrimStart('\','/').Replace('\','/'); line = ($i + 1); text = $lines[$i].Substring(0, [Math]::Min(240, $lines[$i].Length)) }
            if ($results.Count -ge 200) { $truncated = $true; break }
          }
        }
      } catch { }
    }
  } catch { return @{ ok = $false; error = $_.Exception.Message } }
  return @{ ok = $true; results = $results; truncated = $truncated }
}


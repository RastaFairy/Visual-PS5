# runtime/server-model.ps1 — validación del modelo. Extraído de server.ps1 en 1.1.59 (dot-sourced: comparte el ámbito $script:).
#requires -Version 5.1

# Valida el modelo del proyecto en el servidor (el cliente ya valida con project-contracts.js;
# aquí se aplican las invariantes minimas para no confiar ciegamente en el navegador).
# Devuelve $null si el modelo es aceptable o el mensaje de error.
function Test-PS5HSProjectModel($P) {
  if ($null -eq $P) { return 'El cuerpo no incluye un proyecto.' }
  $format = [string]$P.format
  if ($format -ne 'ps5vproj') { return ('formato no reconocido: ' + $format) }
  $fvText = "$($P.formatVersion)"
  if ($fvText -notmatch '^\d+$' -or [int]$fvText -lt 1 -or [int]$fvText -gt 2) { return ('versión de formato no soportada: ' + $fvText) }
  $backend = [string]$P.backend
  if ($backend -notin @('sharp','opengl-ui','vulkan-ui','vulkan-compute','sharp-payload','ps5sdk','payload','ps5link','etahen')) { return ('backend desconocido: ' + $backend) }
  $name = [string]$P.name
  if (!$name.Trim()) { return 'el nombre del proyecto está vacío.' }
  if ($name.Length -gt 80) { return 'el nombre del proyecto supera 80 caracteres.' }
  $components = $P.components
  if ($null -eq $components) { return 'faltan los componentes.' }
  $ids = @()
  foreach ($c in @($components)) {
    if ($null -eq $c -or !$c.PSObject.Properties['id']) { return 'un componente no tiene id.' }
    $cid = [string]$c.id
    if (!$cid.Trim()) { return 'un componente tiene un id vacío.' }
    if ($ids -contains $cid) { return ('id de componente duplicado: ' + $cid) }
    $ids += $cid
  }
  if ([int]$fvText -eq 2) {
    if ($null -eq $P.screens) { return 'faltan las pantallas.' }
    $screenIds = @()
    foreach ($s in @($P.screens)) {
      $sid = if ($s -and $s.PSObject.Properties['id']) { [string]$s.id } else { '' }
      if (!$sid.Trim()) { return 'una pantalla no tiene id.' }
      $screenIds += $sid
    }
    $current = [string]$P.currentScreen
    if ($current -and $screenIds -notcontains $current) { return ('la pantalla activa no existe: ' + $current) }
    foreach ($c in @($components)) {
      $csid = if ($c.PSObject.Properties['screenId']) { [string]$c.screenId } else { '' }
      if ($csid -and $screenIds -notcontains $csid) { return ('el componente ' + [string]$c.id + ' apunta a una pantalla inexistente.') }
    }
  }
  return $null
}


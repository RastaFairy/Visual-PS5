$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'native-modification-policy.ps1')

function Assert-Condition([bool]$Condition,[string]$Message) {
  if (!$Condition) { throw $Message }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('ps5hs-project-destination-' + [guid]::NewGuid().ToString('N'))
try {
  $missing = Join-Path $root 'not-created-yet'
  Assert-Condition (TestPS5HSNativeProjectDestinationAvailable -Path $missing) 'Un destino ausente debe estar disponible.'
  [IO.Directory]::CreateDirectory($root) | Out-Null
  Assert-Condition (TestPS5HSNativeProjectDestinationAvailable -Path $root) 'Se debe poder reintentar en una carpeta vacía.'
  [IO.File]::WriteAllText((Join-Path $root 'content.txt'),'keep')
  Assert-Condition (!(TestPS5HSNativeProjectDestinationAvailable -Path $root)) 'No se debe reutilizar una carpeta con contenido.'
  Assert-Condition (!(TestPS5HSNativeProjectDestinationAvailable -Path (Join-Path $root 'content.txt'))) 'Un archivo no es un destino de proyecto válido.'
  Write-Output 'PASS native project destination: missing and empty paths allowed; nonempty and file paths rejected.'
} finally {
  if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}

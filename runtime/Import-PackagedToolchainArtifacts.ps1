# Import-PackagedToolchainArtifacts.ps1
# Copia solo los artefactos binarios fijados desde el ZIP distribuido del IDE.
# No descarga nada, no modifica fuentes upstream y nunca sobrescribe una copia invalida.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PackageZip,

    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '..')
)

$ErrorActionPreference = 'Stop'

$ideRoot = [IO.Path]::GetFullPath($RepositoryRoot)
$pinsPath = Join-Path $ideRoot 'runtime/toolchain-pins.json'
if (!(Test-Path -LiteralPath $pinsPath -PathType Leaf)) {
    throw "No se encontro el manifiesto de pins: $pinsPath"
}

$resolvedZip = Resolve-Path -LiteralPath $PackageZip
$zipPath = [IO.Path]::GetFullPath($resolvedZip.Path)
if (!(Test-Path -LiteralPath $zipPath -PathType Leaf)) {
    throw "No se encontro el ZIP de distribucion: $zipPath"
}

$pins = Get-Content -LiteralPath $pinsPath -Raw | ConvertFrom-Json
$artifactNames = @('ps5-opengl-sdk', 'ps5-payload-sdk', 'zlib', 'pacbrew', 'googletest')
$stageRoot = Join-Path ([IO.Path]::GetTempPath()) ('ps5hs-toolchain-import-' + [guid]::NewGuid().ToString('N'))
$plan = @()
$zip = $null

try {
    New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)

    $rootPrefix = $ideRoot.TrimEnd([char[]]@('\', '/')) + [IO.Path]::DirectorySeparatorChar

    # Validar primero todos los cinco archivos; no cambiar el checkout si falta
    # una entrada o cualquiera de los hashes no coincide.
    $index = 0
    foreach ($name in $artifactNames) {
        $pinProperty = $pins.artifacts.PSObject.Properties[$name]
        if ($null -eq $pinProperty) {
            throw "El manifiesto no contiene el pin requerido: $name"
        }

        $pin = $pinProperty.Value
        $relativePath = [string]$pin.localPath
        $expectedFile = [string]$pin.file
        $expectedHash = [string]$pin.archive.sha256
        if ([string]::IsNullOrWhiteSpace($relativePath) -or
            [string]::IsNullOrWhiteSpace($expectedFile) -or
            $expectedHash -notmatch '^[0-9a-fA-F]{64}$') {
            throw "Pin incompleto o invalido para el artefacto: $name"
        }

        $entryName = $relativePath.Replace('\', '/')
        if (!$entryName.StartsWith('toolchains/', [StringComparison]::Ordinal) -or
            $entryName -match '(^|/)\.\.(/|$)' -or
            $entryName.Split('/')[-1] -ne $expectedFile) {
            throw "Ruta de destino no permitida para el pin $name ($relativePath)"
        }

        $target = [IO.Path]::GetFullPath((Join-Path $ideRoot ($entryName.Replace('/', [string][IO.Path]::DirectorySeparatorChar))))
        if (!$target.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "La ruta de destino queda fuera del repositorio: $target"
        }

        $entry = $zip.GetEntry($entryName)
        if ($null -eq $entry -or $entry.Length -le 0) {
            throw "El ZIP no contiene el artefacto requerido: $entryName"
        }

        $stagedPath = Join-Path $stageRoot (('{0}-{1}' -f $index, $expectedFile))
        $inputStream = $null
        $outputStream = $null
        try {
            $inputStream = $entry.Open()
            $outputStream = [IO.File]::Create($stagedPath)
            $inputStream.CopyTo($outputStream)
        }
        finally {
            if ($outputStream) { $outputStream.Dispose() }
            if ($inputStream) { $inputStream.Dispose() }
        }

        $actualHash = (Get-FileHash -LiteralPath $stagedPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $expectedHash.ToLowerInvariant()) {
            throw "SHA-256 incorrecto para $entryName. Esperado $expectedHash; recibido $actualHash. No se ha copiado ningun archivo."
        }

        $alreadyPresent = $false
        if (Test-Path -LiteralPath $target) {
            if (!(Test-Path -LiteralPath $target -PathType Leaf)) {
                throw "La ruta de destino existe y no es un archivo: $target"
            }
            $existingHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($existingHash -ne $expectedHash.ToLowerInvariant()) {
                throw "No se sobrescribe el archivo existente con SHA-256 distinto: $target. Muevelo manualmente a una copia de seguridad y repite la importacion."
            }
            $alreadyPresent = $true
        }

        $plan += [pscustomobject]@{
            Name = $name
            Target = $target
            StagedPath = $stagedPath
            Sha256 = $expectedHash.ToLowerInvariant()
            AlreadyPresent = $alreadyPresent
        }
        $index++
    }

    $zip.Dispose()
    $zip = $null

    # Solo despues de validar entradas, pins y destinos se escriben los faltantes.
    foreach ($item in $plan) {
        if ($item.AlreadyPresent) {
            Write-Host ("VALIDADO (ya existia): {0}" -f $item.Target)
            continue
        }

        $targetDirectory = Split-Path -Parent $item.Target
        New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        $temporaryTarget = $item.Target + '.ps5hs-import-' + [guid]::NewGuid().ToString('N') + '.tmp'
        try {
            Copy-Item -LiteralPath $item.StagedPath -Destination $temporaryTarget
            $copiedHash = (Get-FileHash -LiteralPath $temporaryTarget -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($copiedHash -ne $item.Sha256) {
                throw "La copia temporal no supera SHA-256: $temporaryTarget"
            }
            if (Test-Path -LiteralPath $item.Target) {
                throw "El destino aparecio durante la importacion; no se sobrescribio: $($item.Target)"
            }
            [IO.File]::Move($temporaryTarget, $item.Target)
        }
        finally {
            if (Test-Path -LiteralPath $temporaryTarget) {
                Remove-Item -LiteralPath $temporaryTarget -Force
            }
        }

        Write-Host ("IMPORTADO Y VERIFICADO: {0} [{1}]" -f $item.Target, $item.Sha256)
    }

    Write-Host 'Importacion completada: cinco artefactos comprobados contra runtime/toolchain-pins.json. No se consulto Internet.' -ForegroundColor Green
}
finally {
    if ($zip) { $zip.Dispose() }
    Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
}

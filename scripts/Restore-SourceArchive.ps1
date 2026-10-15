$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$segments = Join-Path $repoRoot 'release\source-archive'
$output = Join-Path $repoRoot 'PS5-Homebrew-Studio-v1.0.1.tar.xz'
$expectedHash = 'f6aa6aae6d5d58a1e5e2e3582d168f0e97f67e1d105938ed6039ba963b329d13'

$parts = @(Get-ChildItem -LiteralPath $segments -Filter 'part*.b64' -File | Sort-Object Name)
if ($parts.Count -ne 7) {
    throw "Expected 7 archive segments; found $($parts.Count). Do not continue with an incomplete archive."
}
$base64 = ($parts | ForEach-Object { (Get-Content -LiteralPath $_.FullName -Raw).Trim() }) -join ''
try {
    $bytes = [Convert]::FromBase64String($base64)
} catch {
    throw "The source archive segments are corrupt or have been edited: $($_.Exception.Message)"
}
[IO.File]::WriteAllBytes($output, $bytes)
$actualHash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $expectedHash) {
    Remove-Item -LiteralPath $output -Force
    throw "SHA-256 mismatch. Expected $expectedHash but got $actualHash."
}
Write-Host "Verified SHA-256: $actualHash"
$null = & tar -tJf $output
if ($LASTEXITCODE -ne 0) { throw 'tar could not read the XZ archive.' }
& tar -xJf $output -C $repoRoot
if ($LASTEXITCODE -ne 0) { throw 'Extraction failed.' }
Write-Host "Source restored under $repoRoot\PS5-Homebrew-Studio"

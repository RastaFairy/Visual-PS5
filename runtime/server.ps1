# PS5 Homebrew Studio · Windows local service (PowerShell 5.1+)
# Localhost only: project filesystem and process execution are not exposed to the LAN.
param([switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
$script:Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script:Toolchains = Join-Path $script:Root 'toolchains'
$script:Runtime = Join-Path $script:Root '.runtime'
$script:Exports = Join-Path $script:Runtime 'exports'
$script:Workspace = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PS5HomebrewStudio\Projects'
$script:Url = 'http://127.0.0.1:47813/'
$script:Utf8 = [System.Text.UTF8Encoding]::new($false)
$script:NativeRuntimeProfileScript = Join-Path $PSScriptRoot 'native-runtime.ps1'
if (!(Test-Path -LiteralPath $script:NativeRuntimeProfileScript -PathType Leaf)) { throw 'Falta runtime/native-runtime.ps1; el IDE no se iniciará sin su perfil nativo.' }
. $script:NativeRuntimeProfileScript
$script:NativeModificationPolicyScript = Join-Path $PSScriptRoot 'native-modification-policy.ps1'
if (!(Test-Path -LiteralPath $script:NativeModificationPolicyScript -PathType Leaf)) { throw 'Falta runtime/native-modification-policy.ps1; el IDE no iniciará sin el control de permisos de modificación.' }
. $script:NativeModificationPolicyScript
$script:VulkanComputeRuntimeScript = Join-Path $PSScriptRoot 'vulkan-compute.ps1'
if (!(Test-Path -LiteralPath $script:VulkanComputeRuntimeScript -PathType Leaf)) { throw 'Falta runtime/vulkan-compute.ps1; el IDE no iniciará con el backend compute desconectado.' }
. $script:VulkanComputeRuntimeScript
$script:ToolchainPinsPath = Join-Path $PSScriptRoot 'toolchain-pins.json'
$script:ToolchainPins = $null
if (Test-Path -LiteralPath $script:ToolchainPinsPath -PathType Leaf) {
  try { $script:ToolchainPins = Get-Content -LiteralPath $script:ToolchainPinsPath -Raw | ConvertFrom-Json } catch { $script:ToolchainPins = $null }
}

function GetPS5HSSdkArtifactPin {
  if (!$script:ToolchainPins -or !$script:ToolchainPins.artifacts) { return $null }
  $prop = $script:ToolchainPins.artifacts.PSObject.Properties['ps5-opengl-sdk']
  if (!$prop) { return $null }
  return $prop.Value
}

function GetPS5HSToolchainPackRoot { return (Join-Path $script:Toolchains 'ps5-opengl-sdk') }
function GetPS5HSToolchainPackSdkArchive {
  $pin = GetPS5HSSdkArtifactPin
  if (!$pin) { return @{present=$false;verified=$false;path='';version='';sha256='';bytes=0} }
  $candidate = Join-Path (GetPS5HSToolchainPackRoot) ([string]$pin.file)
  $present = (Test-Path -LiteralPath $candidate -PathType Leaf)
  $verified = $false
  $bytes = 0
  if ($present) {
    try {
      $bytes = (Get-Item -LiteralPath $candidate).Length
      $verified = ((Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant() -eq [string]$pin.archive.sha256)
    } catch { $verified = $false }
  }
  return @{present=$present;verified=$verified;path=$candidate;version=[string]$pin.version;sha256=[string]$pin.archive.sha256;bytes=$bytes}
}
function SeedProjectOpenGlSdkCache([string]$ProjectRoot) {
  $pin = GetPS5HSSdkArtifactPin
  if (!$pin) { return @{seeded=$false;reason='no hay pin del artefacto ps5-opengl-sdk'} }
  $pack = GetPS5HSToolchainPackSdkArchive
  if (!$pack.present) { return @{seeded=$false;reason='el pack local no contiene el tarball del SDK'} }
  if (!$pack.verified) { return @{seeded=$false;reason='el tarball del pack no coincide con el pin SHA-256; no se sembrara'} }
  $cacheDir = Join-Path $ProjectRoot '.deps/ps5-opengl'
  $target = Join-Path $cacheDir ([string]$pin.file)
  if (Test-Path -LiteralPath $target -PathType Leaf) {
    try {
      $existingOk = ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -eq [string]$pin.archive.sha256)
      if ($existingOk) { return @{seeded=$false;alreadyPresent=$true;path=$target} }
    } catch { }
    Remove-Item -LiteralPath $target -Force
  }
  New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
  Copy-Item -LiteralPath $pack.path -Destination $target -Force
  $finalOk = ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -eq [string]$pin.archive.sha256)
  if (!$finalOk) { Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue; return @{seeded=$false;reason='la copia no supero la verificacion SHA-256'} }
  return @{seeded=$true;path=$target}
}
$script:Catalog = @(
  @{id='sharp';name='SharpProspero';repo='SvenGDK/SharpProspero';branch='main';folder='SharpProspero';role='Aplicaciones nativas / payload C#';license='GPL-3.0-or-later';description='SDK C# y toolchain de aplicaciones nativas, interfaz, gráficos, audio, entrada, red y payloads.'},
  @{id='ps5sdk';name='PS5SDK';repo='PS5Dev/PS5SDK';branch='main';folder='PS5SDK';role='Payload ELF C/C++';license='GPL-2.0';description='SDK en desarrollo para ELF/payloads y homebrew sencillo; no construye títulos completos.'},
  @{id='payload';name='ps5-payload-dev/sdk';repo='ps5-payload-dev/sdk';branch='master';folder='ps5-payload-sdk';role='SDK de payloads C/C++';license='GPL-3.0-or-later';description='SDK con enlace dinámico, prospero-clang, herramientas y muestras de payload.'},
  @{id='ps5link';name='ps5link-sdk';repo='Rufidj/ps5link-sdk';branch='master';folder='ps5link-sdk';role='Título nativo / eboot.bin';license='GPL-3.0';description='Enlazador para títulos nativos. Requiere dependencias y libc.prx compatible para empaquetar.'},
  @{id='etahen';name='etaHEN-Plugins';repo='etaHEN/etaHEN-Plugins';branch='main';folder='etaHEN-Plugins';role='Plugins/daemons etaHEN';license='GPL-3.0';description='SDK para plugins de etaHEN Toolbox; no equivale a una aplicación GUI independiente.'},
  @{id='nid';name='libNidResolver';repo='astrelsky/libNidResolver';branch='master';folder='libNidResolver';role='Dependencia etaHEN';license='GPL-2.0';description='Fuente local offline fijada al commit 3f7ce7086c38ef35eb7869aafb247ed544ae3ee1; dependencia C para consumidores compatibles.';category='dependency'},
  @{id='nativecpp';name='PS5 Native App Boilerplate';repo='blackbearreloaded/ps5-native-app-boilerplate';branch='main';folder='ps5-native-app-boilerplate';role='Fundación C/C++20 para títulos nativos';license='GPL-3.0-or-later';description='Base de aplicación nativa con runtime reproducible, metadatos y empaquetado; clona con submódulos.';category='source';method='git'},
  @{id='opengl';name='PS5 OpenGL 4.6';repo='blackbearreloaded/ps5-opengl';branch='main';folder='ps5-opengl';role='Renderer OpenGL 4.6 / GLSL 4.60';license='GPL-3.0-or-later';description='Pila Mesa/Gallium, EGL, compilación de shaders, SDK estático, puente SDL2 y ejemplos.';category='source';method='git'},
  @{id='hui-gl';name='PS5 Homebrew UI (OpenGL)';repo='blackbearreloaded/ps5-homebrew-ui';branch='main';folder='ps5-homebrew-ui';role='Kit de interfaz OpenGL';license='GPL-3.0-or-later';description='Fuente upstream de renderer/componentes OpenGL; el shell de los títulos visuales queda bajo control de Homebrew Studio.';category='source';method='git'},
  @{id='vulkan-template';name='PS5 Vulkan Template';repo='mihawk-99/PS5_VulkanTemplate';branch='main';folder='PS5_VulkanTemplate';role='Plantilla Vulkan/RADV con generador';license='MIT base; UI opcional GPL-3.0-or-later';description='Fundación Vulkan, ejemplos, test runner y new-title.py para crear títulos nativos.';category='source';method='git'},
  @{id='vulkan-radv';name='PS5_Vulkan / RADV';repo='mihawk-99/PS5_Vulkan';branch='main';folder='PS5_Vulkan';role='Driver Vulkan Mesa/RADV';license='GPL-3.0-or-later';description='Driver Vulkan y capa de plataforma para el stack RADV de PS5; requiere componentes compañeros.';category='source';method='git'},
  @{id='vulkan-sdk';name='PS5_PayloadSDK (fork RADV)';repo='mihawk-99/PS5_PayloadSDK';branch='main';folder='PS5_PayloadSDK';role='SDK compañero de PS5 Vulkan';license='Revisar upstream';description='Fork del SDK con capa PS5. La revisión 611893fc se resuelve desde el snapshot local versionado en toolchains/PS5_PayloadSDK-pinned-611893fc; no requiere historial Git.';category='source';method='git';fullHistory=$false},
  @{id='vulkan-alt';name='ps5-vulkan (alternativo)';repo='mpereiraesaa/ps5-vulkan';branch='main';folder='ps5-vulkan-alt';role='Driver Vulkan experimental alternativo';license='GPL-3.0-or-later';description='Implementación experimental separada de RADV; no mezclar APIs ni dependencias sin revisar.';category='source';method='git'},
  @{id='hui-vk';name='PS5 VKHomebrewUI';repo='mihawk-99/PS5_VKHomebrewUI';branch='main';folder='PS5_VKHomebrewUI';role='Kit UI para Vulkan/RADV';license='GPL-3.0-or-later';description='Fork del kit UI con backend Vulkan; usar la revisión fijada por la plantilla compatible.';category='source';method='git'},
  @{id='prosperolight';name='ProsperoLight';repo='blackbearreloaded/ProsperoLight';branch='main';folder='ProsperoLight';role='Aplicación de referencia Moonlight';license='Revisar upstream';description='Aplicación nativa grande con OpenGL, decodificación de vídeo, audio, entrada y UI.';category='source';method='git'},
  @{id='eden';name='ProsperoEden0';repo='Tiang-88/ProsperoEden0';branch='main';folder='ProsperoEden0';role='Aplicación de referencia; IA declarada';license='Revisar upstream';description='Port experimental que documenta asistencia de OpenAI y/o Anthropic; auditar sus deps y licencias.';category='source';method='git'},
  @{id='stremio';name='Unofficial Stremio PS5 Port';repo='Sp9nky/unofficial-stremio-ps5-port';branch='main';folder='unofficial-stremio-ps5-port';role='Aplicación multimedia de referencia';license='Revisar upstream';description='Port multimedia con UI nativa, OpenGL y dependencias fijadas.';category='source';method='git'},
  @{id='nativehbl';name='Nativehbl';repo='Rufidj/Nativehbl';branch='main';folder='Nativehbl';role='Launcher nativo SDL2';license='Revisar upstream';description='Launcher de homebrew con navegación, recursos y backend de lanzamiento.';category='source';method='git'},
  @{id='ps5gl';name='PS5GL (API OpenGL-shaped sobre AGC)';repo='Rufidj/ps5gl';branch='master';folder='ps5gl';role='Renderer de compatibilidad OpenGL';license='Revisar upstream';description='API OpenGL parcial construida sobre ps5link ps5gpu/AGC; no dispone de compilador GLSL y varias funciones están declaradas pero no implementadas.';category='source';method='git'},
  @{id='opengl-mihawk';name='PS5 OpenGL (fork alternativo)';repo='mihawk-99/ps5-opengl';branch='main';folder='ps5-opengl-mihawk';role='Renderer OpenGL 4.6 alternativo';license='GPL-3.0-or-later';description='Otra línea del stack OpenGL/Mesa; compárala con ps5-opengl y evita mezclar SDK binarios de distintas revisiones.';category='source';method='git'},
  @{id='fsr4';name='PS5 FSR4';repo='blackbearreloaded/ps5-fsr4';branch='main';folder='ps5-fsr4';role='SDK de upscaling Vulkan compute';license='Revisar licencia y THIRD_PARTY_NOTICES';description='Integración experimental de FSR 4 para el stack Vulkan de PS5; necesita dependencias fijadas y perfil diagnóstico del driver.';category='source';method='git'},
  @{id='helixsr';name='PS5 HelixSR';repo='blackbearreloaded/ps5-helixsr';branch='main';folder='ps5-helixsr';role='SDK de upscaling Vulkan compute';license='Revisar licencia y avisos upstream';description='Runtime nativo para HelixSR; source only y requiere que el usuario aporte su nvngx_dlss.dll legítima. No descarga ni redistribuye ese binario.';category='source';method='git'},
  @{id='sunshine';name='PS5 Sunshine';repo='griches/PS5_Sunshine';branch='main';folder='PS5_Sunshine';role='Port de juego / referencia OpenGL';license='GPL-3.0 según el README';description='Port nativo de Super Mario Sunshine; referencia de porting. Requiere imagen de juego propia, no incluida.';category='source';method='git'},
  @{id='switchwaker';name='PS5 SwitchWaker';repo='griches/PS5_SwitchWaker';branch='main';folder='PS5_SwitchWaker';role='Port de juego / referencia WebGPU-RADV';license='GPL-3.0 según el README';description='Port de Wind Waker sobre Aurora/Dawn WebGPU y el stack PS5 Vulkan; datos de juego no incluidos.';category='source';method='git'},
  @{id='dusklight';name='PS5 Dusklight';repo='griches/PS5_Dusklight';branch='main';folder='PS5_Dusklight';role='Port de juego / referencia WebGPU-RADV';license='GPL-3.0 según el README';description='Port experimental de Dusklight basado en Aurora/Dawn WebGPU y RADV; requiere datos propios del juego.';category='source';method='git'},
  @{id='ghostship';name='PS5 Ghostship (Mario 64)';repo='griches/PS5_Ghostship';branch='main';folder='PS5_Ghostship';role='Port nativo / referencia Vulkan';license='GPL-3.0 según el README';description='Port de Ghostship/libultraship sobre Vulkan/RADV; útil como referencia de integración de renderer y UI.';category='source';method='git'},
  @{id='porpoise';name='Porpoise Dolphin Emulator';repo='elripalda/Porpoise-Dolphin-Emulator-for-PS5';branch='Main';folder='Porpoise-Dolphin-Emulator-for-PS5';role='Emulador de referencia Vulkan';license='GPL-3.0-or-later';description='Aplicación Dolphin con launcher y biblioteca de juegos; proyecto grande y no plantilla mínima. No incluye juegos, BIOS ni firmware.';category='source';method='git'},
  @{id='ps5x360';name='PS5X360 (Xenia Canary)';repo='BrinooTk/PS5X360';branch='main';folder='PS5X360';role='Emulador de referencia Vulkan/RADV';license='Revisar upstream';description='Integración experimental de Xenia Canary con DualSense, audio y RADV; requiere recursos legítimos del usuario.';category='source';method='git'},
  @{id='syobon';name='Syobon Action PS5';repo='kvaps/syobon-action-ps5';branch='main';folder='syobon-action-ps5';role='Juego SDL2 / referencia de porting';license='Revisar licencias upstream';description='Port de Syobon Action sobre SDL2 y Native App Boilerplate; ejemplo de mover una aplicación existente a PS5.';category='source';method='git'},
  @{id='ps5-mesa';name='PS5_Mesa / RADV (dependencia crítica)';repo='mihawk-99/PS5_Mesa';branch='main';folder='PS5_Mesa';role='Fuente Mesa/RADV con winsys PS5';license='Licencias Mesa y avisos de terceros';description='Fork grande de Mesa con winsys/VideoOut y RADV; PS5_Vulkan fija un commit que el build exporta y compila.';category='source';method='git';fullHistory=$true},
  @{id='aurora';name='Aurora';repo='encounter/aurora';branch='main';folder='aurora';role='Capa GX/WebGPU para ports';license='MIT';description='Capa de compatibilidad para proyectos GameCube/Wii con SDL3, GX, WebGPU/Dawn, input, disco, Dear ImGui y RmlUi.';category='source';method='git'},
  @{id='quake3e';name='PS5 Quake3e';repo='griches/PS5_Quake3e';branch='main';folder='PS5_Quake3e';role='Motor/port Vulkan-RADV';license='GPL-3.0 según upstream; revisar componentes';description='Port real del motor Quake3e con Vulkan/RADV, DualSense y audio. Requiere datos del juego del usuario.';category='source';method='git'},
  @{id='retroarch';name='PS5 RetroArch';repo='mihawk-99/PS5_RetroArch';branch='main';folder='PS5_RetroArch';role='Frontend/emulación Vulkan';license='GPL y licencias individuales de cores';description='Aplicación nativa modular con RetroArch, EmulationStation, WebUI y numerosos cores; no incluye ROMs/BIOS.';category='source';method='git'},
  @{id='x360-ai';name='X360PS5 (asistencia IA declarada)';repo='polarco/X360PS5';branch='master';folder='X360PS5-AI-Prototype';role='Prototipo experimental Xenia/Vulkan';license='Revisar licencia y dependencias';description='Investigación asistida por Codex declarada por su README; pruebas de host, no PS5 probado y aún no carga juegos.';category='source';method='git';aiDeclared=$true}
  @{id='ps5-ultrapack';name='PS5 UltraPack';repo='knutwurst/ps5-ultrapack';branch='main';folder='ps5-ultrapack';role='Empaquetado ffpfs/ffpfsc/fPKG';license='MIT para código propio + licencias de terceros';description='CLI para convertir carpetas de título en .ffpfs/.ffpfsc/.pkg; el soporte fuera de macOS puede ser limitado.'}
)
function WriteUtf8([string]$Path,[string]$Content) {
  $fullPath = [IO.Path]::GetFullPath($Path)
  $parentPath = [IO.Path]::GetDirectoryName($fullPath)
  if (![string]::IsNullOrWhiteSpace($parentPath) -and !(Test-Path -LiteralPath $parentPath -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $parentPath | Out-Null
  }
  [IO.File]::WriteAllText($fullPath,$Content,$script:Utf8)
}

# Normalizes build-critical text copied from Windows checkouts before Make/WSL consumes it.
# This preserves file bytes except CR characters used as line endings and never touches binaries.
function NormalizeNativeBuildFiles([string]$ProjectRoot,[bool]$EnsureSha256Attributes=$true) {
  $root = [IO.Path]::GetFullPath($ProjectRoot)
  $allowedExtensions = @('.sh','.sha256','.c','.cc','.cpp','.h','.hpp','.ld','.mk','.s','.cmake','.yml','.yaml')
  $allowedNames = @('Makefile','GNUmakefile','CMakeLists.txt','.gitattributes')
  $normalized = 0
  foreach ($item in (Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction Stop)) {
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
    $relativePath = $item.FullName.Substring($root.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar).Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if ($relativePath -match '(^|[\\/])(\.git|\.deps|\.cache|build|dist|out|obj|node_modules|\.runtime)([\\/]|$)') { continue }
    $extension = $item.Extension.ToLowerInvariant()
    if ($item.Name -notin $allowedNames -and $extension -notin $allowedExtensions) { continue }
    $bytes = [IO.File]::ReadAllBytes($item.FullName)
    if ($bytes.Length -eq 0) { continue }
    $output = [System.Collections.Generic.List[byte]]::new()
    $changed = $false
    for ($i = 0; $i -lt $bytes.Length; $i++) {
      if ($bytes[$i] -eq 13) {
        if ($i + 1 -lt $bytes.Length -and $bytes[$i + 1] -eq 10) { $i++ }
        $null = $output.Add([byte]10)
        $changed = $true
      } else {
        $null = $output.Add($bytes[$i])
      }
    }
    if ($changed) {
      [IO.File]::WriteAllBytes($item.FullName, $output.ToArray())
      $normalized++
    }
  }

  # Upstream's checksum manifest is text too. Declare its LF policy so a later
  # Git checkout on Windows does not reintroduce CRLF and fail an exact digest check.
  $attributesPath = Join-Path $root '.gitattributes'
  if ($EnsureSha256Attributes -and (Test-Path -LiteralPath $attributesPath -PathType Leaf)) {
    $attributes = [IO.File]::ReadAllText($attributesPath)
    $attributes = $attributes -replace "`r`n?", "`n"
    if ($attributes -notmatch '(?m)^\*\.sha256\s+text\b') {
      if ($attributes.Length -gt 0 -and !$attributes.EndsWith("`n")) { $attributes += "`n" }
      $attributes += "*.sha256 text eol=lf`n"
      [IO.File]::WriteAllText($attributesPath, $attributes, $script:Utf8)
    }
  }
  return $normalized
}
function SendBytes($C,[byte[]]$B,[string]$Type='application/octet-stream',[int]$Code=200) {
  $C.Response.StatusCode=$Code; $C.Response.ContentType=$Type; $C.Response.Headers['Cache-Control']='no-store'; $C.Response.Body=$B
}
function SendJson($C,$Object,[int]$Code=200) { $j=ConvertTo-Json -InputObject $Object -Depth 100 -Compress; SendBytes $C ([Text.Encoding]::UTF8.GetBytes($j)) 'application/json; charset=utf-8' $Code }
function ReadBody($C) { if([string]::IsNullOrWhiteSpace($C.Request.Body)){return $null}; return ($C.Request.Body | ConvertFrom-Json) }
function CmdInfo([string]$N) { $x=Get-Command $N -ErrorAction SilentlyContinue|Select-Object -First 1; if($x){return @{ok=$true;path=$x.Source;version=''}}; return @{ok=$false;path='';version=''} }
function GetPS5HSOfflineBackendReadiness([string]$Backend) {
  $readinessPath = Join-Path $PSScriptRoot 'offline/backend-readiness.json'
  $bundlePresent = (Test-Path -LiteralPath (Join-Path $script:Root 'manifest.json') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $script:Root 'SHA256SUMS') -PathType Leaf)
  $backendId = switch ($Backend) {
    'hui-gl' { 'native-opengl-ui' }
    'opengl-ui' { 'native-opengl-ui' }
    'vulkan-template' { 'native-vulkan-ui' }
    'vulkan-ui' { 'native-vulkan-ui' }
    'sharp' { 'sharpprospero-nativeaot' }
    'payload' { 'ps5-payload-sdk-sample' }
    'nativecpp' { 'native-app-boilerplate' }
    default { [string]$Backend }
  }
  if (!(Test-Path -LiteralPath $readinessPath -PathType Leaf)) {
    return @{backend=$backendId;status='unverified';enforced=[bool]$bundlePresent;reason='No existe el inventario de preparación offline.'}
  }
  if ($bundlePresent) {
    try {
      $bundleManifest = Get-Content -LiteralPath (Join-Path $script:Root 'manifest.json') -Raw | ConvertFrom-Json
      $readinessRecord = @($bundleManifest.files | Where-Object { [string]$_.path -ceq 'runtime/offline/backend-readiness.json' } | Select-Object -First 1)
      $actualReadinessHash = (Get-FileHash -LiteralPath $readinessPath -Algorithm SHA256).Hash.ToLowerInvariant()
      if (!$readinessRecord.Count -or $actualReadinessHash -cne [string]$readinessRecord[0].sha256) {
        return @{backend=$backendId;status='unverified';enforced=$true;reason='runtime/offline/backend-readiness.json no coincide con el hash declarado por el bundle.'}
      }
    } catch {
      return @{backend=$backendId;status='unverified';enforced=$true;reason='No se pudo verificar el manifiesto offline del bundle.'}
    }
  }
  try { $readiness = Get-Content -LiteralPath $readinessPath -Raw | ConvertFrom-Json }
  catch { return @{backend=$backendId;status='unverified';enforced=[bool]$bundlePresent;reason='No se pudo leer runtime/offline/backend-readiness.json.'} }
  $record = @($readiness.backends | Where-Object { [string]$_.id -eq $backendId } | Select-Object -First 1)
  if (!$record.Count) {
    return @{backend=$backendId;status='source-only';enforced=[bool]$bundlePresent;reason='No hay una receta offline aprobada para este backend.'}
  }
  return @{backend=$backendId;status=[string]$record[0].status;enforced=[bool]$bundlePresent;reason=[string]$record[0].evidence;scope=[string]$record[0].scope}
}
function GetStatus {
  $dot=CmdInfo 'dotnet.exe'; if(!$dot.ok){$dot=CmdInfo 'dotnet'}; $dot10=$false; $dotVersion='No detectado'
  if($dot.ok){try{$list=(& $dot.path --list-sdks 2>$null|Out-String);$dot10=[bool]($list -match '(?m)^10\.[0-9.]+');$dotVersion=((& $dot.path --version 2>$null|Out-String).Trim())}catch{$dot10=$false;$dotVersion='No se pudo consultar .NET SDK: '+$_.Exception.Message}}
  $wsl=CmdInfo 'wsl.exe';$wslOk=$false;$wslDist='No detectada';$wslDot=$false;$wslGitPython=$false;$offlineUbuntuVerified=$false;$offlineDistroName='VisualPS5-Ubuntu-26.04'
  if($wsl.ok){try{
    $distOutput=@(& $wsl.path -l -q 2>$null);$exitWsl=$LASTEXITCODE
    $entries=@($distOutput|ForEach-Object{($_.ToString() -replace "`0",'').Trim()}|Where-Object{$_ -and $_ -notmatch 'no installed distributions|no hay distribuciones instaladas|Windows Subsystem for Linux|distribuciones instaladas'}|ForEach-Object{$_ -replace '^\*\s*',''})
    $wslOk=($exitWsl -eq 0 -and $entries.Count -gt 0)
    if($wslOk){
      if($offlineDistroName -in $entries){$wslDist=$offlineDistroName}else{$wslDist=$entries[0]}
      & $wsl.path -d $wslDist --exec bash -lc 'dotnet --list-sdks 2>/dev/null | grep -q "^10\."' 2>$null;$wslDot=($LASTEXITCODE -eq 0)
      & $wsl.path -d $wslDist --exec bash -lc 'command -v git >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1' 2>$null;$wslGitPython=($LASTEXITCODE -eq 0)
      if($wslDist -eq $offlineDistroName){
        $identityCheck='test "$(id -un)" = visualps5 && test -x /opt/ps5-payload-sdk/bin/prospero-lld && test -x "$(command -v cmake)" && test -x "$(command -v git)" && test "$(. /etc/os-release; printf %s "$VERSION_ID")" = 26.04'
        & $wsl.path -d $wslDist --exec bash -lc $identityCheck 2>$null;$offlineUbuntuVerified=($LASTEXITCODE -eq 0)
      }
    }
  }catch{$wslOk=$false;$wslDist='';$wslDot=$false;$wslGitPython=$false;$offlineUbuntuVerified=$false}}
  $git=CmdInfo 'git.exe';if(!$git.ok){$git=CmdInfo 'git'}
  $cmake=CmdInfo 'cmake.exe';if(!$cmake.ok){$cmake=CmdInfo 'cmake'};$ninja=CmdInfo 'ninja.exe';if(!$ninja.ok){$ninja=CmdInfo 'ninja'};$clang=CmdInfo 'clang.exe';if(!$clang.ok){$clang=CmdInfo 'clang'};$make=CmdInfo 'make.exe';if(!$make.ok){$make=CmdInfo 'make'}
  $items=@(
    @{name='Git (para los builds que lo requieran)';ok=$git.ok;version='';detail=$git.path},
    @{name='.NET SDK 10 (Windows)';ok=$dot10;version=$dotVersion;detail=$dot.path},
    @{name='WSL con distribución Linux';ok=$wslOk;version=$wslDist;detail=$wsl.path},
    @{name='.NET SDK 10 dentro de WSL';ok=$wslDot;version=$(if($wslDot){'10.x detectado'}else{'No detectado'});detail='Necesario para NativeAOT en la ruta de SharpProspero.'},
    @{name='Git y Python 3 dentro de WSL';ok=$wslGitPython;version=$(if($wslGitPython){'Detectados'}else{'No detectados'});detail='Necesarios para los generadores C/C++ que se ejecutan desde WSL.'},
    @{name='CMake ≥ 3.20';ok=$cmake.ok;version='';detail=$cmake.path},
    @{name='Ninja';ok=$ninja.ok;version='';detail=$ninja.path},
    @{name='Clang';ok=$clang.ok;version='';detail=$clang.path},
    @{name='Make';ok=$make.ok;version='';detail=$make.path}
  )
  $sdks=@()
  foreach($e in $script:Catalog) {
    $p=Join-Path $script:Toolchains $e.folder
    $localSource=GetPS5HSBundledToolchainInfo $e $p
    $sourceOnly=[bool]($localSource.sourceInfo -and $localSource.sourceInfo.sourceOnly)
    $installed=[bool]$localSource.installed -and !$sourceOnly
    $category='backend';if($e.category){$category=[string]$e.category}
    $buildVerified=$null
    $buildStatus=''
    if($localSource.sourceInfo -and $localSource.sourceInfo.PSObject.Properties['buildVerified']) {
      $buildVerified=[bool]$localSource.sourceInfo.buildVerified
      $buildStatus=[string]$localSource.sourceInfo.buildStatus
    }
    $sdks+=@{
      id=$e.id;name=$e.name;folder=$e.folder;role=$e.role;license=$e.license;
      description=$e.description;category=$category;method=$e.method;
      href=('https://github.com/RastaFairy/Visual-PS5/tree/main/toolchains/'+$e.folder);
      sourceHref=('https://github.com/'+$e.repo);
      installed=$installed;bundled=[bool]$localSource.bundled;sourceOnly=$sourceOnly;
      buildVerified=$buildVerified;buildStatus=$buildStatus;
      buildable=([bool]$localSource.installed -and !$sourceOnly);path=$p;sourceCommit=[string]$localSource.commit;
    }
  }
  $sdkPackInfo=GetPS5HSToolchainPackSdkArchive
  $toolchainHealth=@{localOnly=$true;sourceRoot=$script:Toolchains;dependencySource='toolchains/ versionado en RastaFairy/Visual-PS5';pinsLoaded=($null -ne $script:ToolchainPins);pinsPath=$script:ToolchainPinsPath;sdkPack=@{present=$sdkPackInfo.present;verified=$sdkPackInfo.verified;version=$sdkPackInfo.version;sha256=$sdkPackInfo.sha256;bytes=$sdkPackInfo.bytes;path=$sdkPackInfo.path}}
  $readinessPath=Join-Path $PSScriptRoot 'offline/backend-readiness.json';$readinessBackends=@();$readinessSourcePresent=Test-Path -LiteralPath $readinessPath -PathType Leaf
  if($readinessSourcePresent){try{$readinessBackends=@((Get-Content -LiteralPath $readinessPath -Raw|ConvertFrom-Json).backends)}catch{$readinessBackends=@()}}
  $offlineBundlePresent=(Test-Path -LiteralPath (Join-Path $script:Root 'manifest.json') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $script:Root 'SHA256SUMS') -PathType Leaf)
  if($offlineBundlePresent -and $readinessBackends.Count){
    try{
      $bundleManifestForStatus=Get-Content -LiteralPath (Join-Path $script:Root 'manifest.json') -Raw|ConvertFrom-Json
      $readinessRecordForStatus=@($bundleManifestForStatus.files|Where-Object{[string]$_.path -ceq 'runtime/offline/backend-readiness.json'}|Select-Object -First 1)
      $currentReadinessHash=(Get-FileHash -LiteralPath $readinessPath -Algorithm SHA256).Hash.ToLowerInvariant()
      if(!$readinessRecordForStatus.Count -or $currentReadinessHash -cne [string]$readinessRecordForStatus[0].sha256){$readinessBackends=@([pscustomobject]@{id='bundle-readiness';status='blocked';evidence='La matriz de preparación no coincide con el hash del manifiesto del bundle.';scope='Verifica o vuelve a extraer el bundle offline.'})}
    }catch{$readinessBackends=@([pscustomobject]@{id='bundle-readiness';status='blocked';evidence='No se pudo verificar la matriz offline contra el manifiesto.';scope='Verifica el manifiesto y SHA256SUMS.'})}
  }
  $offlineEnvironment=@{
    mode=$(if($offlineBundlePresent){'offline-bundle'}else{'source-checkout'})
    ideInstalled=$true
    installerAvailable=($offlineBundlePresent -and (Test-Path -LiteralPath (Join-Path $script:Root 'INSTALL-OFFLINE.bat') -PathType Leaf))
    wslReady=$wslOk
    wslDistribution=$wslDist
    ubuntuVerified=$offlineUbuntuVerified
    backendReadinessSourcePresent=$readinessSourcePresent
    backends=$readinessBackends
  }
  return @{root=$script:Root;workspace=$script:Workspace;wslDistribution=$wslDist;sdks=$sdks;toolchainHealth=$toolchainHealth;offlineEnvironment=$offlineEnvironment;prerequisites=@{git=$git.ok;gitPath=$git.path;dotnet10=$dot10;wsl=$wslOk;wslDotnet10=$wslDot;wslGitPython=$wslGitPython;items=$items}}
}
function Slug([string]$Text) { $s=([string]$Text).Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}','';$s=$s -replace '[^a-zA-Z0-9_-]+','-';$s=$s.Trim('-');if(!$s){$s='MiHomebrew'};if($s.Length -gt 48){$s=$s.Substring(0,48)};return $s }
function TestPS5HSTitleId([string]$Value) { $id = ([string]$Value).Trim().ToUpperInvariant(); return (($id -match '^PPSA\d{5}$') -and $id -ne 'PPSA00000') }
function WriteProjectFiles($P,[string]$Code,[string]$Dir) {
  if ([string]$P.backend -eq 'ps5link' -and $P.manualCode -ne $true -and [string]::IsNullOrWhiteSpace($Code)) { $Code = GetPS5HSVisualGameSource $P }
  New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  $assets=Join-Path $Dir 'assets';New-Item -ItemType Directory -Force -Path $assets|Out-Null
  WriteUtf8 (Join-Path $Dir 'project.json') (ConvertTo-Json -InputObject $P -Depth 100)
  if([string]$P.backend -eq 'vulkan-compute' -and $P.computeGraph){WriteUtf8 (Join-Path $Dir 'compute-graph.json') (ConvertTo-Json -InputObject $P.computeGraph -Depth 80)}
  if($Code -and [string]$P.backend -eq 'payload'){
    $sourceDir=Join-Path $Dir 'src';New-Item -ItemType Directory -Force -Path $sourceDir|Out-Null
    $sourceName=if([string]$P.payloadLanguage -eq 'cpp'){'main.cpp'}else{'main.c'}
    if([string]$P.payloadBuildMode -ne 'upstream-makefile'){WriteUtf8 (Join-Path $sourceDir $sourceName) $Code}
  }
  elseif($Code -and [string]$P.backend -eq 'ps5link'){
    $sourceDir=Join-Path $Dir 'src';New-Item -ItemType Directory -Force -Path $sourceDir|Out-Null
    $mainPath=Join-Path $sourceDir 'main.c'
    if($P.manualCode -ne $true -and (Test-Path -LiteralPath $mainPath -PathType Leaf)){
      $oldItem=Get-Item -LiteralPath $mainPath -Force
      if(($oldItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'No se reemplazará src/main.c porque es un enlace o punto de reanálisis.'}
      $oldSource=[IO.File]::ReadAllText($mainPath,[Text.Encoding]::UTF8)
      if($oldSource -cne $Code){
        $backupPath=Join-Path $sourceDir 'main.manual.backup.c'
        if(Test-Path -LiteralPath $backupPath -PathType Leaf){
          $backupSource=[IO.File]::ReadAllText($backupPath,[Text.Encoding]::UTF8)
          if($backupSource -cne $oldSource){$backupPath=Join-Path $sourceDir ('main.manual.backup-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'.c')}
        }
        if(!(Test-Path -LiteralPath $backupPath -PathType Leaf)){WriteUtf8 $backupPath $oldSource}
      }
    }
    WriteUtf8 $mainPath $Code
  }
  elseif($Code -and [string]$P.backend -ne 'vulkan-compute'){
    if([string]$P.backend -in @('opengl-ui','vulkan-ui')){WriteUtf8 (Join-Path $Dir 'GeneratedScreen.cpp') $Code}
    else{WriteUtf8 (Join-Path $Dir 'Program.cs') $Code}
  }
  foreach($a in @($P.assets)){
    if(!$a -or !$a.dataUrl){continue}
    $name=[IO.Path]::GetFileName([string]$a.fileName);if(!$name){continue}
    if($a.dataUrl -match '^data:[^;]+;base64,(.*)$'){
      try{[IO.File]::WriteAllBytes((Join-Path $assets $name),[Convert]::FromBase64String($Matches[1]))}
      catch{throw ('No se pudo guardar el recurso ' + $name + ': ' + $_.Exception.Message)}
    }
  }
}

function GetPS5HSBundledToolchainInfo($Entry,[string]$Path) {
  $result=@{installed=$false;bundled=$false;commit='';sourceInfo=$null;reason=''}
  try {
    $toolchainsRoot=[IO.Path]::GetFullPath($script:Toolchains)+[IO.Path]::DirectorySeparatorChar
    $fullPath=[IO.Path]::GetFullPath($Path)
    if(!$fullPath.StartsWith($toolchainsRoot,[StringComparison]::OrdinalIgnoreCase)) {
      $result.reason='La ruta no está dentro de toolchains/ del repositorio del IDE.'
      return $result
    }
  } catch {
    $result.reason='No se pudo validar la ruta local de la toolchain: '+$_.Exception.Message
    return $result
  }
  if(!(Test-Path -LiteralPath $Path -PathType Container)) {
    $result.reason='No existe la carpeta versionada toolchains/'+[string]$Entry.folder+'.'
    return $result
  }
  $readme=$false
  foreach($name in @('README.md','readme.md','README')) {
    if(Test-Path -LiteralPath (Join-Path $Path $name) -PathType Leaf) {$readme=$true;break}
  }
  if(!$readme) {
    $result.reason='La carpeta local no contiene README.md/README.'
    return $result
  }
  $markerPath=Join-Path $Path '.ps5hs-source.json'
  if(!(Test-Path -LiteralPath $markerPath -PathType Leaf)) {
    $result.reason='Falta .ps5hs-source.json; no se confía en una carpeta sin procedencia verificable.'
    return $result
  }
  try {
    $sourceInfo=Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
    $expected=[string]$Entry.repo
    $sourceRepository=[string]$sourceInfo.repository
    $mirrorRepository=[string]$sourceInfo.mirrorRepository
    $declaredSource=[string]$sourceInfo.sourceRepository
    $repoMatches=($sourceRepository -eq $expected) -or ($mirrorRepository -eq $expected) -or ($declaredSource -eq $expected)
    $isVendored=([bool]$sourceInfo.vendoredSnapshot) -and ([string]$sourceInfo.vendorRepository -eq 'RastaFairy/Visual-PS5')
    if(!$isVendored) {
      $result.reason='El manifiesto no declara un snapshot versionado de RastaFairy/Visual-PS5.'
      return $result
    }
    if(!$repoMatches) {
      $result.reason='El repositorio del manifiesto no coincide con el catálogo esperado ('+$expected+').'
      return $result
    }
    $result.sourceInfo=$sourceInfo
    $result.commit=[string]$(if($sourceInfo.sourceCommit){$sourceInfo.sourceCommit}else{$sourceInfo.commit})
    $result.bundled=$true
    $result.installed=!([bool]$sourceInfo.sourceOnly)
    if([bool]$sourceInfo.sourceOnly) {
      $result.reason='La copia está marcada sourceOnly; sirve como referencia pero no como backend compilable.'
    } else {
      $result.reason='Fuente local verificada por su manifiesto de vendorización.'
    }
    return $result
  } catch {
    $result.reason='No se pudo validar .ps5hs-source.json: '+$_.Exception.Message
    return $result
  }
}

function InstallRepo($Entry) {
  $dest=Join-Path $script:Toolchains $Entry.folder
  $localSource=GetPS5HSBundledToolchainInfo $Entry $dest
  if(!$localSource.bundled) {
    $detail=[string]$localSource.reason
    if(!$detail) {$detail='La carpeta no cumple el manifiesto local esperado.'}
    throw ($detail+' No se ha consultado GitHub, probado mirrors ni descargado o sobrescrito nada. Revisa toolchains/'+[string]$Entry.folder+' en el repositorio RastaFairy/Visual-PS5.')
  }
  $sourceOnly=[bool]($localSource.sourceInfo -and $localSource.sourceInfo.sourceOnly)
  if($Entry.id -eq 'ps5-ultrapack') {
    $cli=Join-Path $dest 'backend\cli.py'
    if(!(Test-Path -LiteralPath $cli -PathType Leaf)) {
      throw ('La copia local de UltraPack está incompleta: falta '+$cli+'. No se descargará ni reparará desde Internet.')
    }
    $venvPython=Join-Path (Join-Path $dest '.venv') 'Scripts\python.exe'
    return @{
      ok=$true;name=$Entry.name;
      message=$(if(Test-Path -LiteralPath $venvPython -PathType Leaf){'Fuente y entorno Python locales encontrados; no se instalarán paquetes automáticamente.'}else{'Fuente local encontrada. No hay entorno Python incluido; no se instalarán paquetes por Internet. Configura un Python y dependencias ya disponibles localmente.'});
      path=$dest;commit=[string]$localSource.commit;vendored=$true;sourceOnly=$sourceOnly;cli=$cli;
      pythonExe=$(if(Test-Path -LiteralPath $venvPython -PathType Leaf){$venvPython}else{''})
    }
  }
  $message=if($sourceOnly){'Snapshot local encontrado, pero está marcado sourceOnly y no se considera compilable.'}else{'Fuente versionada validada en toolchains/; no se ha consultado ni descargado nada de Internet.'}
  return @{ok=$true;name=$Entry.name;message=$message;path=$dest;commit=[string]$localSource.commit;vendored=$true;sourceOnly=$sourceOnly;buildable=(!$sourceOnly)}
}
function BashQuote([string]$Text) { return "'" + $Text.Replace("'", "'\''") + "'" }
function ConvertToWslPath([string]$Path) {
  $full=[IO.Path]::GetFullPath($Path)
  if($full -notmatch '^([A-Za-z]):\\(.*)$'){throw "La ruta no puede traducirse a WSL: $full. Usa una carpeta dentro de una unidad local."}
  $drive=$Matches[1].ToLowerInvariant();$rest=$Matches[2] -replace '\\','/'
  return "/mnt/$drive/$rest"
}
function CopyProjectTree([string]$Source,[string]$Destination,[bool]$IsRoot=$true) {
  $alwaysExclude=@('.git','.deps','.cache','node_modules','__pycache__','.venv','.ps5hs-source.json')
  $rootExclude=@('build','dist','out','obj','.runtime')
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  $sourceItem = Get-Item -LiteralPath $Source -Force
  if (($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "La carpeta fuente es un enlace o punto de reanálisis; no se copiará: $Source"
  }
  foreach($item in (Get-ChildItem -LiteralPath $Source -Force -ErrorAction Stop)) {
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "La plantilla contiene un enlace o punto de reanálisis; se cancela la copia: $($item.FullName)"
    }
    if($alwaysExclude -contains $item.Name -or ($IsRoot -and $rootExclude -contains $item.Name)) { continue }
    $childDestination=Join-Path $Destination $item.Name
    if($item.PSIsContainer) {
      CopyProjectTree $item.FullName $childDestination $false
    } else {
      Copy-Item -LiteralPath $item.FullName -Destination $childDestination -Force
    }
  }
}
function NewNativeTitle([string]$Name,[string]$TitleId,[string]$Category,[string]$TemplateId,$Policy=$null) {
  if($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._-]{0,39}$') { return @{ok=$false;message='Nombre inválido. Usa 1–40 caracteres ASCII: letras, números, espacios, punto, guion o guion bajo.';output=''} }
  if(!(TestPS5HSTitleId $TitleId)) { return @{ok=$false;message='TITLE_ID inválido. Usa un identificador PPSA12345 válido distinto de PPSA00000.';output=''} }
  if($Category -notin @('game','media')) { return @{ok=$false;message='Categoría inválida.';output=''} }
  if($TemplateId -notin @('nativecpp','hui-gl')) { return @{ok=$false;message='La plantilla no dispone de un generador C++ aquí.';output=''} }
  $policy = AssertPS5HSNativeModificationConsent -Backend $TemplateId -Policy $Policy -RequirePermissionKeys @('allowExecuteUpstreamGenerationTools')
  $entry=$script:Catalog | Where-Object id -eq $TemplateId | Select-Object -First 1
  if(!$entry) { return @{ok=$false;message='No se encontró la plantilla en el catálogo.';output=$TemplateId} }
  try { $cloneResult = InstallRepo $entry; if(!$cloneResult.ok) { return @{ok=$false;message=$cloneResult.message;output=$cloneResult.path} } }
  catch { return @{ok=$false;message='No se pudo validar o preparar la plantilla local.';output=$_.Exception.Message} }
  $src=Join-Path $script:Toolchains $entry.folder
  $expected=@('Makefile','src/main.cpp')
  foreach($rel in $expected) { if(!(Test-Path (Join-Path $src $rel))) { return @{ok=$false;message="La plantilla upstream está incompleta: falta $rel. Vuelve a clonar $($entry.repo).";output=$src} } }
  $st=GetStatus
  if(!$st.prerequisites.wsl) { return @{ok=$false;message='No hay distribución WSL inicializada.';output='Configura WSL + Debian y completa su primer arranque.'} }
  if(!$st.prerequisites.wslGitPython) { return @{ok=$false;message='Faltan Git o Python 3 dentro de WSL.';output='Instala git y python3 dentro de la distribución Linux según la documentación upstream.'} }
  $dist=[string]$st.wslDistribution
  $suffix=Slug $Name
  $suffix=$suffix.ToUpperInvariant() -replace '[^A-Z0-9]',''
  $suffix=($suffix+'0000000000000000').Substring(0,16)
  $kind=if($TemplateId -eq 'hui-gl'){'OpenGL-UI'}else{'Native'}
  $target=Join-Path $script:Workspace ($suffix+'-'+$kind)
  if(Test-Path $target) { return @{ok=$false;message='Ya existe la carpeta de destino; cambia el nombre para evitar sobrescribirla.';output=$target;path=$target} }
  try {
    $null = InvokePS5HSNativeTreeModificationWithAudit -ProjectRoot $target -Backend $TemplateId -Operation 'copy-upstream-template-to-project' -PermissionKey 'allowExecuteUpstreamGenerationTools' -Policy $policy -SourceRepository $entry.repo -Action {
      CopyProjectTree $src $target
    }

    $normalization = NormalizeNativeBuildFilesWithAudit -ProjectRoot $target -Policy $policy -Backend $TemplateId -SourceRepository $entry.repo
    $patchResult = ApplyPS5HSWindowsBuildEntrypointPatch -ProjectRoot $target -Policy $policy -Backend $TemplateId -SourceRepository $entry.repo
    if ($patchResult.changed) { WriteBuildJobLog $script:ActiveBuildLogPath 'Punto de entrada build.ps1 modificado con autorización y registro SHA-256.' }
    if (!(Test-Path -LiteralPath (Join-Path $target 'build.ps1') -PathType Leaf) -and !(Test-Path -LiteralPath (Join-Path $target 'Makefile') -PathType Leaf)) {
      throw 'La plantilla no contiene build.ps1 ni Makefile; no se puede asignar un perfil de compilación seguro.'
    }
    $initializer=Join-Path $target 'tools/init-project.sh'
    $paramPath=Join-Path $target 'sce_sys/param.json'
    $targetWsl=ConvertToWslPath $target
    $toolchainsWsl=ConvertToWslPath $script:Toolchains
    $wsl=CmdInfo 'wsl.exe'
    if(!$wsl.ok) { throw 'wsl.exe no está disponible.' }
    if ((Test-Path -LiteralPath $initializer -PathType Leaf) -and (Test-Path -LiteralPath $paramPath -PathType Leaf)) {
      $initWsl=ConvertToWslPath $initializer
      $paramWsl=ConvertToWslPath $paramPath
      $cmd='cd '+(BashQuote $targetWsl)+' && export PS5HS_LOCAL_TOOLCHAINS_ONLY=1 PS5HS_TOOLCHAINS_ROOT='+(BashQuote $toolchainsWsl)+' && TITLE_ID='+(BashQuote $TitleId)+' APP_NAME='+(BashQuote $Name)+' APP_CATEGORY='+(BashQuote $Category)+' CONTENT_SUFFIX='+(BashQuote $suffix)+' bash '+(BashQuote $initWsl)+' '+(BashQuote $paramWsl)
    } else {
      $cmd='cd '+(BashQuote $targetWsl)+' && export PS5HS_LOCAL_TOOLCHAINS_ONLY=1 PS5HS_TOOLCHAINS_ROOT='+(BashQuote $toolchainsWsl)+' && make init TITLE_ID='+(BashQuote $TitleId)+' APP_NAME='+(BashQuote $Name)+' APP_CATEGORY='+(BashQuote $Category)
    }
    $initInvocation = InvokePS5HSNativeTreeModificationWithAudit -ProjectRoot $target -Backend $TemplateId -Operation 'run-upstream-native-project-initializer' -PermissionKey 'allowExecuteUpstreamGenerationTools' -Policy $policy -SourceRepository $entry.repo -Action {
      $initOutput = @(& $wsl.path -d $dist --exec bash -lc $cmd 2>&1)
      $initExit = $LASTEXITCODE
      return @{output=@($initOutput | ForEach-Object { $_.ToString() });exitCode=[int]$initExit}
    }
    $output=@($initInvocation.output)
    $exit=[int]$initInvocation.exitCode
    $log=($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    $valid=($exit -eq 0 -and (Test-Path $paramPath) -and (Test-Path (Join-Path $target 'src/main.cpp')) -and (Test-Path (Join-Path $target 'Makefile')))
    if($valid) {
      $summary=@{schema='ps5hs-native-project';template=$TemplateId;repository=$entry.repo;titleId=$TitleId;name=$Name;category=$Category;initializedAt=(Get-Date).ToString('o')}
      $null = InvokePS5HSNativeModificationWithAudit -ProjectRoot $target -Backend $TemplateId -Operation 'write-native-project-metadata' -PermissionKey 'allowExecuteUpstreamGenerationTools' -RelativePaths @('.ps5hs-project.json') -Policy $policy -SourceRepository $entry.repo -Action {
        WriteUtf8 (Join-Path $target '.ps5hs-project.json') (ConvertTo-Json -InputObject $summary -Depth 5)
      }
      return @{ok=$true;message=$(if($TemplateId -eq 'hui-gl'){'Proyecto de interfaz OpenGL creado desde ps5-homebrew-ui upstream.'}else{'Proyecto C++20 nativo creado desde ps5-native-app-boilerplate upstream.'});output=$log;path=$target;titleId=$TitleId;templateId=$TemplateId;build='not-run'}
    }
    return @{ok=$false;message="El inicializador upstream finalizó con código $exit o no dejó la estructura esperada.";output=$log;path=$target;titleId=$TitleId}
  } catch {
    return @{ok=$false;message=$_.Exception.Message;output='Fallo al copiar la plantilla o ejecutar tools/init-project.sh mediante WSL.';path=$target;titleId=$TitleId}
  }
}

function NewVulkanTitle([string]$Name,[string]$TitleId,[string]$Design,$Policy=$null) {
  if($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._-]{0,39}$'){return @{ok=$false;message='Nombre inválido. Usa 1–40 caracteres ASCII: letras, números, espacios, punto, guion o guion bajo.';output=''}}
  if(!(TestPS5HSTitleId $TitleId)){return @{ok=$false;message='TITLE_ID inválido. Usa un identificador PPSA12345 válido distinto de PPSA00000.';output=''}}
  if($Design -notin @('starter','aurora','settings','store','hud')){return @{ok=$false;message='Diseño no admitido por este asistente.';output=''}}
  $policy = AssertPS5HSNativeModificationConsent -Backend 'vulkan-template' -Policy $Policy -RequirePermissionKeys @('allowExecuteUpstreamGenerationTools')
  $entry=$script:Catalog|Where-Object id -eq 'vulkan-template'|Select-Object -First 1
  if(!$entry) { return @{ok=$false;message='No está registrada la plantilla Vulkan.';output='vulkan-template'} }
  try { $cloneResult = InstallRepo $entry; if(!$cloneResult.ok) { return @{ok=$false;message=$cloneResult.message;output=$cloneResult.path} } }
  catch { return @{ok=$false;message='No se pudo validar la plantilla Vulkan local.';output=$_.Exception.Message} }
  $repo=Join-Path $script:Toolchains $entry.folder;$generator=Join-Path $repo 'ps5/tools/new-title.py'
  if(!(Test-Path $generator)){return @{ok=$false;message='La copia local de PS5 Vulkan Template no contiene ps5/tools/new-title.py.';output=$repo}}
  $st=GetStatus;if(!$st.prerequisites.wsl){return @{ok=$false;message='No hay distribución WSL inicializada.';output='Configura WSL + Debian desde Configurar entorno y realiza su primer arranque.'}}
  if(!$st.prerequisites.wslGitPython){return @{ok=$false;message='Faltan Git o Python 3 dentro de WSL.';output='Abre la distribución WSL y ejecuta la instalación de git y python3 conforme a BUILD.md/README upstream.'}}
  $dist=[string]$st.wslDistribution
  $slug=Slug $Name;$target=Join-Path $script:Workspace ($slug+'-Vulkan')
  if(!(TestPS5HSNativeProjectDestinationAvailable -Path $target)){return @{ok=$false;message='El destino existe y contiene datos, o no es una carpeta segura. Cambia el nombre del proyecto para no sobrescribirlo.';output=$target;path=$target}}
  try {
    $repoWsl=ConvertToWslPath $repo;$targetWsl=ConvertToWslPath $target;$generatorWsl=ConvertToWslPath $generator;$toolchainsWsl=ConvertToWslPath $script:Toolchains
    $cmd='export PS5HS_LOCAL_TOOLCHAINS_ONLY=1 PS5HS_TOOLCHAINS_ROOT='+(BashQuote $toolchainsWsl)+' && python3 '+(BashQuote $generatorWsl)+' '+(BashQuote $targetWsl)+' --title-id '+(BashQuote $TitleId)+' --name '+(BashQuote $Name)
    if($Design -ne 'starter'){$cmd+=' --ui '+(BashQuote $Design)}
    $wsl=CmdInfo 'wsl.exe';if(!$wsl.ok){throw 'wsl.exe no está disponible.'}
    $generation = InvokePS5HSNativeTreeModificationWithAudit -ProjectRoot $target -Backend 'vulkan-template' -Operation 'run-vulkan-upstream-title-generator' -PermissionKey 'allowExecuteUpstreamGenerationTools' -Policy $policy -SourceRepository $entry.repo -Action {
      $generatorOutput = @(& $wsl.path -d $dist --exec bash -lc $cmd 2>&1)
      $generatorExit = $LASTEXITCODE
      return @{output=@($generatorOutput | ForEach-Object { $_.ToString() });exitCode=[int]$generatorExit}
    }
    $output=@($generation.output);$exit=[int]$generation.exitCode;$log=($output|ForEach-Object{$_.ToString()}) -join "`r`n"
    $valid=($exit -eq 0 -and (Test-Path (Join-Path $target 'README.md')) -and (Test-Path (Join-Path $target 'ps5')))
    if($valid){
      $summary=@{schema='ps5hs-native-project';template='vulkan-template';repository=$entry.repo;titleId=$TitleId;name=$Name;category='game';design=$Design;initializedAt=(Get-Date).ToString('o')}
      $null = InvokePS5HSNativeModificationWithAudit -ProjectRoot $target -Backend 'vulkan-template' -Operation 'write-vulkan-project-metadata' -PermissionKey 'allowExecuteUpstreamGenerationTools' -RelativePaths @('.ps5hs-project.json') -Policy $policy -SourceRepository $entry.repo -Action {
        WriteUtf8 (Join-Path $target '.ps5hs-project.json') (ConvertTo-Json -InputObject $summary -Depth 5)
      }
      return @{ok=$true;message='Proyecto C++ nativo generado por el generador upstream PS5 Vulkan Template. Todavía no se ha compilado.';output=$log;path=$target;titleId=$TitleId;design=$Design;templateId='vulkan-template';build='not-run'}
    }
    return @{ok=$false;message="El generador upstream terminó con código $exit o no dejó la estructura esperada.";output=$log;path=$target;titleId=$TitleId}
  } catch { return @{ok=$false;message=$_.Exception.Message;output='Error al preparar la ruta o invocar WSL.';path=$target} }
}

function GetProjectRemote([string]$ProjectRoot) {
  $gitConfig = Join-Path $ProjectRoot '.git\config'
  if (!(Test-Path -LiteralPath $gitConfig -PathType Leaf)) { return '' }
  try {
    $text = Get-Content -LiteralPath $gitConfig -Raw
    $match = [regex]::Match($text,'(?im)^\s*url\s*=\s*(.+?)\s*$')
    if (!$match.Success) { return '' }
    $url = $match.Groups[1].Value.Trim()
    $url = $url -replace '^(https?://github\.com/|git@github\.com:|ssh://git@github\.com/)',''
    $url = $url -replace '\.git$',''
    return $url.Trim('/').ToLowerInvariant()
  } catch { return '' }
}
function GetProjectTitleId([string]$ProjectRoot) {
  foreach ($relative in @('sce_sys/param.json','ps5/sce_sys/param.json','param.json')) {
    $candidate = Join-Path $ProjectRoot ($relative.Replace('/',[IO.Path]::DirectorySeparatorChar))
    if (!(Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
    try {
      $raw = Get-Content -LiteralPath $candidate -Raw
      $match = [regex]::Match($raw,'\bPPSA\d{5}\b')
      if ($match.Success -and (TestPS5HSTitleId $match.Value)) { return $match.Value.ToUpperInvariant() }
    } catch { continue }
  }
  return ''
}
function GetProjectProfile([string]$ProjectRoot) {
  $name = Split-Path -Leaf $ProjectRoot
  $remote = GetProjectRemote $ProjectRoot
  $markerPath = Join-Path $ProjectRoot '.ps5hs-project.json'
  $meta = $null
  if (Test-Path -LiteralPath $markerPath -PathType Leaf) {
    try { $meta = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json } catch { $meta = $null }
  }
  $hasMakefile = Test-Path -LiteralPath (Join-Path $ProjectRoot 'Makefile') -PathType Leaf
  $hasParam = Test-Path -LiteralPath (Join-Path $ProjectRoot 'sce_sys/param.json') -PathType Leaf
  if (!$hasParam -and $meta -and $meta.schema -eq 'ps5hs-native-project' -and [string]$meta.template -eq 'ps5link' -and (TestPS5HSTitleId ([string]$meta.titleId))) {
    $ps5LinkParam = Join-Path $ProjectRoot ('dist\' + ([string]$meta.titleId).ToUpperInvariant() + '\sce_sys\param.json')
    $hasParam = Test-Path -LiteralPath $ps5LinkParam -PathType Leaf
  }
  $hasMainCpp = Test-Path -LiteralPath (Join-Path $ProjectRoot 'src/main.cpp') -PathType Leaf
  $hasLegacyInit = Test-Path -LiteralPath (Join-Path $ProjectRoot 'tools/init-project.sh') -PathType Leaf
  $makeText = ''
  if ($hasMakefile) { try { $makeText = Get-Content -LiteralPath (Join-Path $ProjectRoot 'Makefile') -Raw } catch { $makeText = '' } }
  $hasMakeInit = [bool]($makeText -match '(?m)^\s*init\s*:')

  $hasVulkanGenerator = Test-Path -LiteralPath (Join-Path $ProjectRoot 'ps5/tools/new-title.py') -PathType Leaf
  $hasVulkanBuild = Test-Path -LiteralPath (Join-Path $ProjectRoot 'ps5/tools/build.sh') -PathType Leaf
  $hasUiFontTool = Test-Path -LiteralPath (Join-Path $ProjectRoot 'tools/bake-fonts.sh') -PathType Leaf
  $template = ''
  if ($meta -and $meta.schema -eq 'ps5hs-native-project' -and [string]$meta.template -in @('nativecpp','hui-gl','vulkan-template','ps5link')) {
    $template = [string]$meta.template
  } elseif ($hasVulkanBuild -and $hasParam) {
    $template = 'vulkan-template'
  } elseif ($hasVulkanGenerator -and !$hasVulkanBuild) {
    $template = 'vulkan-template-source'
  } elseif ($remote -eq 'blackbearreloaded/ps5-homebrew-ui' -or ($hasMakefile -and $hasUiFontTool)) {
    $template = 'hui-gl'
  } elseif ($remote -eq 'blackbearreloaded/ps5-native-app-boilerplate' -or ($hasMakefile -and $hasMainCpp -and ($hasLegacyInit -or $hasMakeInit))) {
    $template = 'nativecpp'
  }
  $titleId = ''
  if ($meta -and (TestPS5HSTitleId ([string]$meta.titleId))) { $titleId = ([string]$meta.titleId).ToUpperInvariant() }
  if (!$titleId) { $titleId = GetProjectTitleId $ProjectRoot }
  $initialized = ($hasParam -and (TestPS5HSTitleId $titleId))
  $typeLabel = ''
  $buildSystem = 'Upstream'
  $buildable = $false
  $buildReason = ''
  $dependencies = @()
  switch ($template) {
    'nativecpp' {
      $typeLabel = 'Título nativo C/C++ · Native App Boilerplate'
      $buildSystem = 'Make / LLVM / herramientas upstream'
      $buildable = ($hasMakefile -and $hasMainCpp)
      if (!$initialized) { $buildReason = 'La plantilla se reconoce, pero requiere inicializar TITLE_ID y nombre antes de compilar.' }
    }
    'hui-gl' {
      $typeLabel = 'Aplicación UI OpenGL · PS5 Homebrew UI'
      $buildSystem = 'Make / PS5 OpenGL SDK'
      $buildable = ($hasMakefile -and ($hasMainCpp -or $hasUiFontTool -or $remote -eq 'blackbearreloaded/ps5-homebrew-ui'))
      $dependencies = @('nativecpp','opengl')
      if (!$initialized) { $buildReason = 'La aplicación UI requiere TITLE_ID válido y dependencias OpenGL/Native App Boilerplate.' }
    }
    'vulkan-template' {
      $typeLabel = 'Título nativo Vulkan/RADV'
      $buildSystem = 'Scripts upstream / CMake / Ninja'
      $buildable = ($hasVulkanBuild -and $hasParam)
      $dependencies = @('vulkan-radv','vulkan-sdk','ps5-mesa')
    }
    'vulkan-template-source' {
      $typeLabel = 'Plantilla Vulkan upstream (todavía no es un título)'
      $buildSystem = 'Generador upstream new-title.py'
      $buildReason = 'Este directorio es una plantilla; primero crea un título con el generador upstream antes de compilar.'
    }
    'ps5link' {
      $typeLabel = 'Título nativo AGC · ps5link'
      $buildSystem = 'PS5 Payload SDK / ps5link-sdk / SharpProspero'
      $buildable = $false
      $buildReason = if ($hasParam) { 'La presentación se puede editar aquí. Para recompilar el motor visual, abre el proyecto en el IDE y pulsa Compilar.' } else { 'No se encuentra dist/<TITLE_ID>/sce_sys/param.json; vuelve a compilar el proyecto visual desde el IDE.' }
    }
  }
  if (!$template) {
    $known = $script:Catalog | Where-Object { $_.repo -and ([string]$_.repo).ToLowerInvariant() -eq $remote } | Select-Object -First 1
    if ($known) {
      $typeLabel = [string]$known.role + ' · proyecto upstream'
      $buildReason = 'Repositorio reconocido, pero no dispone de un perfil de compilación de título validado en Homebrew Studio. Usa las instrucciones upstream específicas.'
    } elseif (Test-Path -LiteralPath (Join-Path $ProjectRoot 'CMakeLists.txt') -PathType Leaf) {
      $typeLabel = 'Proyecto CMake externo'
      $buildSystem = 'CMake (perfil PS5 no confirmado)'
      $buildReason = 'Se detectó CMake, pero no se infiere una configuración de cross-compilación PS5. Se requiere un perfil explícito del proyecto.'
    } elseif ($hasMakefile) {
      $typeLabel = 'Proyecto Make externo'
      $buildSystem = 'Make (perfil PS5 no confirmado)'
      $buildReason = 'Se detectó un Makefile, pero no se puede asumir que produzca un título PS5 válido.'
    } elseif (Test-Path -LiteralPath (Join-Path $ProjectRoot 'build.ps1') -PathType Leaf) {
      $typeLabel = 'Proyecto con build.ps1 upstream'
      $buildSystem = 'PowerShell / upstream'
      $buildReason = 'Se detectó build.ps1; falta un perfil conocido que identifique sus dependencias y artefactos.'
    } elseif ($remote) {
      $typeLabel = 'Repositorio GitHub sin perfil reconocido'
      $buildReason = 'Se detectó el origen Git, pero no una receta de compilación segura y conocida.'
    } else {
      $typeLabel = 'Proyecto local sin clasificar'
      $buildReason = 'No se han encontrado marcadores de un título nativo compatible.'
    }
  }
  if (!$buildable -and !$buildReason) { $buildReason = 'Faltan marcadores estructurales requeridos por el perfil de compilación.' }
  $supportsClean = $false
  if ($hasMakefile) {
    try { $supportsClean = [bool]((Get-Content -LiteralPath (Join-Path $ProjectRoot 'Makefile') -Raw) -match '(?m)^\s*clean\s*:') } catch { $supportsClean = $false }
  }
  $isRelevant = ((Test-Path -LiteralPath $markerPath -PathType Leaf) -or $remote -or $hasMakefile -or (Test-Path -LiteralPath (Join-Path $ProjectRoot 'CMakeLists.txt') -PathType Leaf) -or $hasVulkanGenerator -or (Test-Path -LiteralPath (Join-Path $ProjectRoot 'build.ps1') -PathType Leaf))
  return @{
    name = $(if ($meta -and $meta.name) { [string]$meta.name } else { $name })
    nativeModifications = @{}
    path = $ProjectRoot
    repository = $(if ($meta -and $meta.repository) { [string]$meta.repository } else { $remote })
    template = $template
    typeLabel = $typeLabel
    buildSystem = $buildSystem
    buildable = [bool]$buildable
    buildReason = $buildReason
    titleId = $titleId
    design = $(if ($meta) { [string]$meta.design } else { '' })
    generatedFromStudio = [bool]($meta -and $meta.generatedFromStudio)
    initialized = [bool]$initialized
    needsInit = [bool]($template -in @('nativecpp','hui-gl') -and !$initialized)
    supportsClean = [bool]$supportsClean
    dependencies = @($dependencies)
    recognized = [bool]($template -in @('nativecpp','hui-gl','vulkan-template','ps5link'))
    relevant = [bool]$isRelevant
  }
}
function GetMissingProjectDependencies($Profile) {
  $missing = @()
  foreach ($dependencyId in @($Profile.dependencies)) {
    $entry = $script:Catalog | Where-Object id -eq ([string]$dependencyId) | Select-Object -First 1
    if (!$entry) { $missing += [string]$dependencyId; continue }
    $dependencyPath = Join-Path $script:Toolchains $entry.folder
    $localSource = GetPS5HSBundledToolchainInfo $entry $dependencyPath
    if (!$localSource.bundled -or !$localSource.installed) {
      $reason=[string]$localSource.reason
      if(!$reason){$reason='snapshot local ausente o no válido'}
      $missing += ([string]$entry.name+' ('+$reason+')')
      continue
    }
    if ($dependencyId -eq 'opengl' -and !(Test-Path -LiteralPath (Join-Path $dependencyPath 'build/sdk/ps5-opengl-gl46') -PathType Container)) {
      $missing += 'PS5 OpenGL SDK (no está compilado en la copia local; no se descargará automáticamente)'
    }
  }
  return ,@($missing)
}
function GetGeneratedProjects {
  $items = @()
  foreach ($dir in (Get-ChildItem -LiteralPath $script:Workspace -Directory -ErrorAction SilentlyContinue)) {
    if (($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
    $profile = GetProjectProfile $dir.FullName
    if (!$profile.relevant) { continue }
    $artifact = ''
    $built = $false
    $eboots = @(GetProjectEbootFolders $dir.FullName)
    foreach ($eboot in $eboots) {
      $ebootFolder = Split-Path -Parent $eboot.FullName
      $paramPath = Join-Path $ebootFolder 'sce_sys\param.json'
      if (!(Test-Path -LiteralPath $paramPath -PathType Leaf)) { $paramPath = Join-Path $dir.FullName 'sce_sys\param.json' }
      if (!(Test-Path -LiteralPath $paramPath -PathType Leaf)) { $paramPath = Join-Path $dir.FullName 'ps5\sce_sys\param.json' }
      if (Test-Path -LiteralPath $paramPath -PathType Leaf) { $artifact = $eboot.FullName; $built = $true; break }
    }
    $items += @{
      name = [string]$profile.name
      titleId = [string]$profile.titleId
      templateId = [string]$profile.template
      typeLabel = [string]$profile.typeLabel
      buildSystem = [string]$profile.buildSystem
      buildable = [bool]$profile.buildable
      buildReason = [string]$profile.buildReason
      needsInit = [bool]$profile.needsInit
      supportsClean = [bool]$profile.supportsClean
      missingDependencies = @(GetMissingProjectDependencies $profile)
      visualBackend = [string]$profile.template
      generatedFromStudio = [bool]$profile.generatedFromStudio
      nativeModifications = $profile.nativeModifications
      design = [string]$profile.design
      path = $dir.FullName
      repository = [string]$profile.repository
      artifact = $artifact
      built = $built
      presentation = (GetNativePresentationState $dir.FullName)
      initializedAt = ''
    }
  }
  return ,@($items | Sort-Object name)
}

function GetPS5HSSceSysPath([string]$ProjectRoot) {
  $rootSceSys = Join-Path $ProjectRoot 'sce_sys'
  if (Test-Path -LiteralPath $rootSceSys -PathType Container) { return $rootSceSys }
  $markerPath = Join-Path $ProjectRoot '.ps5hs-project.json'
  if (Test-Path -LiteralPath $markerPath -PathType Leaf) {
    try {
      $markerItem = Get-Item -LiteralPath $markerPath -Force
      if (($markerItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'El manifiesto del proyecto es un enlace.' }
      $meta = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
      if ($meta.schema -eq 'ps5hs-native-project' -and [string]$meta.template -eq 'ps5link' -and (TestPS5HSTitleId ([string]$meta.titleId))) {
        $ps5LinkSceSys = Join-Path $ProjectRoot ('dist\' + ([string]$meta.titleId).ToUpperInvariant() + '\sce_sys')
        $null = AssertPS5HSNativePathNoReparsePoints -Path $ps5LinkSceSys
        return $ps5LinkSceSys
      }
    } catch { throw ('No se pudo resolver con seguridad sce_sys del título ps5link: ' + $_.Exception.Message) }
  }
  $vulkanBuildScript = Join-Path $ProjectRoot 'ps5\tools\build.sh'
  $vulkanSceSys = Join-Path $ProjectRoot 'ps5\sce_sys'
  if ((Test-Path -LiteralPath $vulkanBuildScript -PathType Leaf) -and (Test-Path -LiteralPath $vulkanSceSys -PathType Container)) {
    return $vulkanSceSys
  }
  return $rootSceSys
}

function GetNativePresentationState([string]$ProjectRoot) {
  $sceSys = GetPS5HSSceSysPath $ProjectRoot
  $paramPath = Join-Path $sceSys 'param.json'
  $assetScript = Join-Path $ProjectRoot 'tools\prepare-assets.ps1'
  if (!(Test-Path -LiteralPath $assetScript -PathType Leaf)) {
    $assetScript = Join-Path $script:Toolchains 'ps5-native-app-boilerplate\tools\prepare-assets.ps1'
  }
  $texconv = CmdInfo 'texconv.exe'
  if (!$texconv.ok) { $texconv = CmdInfo 'texconv' }
  $at9 = Join-Path $script:Toolchains 'ps5-at9-converter\bin\ps5-at9-converter'
  $at9Available = $false
  if (Test-Path -LiteralPath $at9 -PathType Leaf) {
    try {
      $at9Item = Get-Item -LiteralPath $at9 -Force
      $at9Available = (($at9Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and $at9Item.Length -gt 1024)
    } catch { $at9Available = $false }
  }
  return @{
    editable = [bool](Test-Path -LiteralPath $paramPath -PathType Leaf)
    icon = [bool](Test-Path -LiteralPath (Join-Path $sceSys 'icon0.png') -PathType Leaf)
    selectionBackground = [bool](Test-Path -LiteralPath (Join-Path $sceSys 'pic0.dds') -PathType Leaf)
    launchBackground = [bool](Test-Path -LiteralPath (Join-Path $sceSys 'pic1.dds') -PathType Leaf)
    music = [bool](Test-Path -LiteralPath (Join-Path $sceSys 'snd0.at9') -PathType Leaf)
    conversionScript = [bool](Test-Path -LiteralPath $assetScript -PathType Leaf)
    texconv = [bool]$texconv.ok
    at9Encoder = [bool]$at9Available
  }
}

function ResolveNativePresentationProject([string]$RequestedPath) {
  if ([string]::IsNullOrWhiteSpace($RequestedPath)) { throw 'La ruta del proyecto está vacía.' }
  $workspaceRoot = [IO.Path]::GetFullPath($script:Workspace).TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
  $prefix = $workspaceRoot + [IO.Path]::DirectorySeparatorChar
  $full = [IO.Path]::GetFullPath($RequestedPath)
  if (!$full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Solo se pueden editar recursos de proyectos dentro del workspace PS5 Homebrew Studio.'
  }
  if (!(Test-Path -LiteralPath $full -PathType Container)) { throw 'No se encuentra la carpeta del proyecto.' }
  $projectItem = Get-Item -LiteralPath $full -Force
  if (($projectItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'No se permite editar recursos a través de una carpeta de proyecto enlazada.'
  }
  $sceSys = GetPS5HSSceSysPath $full
  if (!(Test-Path -LiteralPath $sceSys -PathType Container)) { throw 'Este proyecto no contiene sce_sys/ ni ps5/sce_sys/.' }
  $sceItem = Get-Item -LiteralPath $sceSys -Force
  if (($sceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'No se permite editar recursos a través de un enlace sce_sys.'
  }
  $paramPath = Join-Path $sceSys 'param.json'
  if (!(Test-Path -LiteralPath $paramPath -PathType Leaf)) {
    throw 'Falta sce_sys/param.json. Inicializa primero el título PS5 antes de personalizar su presentación.'
  }
  $paramItem = Get-Item -LiteralPath $paramPath -Force
  if (($paramItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'No se leerá ni modificará sce_sys/param.json a través de un enlace.'
  }
  try { $null = Get-Content -LiteralPath $paramPath -Raw | ConvertFrom-Json }
  catch { throw 'sce_sys/param.json no es JSON válido; no se han cambiado recursos.' }
  return @{ path = $full; sceSys = $sceSys }
}

function WriteNativePresentationUpload($Upload, [string]$Prefix, [string]$InputDirectory, [string[]]$AllowedExtensions, [long]$MaxBytes) {
  if ($null -eq $Upload) { return '' }
  $name = [IO.Path]::GetFileName([string]$Upload.name)
  $extension = [IO.Path]::GetExtension($name).ToLowerInvariant()
  if (!$name -or $extension -notin $AllowedExtensions) {
    throw "${Prefix}: formato de archivo no permitido. Extensiones aceptadas: $($AllowedExtensions -join ', ')."
  }
  $encoded = [string]$Upload.data
  if ([string]::IsNullOrWhiteSpace($encoded)) { throw "${Prefix}: el archivo está vacío o no se pudo leer." }
  $encodedLimit = [long][Math]::Ceiling($MaxBytes * 4.0 / 3.0) + 8
  if ($encoded.Length -gt $encodedLimit) { throw "${Prefix}: el archivo supera el límite de $([Math]::Round($MaxBytes / 1MB)) MiB." }
  try { $bytes = [Convert]::FromBase64String($encoded) }
  catch { throw "${Prefix}: los datos del archivo no son Base64 válido." }
  if ($bytes.Length -lt 1 -or $bytes.LongLength -gt $MaxBytes) { throw "${Prefix}: tamaño de archivo no válido o superior al límite de $([Math]::Round($MaxBytes / 1MB)) MiB." }
  $destination = Join-Path $InputDirectory ($Prefix + $extension)
  [IO.File]::WriteAllBytes($destination, $bytes)
  return $destination
}

function UpdateNativePresentationAssets($Body) {
  $project = ResolveNativePresentationProject ([string]$Body.path)
  $profile = GetProjectProfile $project.path
  $backend = [string]$profile.template
  if ($backend -notin @('nativecpp','hui-gl','vulkan-template','ps5link')) { throw 'No se puede editar la presentación: el tipo de proyecto no tiene un perfil nativo admitido.' }
  $policy = AssertPS5HSNativeModificationConsent -Backend $backend -Policy $Body.nativeModifications -RequirePermissionKeys @('allowExecuteUpstreamAssetTools')
  $null = AssertPS5HSNativeModificationManifestWritable -ProjectRoot $project.path
  $hasIcon = $null -ne $Body.icon
  $hasSelectionBackground = $null -ne $Body.selectionBackground
  $hasLaunchBackground = $null -ne $Body.launchBackground
  $hasAudio = $null -ne $Body.audio
  if (!$hasIcon -and !$hasSelectionBackground -and !$hasLaunchBackground -and !$hasAudio) { throw 'Selecciona al menos un recurso para sustituir.' }
  $sceSysRelative = $project.sceSys.Substring($project.path.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)).Length).TrimStart([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)).Replace([IO.Path]::DirectorySeparatorChar,'/')
  if (!$sceSysRelative) { throw 'No se pudo resolver la ruta de sce_sys para auditar los recursos.' }
  $auditRelativePaths = @()
  if ($hasIcon) { $auditRelativePaths += ($sceSysRelative + '/icon0.png') }
  if ($hasSelectionBackground) { $auditRelativePaths += @(($sceSysRelative + '/pic0.dds'),($sceSysRelative + '/background-source.png')) }
  if ($hasLaunchBackground) { $auditRelativePaths += @(($sceSysRelative + '/pic1.dds'),($sceSysRelative + '/launch-background-source.png')) }
  if ($hasAudio) { $auditRelativePaths += @(($sceSysRelative + '/snd0.at9'),($sceSysRelative + '/param.json')) }
  $auditBeforeHashes = GetPS5HSNativeFileHashes -ProjectRoot $project.path -RelativePaths $auditRelativePaths
  $state = GetNativePresentationState $project.path
  if (!$state.conversionScript) {
    throw 'No se encuentra tools/prepare-assets.ps1 en el proyecto ni en la fuente Native App Boilerplate. Instala/actualiza esa fuente desde el panel SDKs e inténtalo de nuevo.'
  }
  if (!$hasIcon -and !$state.icon) {
    throw 'El título todavía no tiene sce_sys/icon0.png. Selecciona un icono para crear el conjunto de presentación inicial.'
  }
  if (($hasSelectionBackground -or $hasLaunchBackground) -and (!$state.selectionBackground -or !$state.launchBackground)) {
    if (!$hasSelectionBackground -or !$hasLaunchBackground) {
      throw 'Este título aún no tiene ambos fondos. Selecciona a la vez el fondo de selección y el de lanzamiento para crear el par pic0.dds/pic1.dds.'
    }
  }

  $tempRoot = Join-Path $script:Runtime ('presentation-' + [Guid]::NewGuid().ToString('N'))
  $inputDir = Join-Path $tempRoot 'inputs'
  $stageDir = Join-Path $tempRoot 'sce_sys'
  $backupDir = Join-Path $tempRoot 'backup'
  New-Item -ItemType Directory -Force -Path $inputDir,$stageDir,$backupDir | Out-Null
  $changedFiles = @()
  $preserveTempRoot = $false
  try {
    # Copy only assets consumed or updated by the upstream preparation script.
    # Never recurse through unrelated project files or user-controlled links.
    foreach ($filename in @('param.json','icon0.png','pic0.dds','pic1.dds','snd0.at9','background-source.png','launch-background-source.png')) {
      $source = Join-Path $project.sceSys $filename
      if (!(Test-Path -LiteralPath $source -PathType Leaf)) { continue }
      $sourceItem = Get-Item -LiteralPath $source -Force
      if (($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "No se prepararán recursos a través del archivo enlazado $filename."
      }
      Copy-Item -LiteralPath $source -Destination (Join-Path $stageDir $filename) -Force
    }

    $imageExtensions = @('.png','.jpg','.jpeg','.bmp','.tif','.tiff','.dds')
    $audioExtensions = @('.at9','.mp3','.wav','.flac','.aiff','.aif','.aifc')
    $iconPath = ''
    $selectionBackgroundPath = ''
    $launchBackgroundPath = ''
    $audioPath = ''
    $audioConversionOutput = @()
    if ($hasIcon) {
      $iconPath = WriteNativePresentationUpload $Body.icon 'icon' $inputDir $imageExtensions (10MB)
    }
    if ($hasSelectionBackground) {
      $selectionBackgroundPath = WriteNativePresentationUpload $Body.selectionBackground 'selection-background' $inputDir $imageExtensions (24MB)
    }
    if ($hasLaunchBackground) {
      $launchBackgroundPath = WriteNativePresentationUpload $Body.launchBackground 'launch-background' $inputDir $imageExtensions (24MB)
    }
    if ($hasAudio) {
      $audioPath = WriteNativePresentationUpload $Body.audio 'audio' $inputDir $audioExtensions (24MB)
      if ([IO.Path]::GetExtension($audioPath) -ine '.at9') {
        $converter = Join-Path $script:Toolchains 'ps5-at9-converter\bin\ps5-at9-converter'
        try { $null = AssertPS5HSNativePathNoReparsePoints -Path $converter }
        catch { throw ('No se puede ejecutar el codificador ATRAC9 local: ' + $_.Exception.Message) }
        if (!(Test-Path -LiteralPath $converter -PathType Leaf) -or (Get-Item -LiteralPath $converter -Force).Length -lt 1024) {
          throw 'Falta toolchains/ps5-at9-converter/bin/ps5-at9-converter. El audio importado se conserva, pero no se escribirá un snd0.at9 incompleto.'
        }
        $status = GetStatus
        if (!$status.prerequisites.wsl -or [string]::IsNullOrWhiteSpace([string]$status.wslDistribution)) {
          throw 'El codificador ATRAC9 es offline, pero necesita la distribución WSL incluida en el entorno del IDE.'
        }
        $wsl = CmdInfo 'wsl.exe'
        if (!$wsl.ok) { throw 'No se encuentra wsl.exe para ejecutar el codificador ATRAC9 incluido.' }
        $encodedAudio = Join-Path $inputDir 'audio-converted.at9'
        $converterWsl = ConvertToWslPath $converter
        $audioInputWsl = ConvertToWslPath $audioPath
        $audioOutputWsl = ConvertToWslPath $encodedAudio
        $encodeOutput = @(& $wsl.path -d ([string]$status.wslDistribution) --exec $converterWsl --input $audioInputWsl --output $audioOutputWsl 2>&1 | ForEach-Object { $_.ToString() })
        $encodeExit = $LASTEXITCODE
        if ($encodeExit -ne 0 -or !(Test-Path -LiteralPath $encodedAudio -PathType Leaf)) {
          throw ('El codificador ATRAC9 incluido no pudo convertir el audio.' + [Environment]::NewLine + (@($encodeOutput) -join [Environment]::NewLine))
        }
        $encodedItem = Get-Item -LiteralPath $encodedAudio -Force
        if (($encodedItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $encodedItem.Length -gt 2MB) {
          throw 'La conversión ATRAC9 produjo una salida enlazada o mayor que el máximo de 2 MiB para snd0.at9.'
        }
        $audioPath = $encodedAudio
        $audioConversionOutput = @('Codificador ATRAC9 offline incluido: ' + (@($encodeOutput) -join ' '))
      }
    }

    $helper = Join-Path $project.path 'tools\prepare-assets.ps1'
    if (!(Test-Path -LiteralPath $helper -PathType Leaf)) {
      $helper = Join-Path $script:Toolchains 'ps5-native-app-boilerplate\tools\prepare-assets.ps1'
    }
    $helperItem = Get-Item -LiteralPath $helper -Force
    if (($helperItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw 'No se ejecutará tools/prepare-assets.ps1 a través de un enlace o punto de reanálisis.'
    }
    $arguments = @{ OutputDirectory = $stageDir }
    if ($iconPath) { $arguments['Icon'] = $iconPath }
    if ($selectionBackgroundPath) { $arguments['SelectionBackground'] = $selectionBackgroundPath }
    if ($launchBackgroundPath) { $arguments['LaunchBackground'] = $launchBackgroundPath }
    if ($audioPath) { $arguments['Audio'] = $audioPath }
    $toolOutput = @($audioConversionOutput)
    try {
      $helperOutput = @(& $helper @arguments 2>&1 | ForEach-Object { [string]$_ })
      $toolOutput += $helperOutput
    }
    catch {
      $detail = (@($toolOutput) + @([string]$_.Exception.Message) | Where-Object { $_ }) -join "`n"
      throw ('No se pudieron preparar los recursos. Comprueba las herramientas indicadas en el manual.' + "`n" + $detail)
    }

    $commitNames = @()
    if ($hasIcon) { $commitNames += 'icon0.png' }
    if ($hasSelectionBackground) { $commitNames += @('pic0.dds','background-source.png') }
    if ($hasLaunchBackground) { $commitNames += @('pic1.dds','launch-background-source.png') }
    if ($hasAudio) { $commitNames += @('snd0.at9','param.json') }
    foreach ($filename in $commitNames) {
      $source = Join-Path $stageDir $filename
      if (!(Test-Path -LiteralPath $source -PathType Leaf)) { throw "El proceso de conversión no produjo el archivo esperado: $filename" }
      $destination = Join-Path $project.sceSys $filename
      if (Test-Path -LiteralPath $destination) {
        $existing = Get-Item -LiteralPath $destination -Force
        if (($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
          throw "No se sobrescribirá el archivo enlazado $filename."
        }
        [IO.File]::Copy($destination, (Join-Path $backupDir $filename), $true)
      }
      $changedFiles += $filename
      [IO.File]::Copy($source, $destination, $true)
    }
    $finalState = GetNativePresentationState $project.path
    $summary = @()
    if ($hasIcon) { $summary += 'icono 512×512 PNG' }
    if ($hasSelectionBackground) { $summary += 'fondo de selección 3840×2160 BC7 DDS' }
    if ($hasLaunchBackground) { $summary += 'fondo de lanzamiento 3840×2160 BC7 DDS' }
    if ($hasAudio) { $summary += 'música de selección ATRAC9' }
    $auditAfterHashes = GetPS5HSNativeFileHashes -ProjectRoot $project.path -RelativePaths $auditRelativePaths
    $auditChangedPaths = @($auditRelativePaths | Where-Object { $auditBeforeHashes[$_] -cne $auditAfterHashes[$_] })
    if ($auditChangedPaths.Count -gt 0) {
      $null = AddPS5HSNativeModificationRecord -ProjectRoot $project.path -Backend $backend -Operation 'update-native-presentation-assets' -PermissionKey 'allowExecuteUpstreamAssetTools' -RelativePaths $auditChangedPaths -BeforeHashes $auditBeforeHashes -Policy $policy -SourceRepository 'PS5 Native App Boilerplate · tools/prepare-assets.ps1'
    }
    return @{
      ok = $true
      message = 'Presentación actualizada: ' + ($summary -join ', ') + '.'
      output = (@($toolOutput) -join "`n")
      path = $project.path
      presentation = $finalState
    }
  }
  catch {
    $originalFailure = $_
    $rollbackErrors = [System.Collections.Generic.List[string]]::new()
    for ($index = $changedFiles.Count - 1; $index -ge 0; $index--) {
      $filename = [string]$changedFiles[$index]
      $destination = Join-Path $project.sceSys $filename
      $backup = Join-Path $backupDir $filename
      try {
        if (Test-Path -LiteralPath $backup -PathType Leaf) { [IO.File]::Copy($backup, $destination, $true) }
        elseif (Test-Path -LiteralPath $destination -PathType Leaf) { Remove-Item -LiteralPath $destination -Force -ErrorAction Stop }
      } catch {
        $rollbackErrors.Add(($filename + ': ' + $_.Exception.Message))
      }
    }
    if ($rollbackErrors.Count -gt 0) {
      $preserveTempRoot = $true
      $detail = $rollbackErrors -join [Environment]::NewLine
      throw ('Falló la actualización de presentación: ' + $originalFailure.Exception.Message + [Environment]::NewLine +
        'ATENCIÓN: no se pudieron restaurar todos los archivos. Las copias de seguridad se conservan en: ' + $tempRoot +
        [Environment]::NewLine + 'Archivos pendientes de restaurar:' + [Environment]::NewLine + $detail)
    }
    throw
  }
  finally {
    if (!$preserveTempRoot -and (Test-Path -LiteralPath $tempRoot -PathType Container)) {
      try { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction Stop }
      catch { Write-Warning ('No se pudo eliminar la carpeta temporal de presentación: ' + $tempRoot + '. Puede borrarse manualmente tras comprobar sus copias de seguridad.') }
    }
  }
}

function EnsureVulkanBuildSupport([string]$VulkanDir) {
  # PS5_Vulkan's current Makefile/build.sh still refers to these shared host-build
  # helpers, but some published revisions omit them from tools/. Restore the actual
  # upstream scripts from the project's companion native boilerplate, never stubs.
  $nativeEntry = $script:Catalog | Where-Object id -eq 'nativecpp' | Select-Object -First 1
  if (!$nativeEntry) { throw 'No está registrada la fuente upstream de las herramientas nativas compartidas.' }
  $nativeInstall = InstallRepo $nativeEntry
  if (!$nativeInstall.ok) { throw "No se pudo obtener el repositorio de herramientas nativas: $($nativeInstall.message)" }
  $nativeRoot = Join-Path $script:Toolchains $nativeEntry.folder
  $provenance = @()
  foreach ($relative in @('tools/ninja-build.sh','tools/build-host-tools.sh')) {
    $destination = Join-Path $VulkanDir ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
    if (Test-Path $destination -PathType Leaf) { continue }
    $source = Join-Path $nativeRoot ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
    if (!(Test-Path $source -PathType Leaf)) { throw "Falta el helper $relative tanto en PS5_Vulkan como en su boilerplate upstream." }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination
    $digest = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    $provenance += @{path=$relative;sourceRepository=$nativeEntry.repo;sourcePath=$relative;sha256=$digest;action='restored-missing-upstream-build-helper'}
  }
  if ($provenance.Count -gt 0) {
    $manifestPath = Join-Path $VulkanDir '.ps5hs-compatibility.json'
    $prior = @()
    if (Test-Path $manifestPath) { try { $prior = @((Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json).restoredFiles) } catch { $prior = @() } }
    WriteUtf8 $manifestPath (ConvertTo-Json -InputObject @{notice='Compatibility overlay: restores absent shared build scripts from their upstream boilerplate source; no generated stubs.';sourceRepository=$nativeEntry.repo;restoredFiles=@($prior + $provenance);updatedAt=(Get-Date).ToString('o')} -Depth 8)
  }
  return @($provenance)
}

function GetIntegrationConfig {
  $stored = @{}
  $configPath = Join-Path $script:Runtime 'integrations.json'
  if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    try { $raw = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json; $stored.pythonExe = [string]$raw.pythonExe; $stored.ultraPackCli = [string]$raw.ultraPackCli } catch { $stored = @{} }
  }
  $python = [string]$stored.pythonExe
  if (!$python -or !(Test-Path -LiteralPath $python -PathType Leaf)) {
    $python = ''
    $venv = Join-Path (Join-Path $script:Toolchains 'ps5-ultrapack') '.venv\Scripts\python.exe'
    if (Test-Path -LiteralPath $venv -PathType Leaf) { $python = $venv }
  }
  if (!$python -or !(Test-Path -LiteralPath $python -PathType Leaf)) {
    $python = ''
    foreach ($name in @('python.exe','python3.exe','python','python3')) { $found = CmdInfo $name; if ($found.ok -and $found.path -and (Test-Path -LiteralPath $found.path -PathType Leaf)) { $python = [string]$found.path; break } }
  }
  $cli = [string]$stored.ultraPackCli
  if (!$cli -or !(Test-Path -LiteralPath $cli -PathType Leaf)) {
    $candidate = Join-Path $script:Toolchains 'ps5-ultrapack\backend\cli.py'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $cli = $candidate } else { $cli = '' }
  }
  return @{pythonExe=$python;ultraPackCli=$cli;pythonReady=[bool]($python -and (Test-Path -LiteralPath $python -PathType Leaf));ultraPackReady=[bool]($cli -and (Test-Path -LiteralPath $cli -PathType Leaf));ultraPackRepo='https://github.com/knutwurst/ps5-ultrapack'}
}
function SetIntegrationConfig($Body) {
  $python = ([string]$Body.pythonExe).Trim()
  $cli = ([string]$Body.ultraPackCli).Trim()
  if ($python) {
    if ($python -match '[\\/]') { try { $python = [IO.Path]::GetFullPath($python) } catch { throw 'La ruta de Python no es válida.' }; if (!(Test-Path -LiteralPath $python -PathType Leaf)) { throw "No se encontró el ejecutable de Python: $python" } }
    else { $command = CmdInfo $python; if (!$command.ok -or !$command.path) { throw "No se encontró Python '$python'. Instala Python 3.10+ o introduce la ruta completa a python.exe." }; $python = [string]$command.path }
    $v = @(& $python --version 2>&1); $ec = $LASTEXITCODE; $text = ($v | ForEach-Object { $_.ToString() }) -join ' '; $m = [regex]::Match($text,'Python\s+(\d+)\.(\d+)')
    if ($ec -ne 0 -or !$m.Success) { throw "No se pudo comprobar la versión de Python: $text" }
    $major=[int]$m.Groups[1].Value; $minor=[int]$m.Groups[2].Value
    if ($major -lt 3 -or ($major -eq 3 -and $minor -lt 10)) { throw "UltraPack requiere Python 3.10 o posterior; se detectó $text" }
  }
  if ($cli) {
    try { $cli = [IO.Path]::GetFullPath($cli) } catch { throw 'La ruta de backend/cli.py de UltraPack no es válida.' }
    if (!(Test-Path -LiteralPath $cli -PathType Leaf) -or [IO.Path]::GetFileName($cli) -ine 'cli.py' -or (Split-Path -Leaf (Split-Path -Parent $cli)) -ine 'backend') { throw 'Indica el archivo backend\cli.py de PS5 UltraPack, no una carpeta.' }
    $repoRoot=Split-Path -Parent (Split-Path -Parent $cli)
    if (!(Test-Path -LiteralPath (Join-Path $repoRoot 'README.md') -PathType Leaf)) { throw 'La ruta no parece corresponder al repositorio PS5 UltraPack (falta README.md).' }
  }
  $configPath=Join-Path $script:Runtime 'integrations.json'
  WriteUtf8 $configPath (ConvertTo-Json -InputObject @{pythonExe=$python;ultraPackCli=$cli;updatedAt=(Get-Date).ToString('o')} -Depth 5)
  return @{ok=$true;message='Configuración de PS5 UltraPack guardada localmente.';config=(GetIntegrationConfig)}
}
function ResolveNativeProjectRoot([string]$InputPath) {
  if ([string]::IsNullOrWhiteSpace($InputPath)) { throw 'La ruta del proyecto está vacía.' }
  try { $projectRoot = [IO.Path]::GetFullPath($InputPath) } catch { throw 'La ruta del proyecto no es válida.' }
  $workspaceRoot = [IO.Path]::GetFullPath($script:Workspace)
  $separator = [string][IO.Path]::DirectorySeparatorChar
  if (!$workspaceRoot.EndsWith($separator)) { $workspaceRoot += $separator }
  if (!$projectRoot.StartsWith($workspaceRoot,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'Solo se permiten proyectos creados dentro del workspace de Homebrew Studio.'
  }
  if (!(Test-Path -LiteralPath $projectRoot -PathType Container)) { throw 'No se encuentra la carpeta del proyecto.' }
  $projectItem = Get-Item -LiteralPath $projectRoot -Force
  if (($projectItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'No se admiten carpetas de proyecto enlazadas o puntos de reanálisis.' }
  $markerPath = Join-Path $projectRoot '.ps5hs-project.json'
  if (!(Test-Path -LiteralPath $markerPath -PathType Leaf)) { throw 'No se encontró .ps5hs-project.json. Abre un proyecto nativo creado por Homebrew Studio.' }
  $markerItem = Get-Item -LiteralPath $markerPath -Force
  if (($markerItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'No se leerá ni modificará un manifiesto de proyecto enlazado.' }
  try { $meta = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json } catch { throw 'El manifiesto del proyecto no se puede leer.' }
  if ($meta.schema -ne 'ps5hs-native-project' -or [string]$meta.template -notin @('nativecpp','hui-gl','vulkan-template','ps5link')) {
    throw 'El manifiesto no identifica una plantilla nativa compatible.'
  }
  return @{path=$projectRoot;meta=$meta}
}
function GetProjectEbootFolders([string]$ProjectRoot) {
  $items = @()
  $rootEboot = Join-Path $ProjectRoot 'eboot.bin'
  if (Test-Path -LiteralPath $rootEboot -PathType Leaf) { $items += Get-Item -LiteralPath $rootEboot }
  $distPath = Join-Path $ProjectRoot 'dist'
  if (Test-Path -LiteralPath $distPath -PathType Container) {
    $items += @(Get-ChildItem -LiteralPath $distPath -Filter 'eboot.bin' -File -Recurse -ErrorAction SilentlyContinue)
  }
  $seen = @{}
  $files = @()
  foreach ($item in $items) {
    $key = $item.FullName.ToLowerInvariant()
    if (!$seen.ContainsKey($key)) { $seen[$key] = $true; $files += $item }
  }
  return @($files | Sort-Object LastWriteTime -Descending)
}
function FindProjectTitleFolder([string]$ProjectRoot,[bool]$RequireParamJson) {
  $eboots = @(GetProjectEbootFolders $ProjectRoot)
  if (!$eboots.Count) { throw "No se encontró eboot.bin en el proyecto ni en '$ProjectRoot\dist'. Compila primero el título nativo." }
  foreach ($eboot in $eboots) {
    $folder = Split-Path -Parent $eboot.FullName
    if (!$RequireParamJson -or (Test-Path -LiteralPath (Join-Path $folder 'sce_sys\param.json') -PathType Leaf)) {
      return @{path=$folder;eboot=$eboot.FullName;staged=$false}
    }
  }
  $projectSceSys = GetPS5HSSceSysPath $ProjectRoot
  if ($RequireParamJson -and (Test-Path -LiteralPath (Join-Path $projectSceSys 'param.json') -PathType Leaf)) {
    $selected = $eboots | Select-Object -First 1
    $sourceFolder = Split-Path -Parent $selected.FullName
    $stageRoot = Join-Path (Join-Path $script:Runtime 'ultrapack-staging') ([IO.Path]::GetFileName($ProjectRoot))
    if (Test-Path -LiteralPath $stageRoot -PathType Container) { Remove-Item -LiteralPath $stageRoot -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
    foreach ($child in (Get-ChildItem -LiteralPath $sourceFolder -Force -ErrorAction SilentlyContinue)) {
      Copy-Item -LiteralPath $child.FullName -Destination $stageRoot -Recurse -Force
    }
    Copy-Item -LiteralPath $projectSceSys -Destination (Join-Path $stageRoot 'sce_sys') -Recurse -Force
    foreach ($assetFolder in @('assets','data','resources','modules','lib')) {
      $candidate = Join-Path $ProjectRoot $assetFolder
      if ((Test-Path -LiteralPath $candidate -PathType Container) -and !(Test-Path -LiteralPath (Join-Path $stageRoot $assetFolder))) {
        Copy-Item -LiteralPath $candidate -Destination $stageRoot -Recurse -Force
      }
    }
    foreach ($module in @(Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.prx' -File -ErrorAction SilentlyContinue)) {
      Copy-Item -LiteralPath $module.FullName -Destination $stageRoot -Force
    }
    if (!(Test-Path -LiteralPath (Join-Path $stageRoot 'eboot.bin') -PathType Leaf) -or !(Test-Path -LiteralPath (Join-Path $stageRoot 'sce_sys\param.json') -PathType Leaf)) {
      throw 'No se pudo preparar una carpeta con eboot.bin y sce_sys\param.json para UltraPack.'
    }
    return @{path=$stageRoot;eboot=(Join-Path $stageRoot 'eboot.bin');staged=$true}
  }
  throw 'UltraPack requiere una carpeta de título que contenga eboot.bin y sce_sys\param.json. La compilación no produjo metadatos de título en esa estructura.'
}
function PackageNativeProjectWithUltraPack($Body) {
  $resolved = ResolveNativeProjectRoot ([string]$Body.path)
  $projectRoot = [string]$resolved.path
  $format = ([string]$Body.format).Trim().ToLowerInvariant()
  if ($format -notin @('ffpfs','ffpfsc','pkg')) { throw 'Formato de salida no válido. Elige .ffpfs, .ffpfsc o .pkg.' }
  $config = GetIntegrationConfig
  $python = [string]$config.pythonExe
  $cli = [string]$config.ultraPackCli
  if ($cli) {
    try { $cli = [IO.Path]::GetFullPath($cli) } catch { throw "La ruta configurada de UltraPack no es válida: $cli" }
    if ([IO.Path]::GetFileName($cli) -ine 'cli.py' -or (Split-Path -Leaf (Split-Path -Parent $cli)) -ine 'backend') {
      throw "La ruta configurada no apunta a backend\cli.py: $cli. Corrige la ruta en Herramientas."
    }
    if (!(Test-Path -LiteralPath $cli -PathType Leaf)) { throw "No existe el CLI configurado de UltraPack: $cli. Vuelve a descargar la fuente desde Herramientas o corrige la ruta." }
  }
  if (!$python -or !(Test-Path -LiteralPath $python -PathType Leaf)) {
    throw 'No se ha configurado Python. En Herramientas, indica python.exe (Python 3.10 o posterior).'
  }
  if (!$cli -or !(Test-Path -LiteralPath $cli -PathType Leaf)) {
    throw "No se ha encontrado backend\cli.py de UltraPack. Usa 'Descargar UltraPack (fuente)' en Herramientas o indica su ruta manualmente. Repositorio: https://github.com/knutwurst/ps5-ultrapack"
  }
  if ($format -eq 'pkg') {
    $backendRoot = Split-Path -Parent $cli
    $pkgTool = Join-Path $backendRoot 'native\ffpfsc-pkg-tool.exe'
    if ($env:FFPFSC_PKG_TOOL -and (Test-Path -LiteralPath $env:FFPFSC_PKG_TOOL -PathType Leaf)) { $pkgTool = $env:FFPFSC_PKG_TOOL }
    if (!(Test-Path -LiteralPath $pkgTool -PathType Leaf)) {
      throw "UltraPack no dispone del helper nativo de Windows para crear .pkg: $pkgTool. Ejecuta BUILD_PKG_TOOL.ps1 en la raíz del repositorio con .NET SDK 9+ o utiliza .ffpfsc/.ffpfs."
    }
  }
  $versionOutput = @(& $python --version 2>&1)
  $versionExit = $LASTEXITCODE
  $versionText = ($versionOutput | ForEach-Object { $_.ToString() }) -join ' '
  $versionMatch = [regex]::Match($versionText, 'Python\s+(\d+)\.(\d+)')
  if ($versionExit -ne 0 -or !$versionMatch.Success) { throw "No se pudo comprobar la versión de Python: $versionText" }
  $pyMajor = [int]$versionMatch.Groups[1].Value
  $pyMinor = [int]$versionMatch.Groups[2].Value
  if ($pyMajor -lt 3 -or ($pyMajor -eq 3 -and $pyMinor -lt 10)) { throw "UltraPack requiere Python 3.10 o posterior; se detectó $versionText" }
  $title = FindProjectTitleFolder $projectRoot $true
  $outputRoot = Join-Path $projectRoot ('packages-ultrapack\' + $format + '\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
  $tempRoot = Join-Path $script:Runtime 'ultrapack-temp'
  New-Item -ItemType Directory -Force -Path $outputRoot,$tempRoot | Out-Null

  # Invoke the upstream CLI as documented: SOURCE OUTPUT --to FORMAT.
  # Use classic Arguments/EnvironmentVariables for both PowerShell 5.1 and PowerShell 7.
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $python
  $psi.WorkingDirectory = Split-Path -Parent $cli
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  # Decode UltraPack's UTF-8 output explicitly. Without this, Windows PowerShell can
  # display Unicode symbols (for example, the source-to-output arrow) as mojibake.
  $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
  $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
  $psi.EnvironmentVariables['PYTHONUNBUFFERED'] = '1'
  $psi.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'
  $psi.EnvironmentVariables['PYTHONUTF8'] = '1'
  $verifyEnabled = $true
  if ($null -ne $Body.verify) { $verifyEnabled = [System.Convert]::ToBoolean($Body.verify) }
  $cliArgs = @('-u',$cli,[string]$title.path,$outputRoot,'--to',$format,'--force','--temp-dir',$tempRoot,'--verbose')
  if ($verifyEnabled) { $cliArgs += '--verify' }
  $psi.Arguments = (($cliArgs | ForEach-Object { '"' + ([string]$_).Replace('"','\\"') + '"' }) -join ' ')
  $commandForLog = '"' + $python + '" ' + $psi.Arguments
  $logText = "CLI configurado: $cli`r`nPython configurado: $python ($versionText)`r`nFormato solicitado: $format`r
Verificación contra el origen: $verifyEnabled`r`nOrigen: $($title.path)`r`nDestino: $outputRoot`r`nComando ejecutado:`r`n$commandForLog`r`nDirectorio de trabajo: $($psi.WorkingDirectory)`r`n`r`n"
  WriteBuildJobLog $script:ActiveBuildLogPath "UltraPack: iniciando $format; verificación=$verifyEnabled; origen $($title.path); destino $outputRoot"
  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $psi
  try {
    if (!$process.Start()) { throw 'Windows no pudo iniciar el proceso de Python para UltraPack.' }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $stdoutText = $stdoutTask.GetAwaiter().GetResult()
    $stderrText = $stderrTask.GetAwaiter().GetResult()
    if (![string]::IsNullOrWhiteSpace($stdoutText)) { $logText += "STDOUT:`r`n$stdoutText`r`n" }
    if (![string]::IsNullOrWhiteSpace($stderrText)) { $logText += "STDERR:`r`n$stderrText`r`n" }
    $exitCode = $process.ExitCode
  } catch {
    $exitCode = 1
    $logText += "ERROR AL INICIAR/ESPERAR ULTRAPACK:`r`n$($_.Exception.ToString())"
  } finally {
    $process.Dispose()
  }
  $extension = '.' + $format
  $artifact = ''
  if (Test-Path -LiteralPath $outputRoot -PathType Container) {
    $candidate = Get-ChildItem -LiteralPath $outputRoot -Filter ('*' + $extension) -File -Recurse -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($candidate) { $artifact = $candidate.FullName }
  }
  if ($exitCode -eq 0 -and $artifact) {
    $formatLabel = if ($format -eq 'pkg') { 'fPKG (.pkg)' } elseif ($format -eq 'ffpfs') { 'PFS sin comprimir (.ffpfs)' } else { 'PFS comprimido (.ffpfsc)' }
    $stageMessage = if ($title.staged) { 'Se creó una carpeta temporal con el eboot compilado, los metadatos sce_sys y recursos habituales del proyecto.' } else { 'Se usó directamente la carpeta de título compilada.' }
    return @{ok=$true;message="UltraPack terminó y generó $formatLabel.";output=$logText;path=$projectRoot;source=[string]$title.path;artifact=$artifact;format=$format;exitCode=$exitCode;note=$stageMessage}
  }
  if ($exitCode -ne 0 -and $format -eq 'pkg') {
    $logText += ([Environment]::NewLine + [Environment]::NewLine + 'Nota: el README de UltraPack documenta actualmente la app empaquetada para macOS. En Windows, el CLI puede requerir ajustes y el ayudante fPKG de .NET no viene precompilado en el repositorio.')
  }
  return @{ok=$false;message="UltraPack terminó con código $exitCode o no generó el archivo .$format esperado.";output=$logText;path=$projectRoot;source=[string]$title.path;artifact=$artifact;format=$format;exitCode=$exitCode}
}

function WriteBuildJobLog([string]$Path,[string]$Message) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return }
  try { [IO.File]::AppendAllText($Path, ([string]$Message + [Environment]::NewLine), $script:Utf8) } catch { $script:BuildLogWriteError = $_.Exception.Message }
}
function GetBuildJobDirectory([string]$JobId) {
  if ($JobId -notmatch '^[a-f0-9]{32}$') { throw 'Identificador de compilación no válido.' }
  $root = Join-Path $script:Runtime 'build-jobs'
  return (Join-Path $root $JobId)
}
function StartNativeBuildJob($Body,[string]$Action='visual') {
  $jobId = [guid]::NewGuid().ToString('N')
  $dir = GetBuildJobDirectory $jobId
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  WriteUtf8 (Join-Path $dir 'request.json') (ConvertTo-Json -InputObject @{action=$Action;body=$Body} -Depth 100)
  $startMessage=if($Action -eq 'compute'){'Preparando la validación Vulkan Compute y la compilación local de GLSL…'}elseif($Action -eq 'package'){'Preparando el empaquetado UltraPack…'}else{'Preparando la generación C++20 y la compilación upstream…'}
  WriteBuildJobLog (Join-Path $dir 'build.log') $startMessage
  $hostPath = (Get-Process -Id $PID -ErrorAction Stop).Path
  if (!$hostPath -or !(Test-Path -LiteralPath $hostPath -PathType Leaf)) { throw 'No se pudo localizar el ejecutable de PowerShell para iniciar el trabajador de compilación.' }
  $argumentLine = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" --worker "' + $jobId + '"'
  $worker = Start-Process -FilePath $hostPath -ArgumentList $argumentLine -WorkingDirectory $script:Root -WindowStyle Hidden -PassThru
  if (!$worker) { throw 'No se pudo iniciar el trabajador de compilación.' }
  WriteUtf8 (Join-Path $dir 'worker.json') (ConvertTo-Json -InputObject @{pid=$worker.Id})
  return @{ok=$true;jobId=$jobId;message='Compilación iniciada.';pid=$worker.Id}
}
function ReadBuildJobLogShared([string]$Path) {
  if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
  for ($attempt = 0; $attempt -lt 5; $attempt++) {
    $stream = $null
    $reader = $null
    try {
      $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
      $reader = [IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true)
      return $reader.ReadToEnd()
    } catch [IO.IOException] {
      if ($attempt -eq 4) { return "[El registro está siendo actualizado; se reintentará en la siguiente consulta.]" }
      Start-Sleep -Milliseconds (40 * ($attempt + 1))
    } finally {
      if ($reader) { $reader.Dispose() } elseif ($stream) { $stream.Dispose() }
    }
  }
  return ''
}
function GetNativeBuildJobStatus([string]$JobId) {
  $dir = GetBuildJobDirectory $JobId
  if (!(Test-Path -LiteralPath $dir -PathType Container)) { throw 'No existe esa tarea de compilación.' }
  $logPath = Join-Path $dir 'build.log'
  $resultPath = Join-Path $dir 'result.json'
  $logText = ReadBuildJobLogShared $logPath
  if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    return @{ok=$true;done=$true;log=$logText;result=$result}
  }
  $workerPath = Join-Path $dir 'worker.json'
  if (Test-Path -LiteralPath $workerPath -PathType Leaf) {
    $workerInfo = Get-Content -LiteralPath $workerPath -Raw | ConvertFrom-Json
    if (!(Get-Process -Id ([int]$workerInfo.pid) -ErrorAction SilentlyContinue)) {
      $failed = @{ok=$false;message='El trabajador terminó inesperadamente sin entregar un resultado.';output=$logText;exitCode=1}
      WriteUtf8 $resultPath (ConvertTo-Json -InputObject $failed -Depth 20)
      return @{ok=$true;done=$true;log=$logText;result=$failed}
    }
  }
  return @{ok=$true;done=$false;log=$logText}
}

function EnableEuropeanFontAtlas([string]$ProjectRoot) {
  $fontScript = Join-Path $ProjectRoot 'tools/bake-fonts.sh'
  if (!(Test-Path -LiteralPath $fontScript -PathType Leaf)) {
    if ($script:ActiveBuildLogPath) { WriteBuildJobLog $script:ActiveBuildLogPath 'El upstream actual no incluye tools/bake-fonts.sh; se conserva el sistema de fuentes de la plantilla, sin parche legacy.' }
    return
  }
  $source = [IO.File]::ReadAllText($fontScript)
  $basic = '"$size" "$range" 1024'
  $european = '"$size" "$range" 2048 european'
  if ($source.Contains($basic)) {
    $source = $source.Replace($basic, $european)
    [IO.File]::WriteAllText($fontScript, $source, $script:Utf8)
  } elseif (!$source.Contains($european)) {
    throw 'La plantilla de fuentes cambió: no se reconoce la invocación de font-baker. Se detiene la compilación para no generar un atlas sin acentos.'
  }
  WriteBuildJobLog $script:ActiveBuildLogPath 'Atlas tipográfico europeo habilitado (2048 px; caracteres latinos extendidos).'
}


function InitializeNativeProjectFolder([string]$ProjectRoot,[string]$Template,[string]$TitleId,[string]$Name,[string]$Category,[string]$Distribution) {
  if (!(TestPS5HSTitleId $TitleId)) { return @{ok=$false;message='TITLE_ID debe ser un identificador PPSA12345 válido distinto de PPSA00000.';output=''} }
  if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._-]{0,39}$') { return @{ok=$false;message='El nombre debe tener 1–40 caracteres ASCII seguros.';output=''} }
  if ($Category -notin @('game','media')) { $Category = 'game' }
  $makefile = Join-Path $ProjectRoot 'Makefile'
  if (!(Test-Path -LiteralPath $makefile -PathType Leaf) -or !(Test-Path -LiteralPath (Join-Path $ProjectRoot 'src/main.cpp') -PathType Leaf)) {
    return @{ok=$false;message='No se puede inicializar: el proyecto no contiene Makefile y src/main.cpp.';output=$ProjectRoot}
  }
  $rootWsl = ConvertToWslPath $ProjectRoot
  $wsl = CmdInfo 'wsl.exe'
  if (!$wsl.ok) { return @{ok=$false;message='wsl.exe no está disponible.';output='Configura WSL y una distribución Linux.'} }
  $legacyInit = Join-Path $ProjectRoot 'tools/init-project.sh'
  $paramPath = Join-Path $ProjectRoot 'sce_sys/param.json'
  if ((Test-Path -LiteralPath $legacyInit -PathType Leaf) -and (Test-Path -LiteralPath $paramPath -PathType Leaf)) {
    $legacyWsl = ConvertToWslPath $legacyInit
    $paramWsl = ConvertToWslPath $paramPath
    $cmd = 'cd ' + (BashQuote $rootWsl) + ' && TITLE_ID=' + (BashQuote $TitleId) + ' APP_NAME=' + (BashQuote $Name) + ' APP_CATEGORY=' + (BashQuote $Category) + ' bash ' + (BashQuote $legacyWsl) + ' ' + (BashQuote $paramWsl)
  } else {
    $makeText = Get-Content -LiteralPath $makefile -Raw
    if ($makeText -notmatch '(?m)^\s*init\s*:') {
      return @{ok=$false;message='Este checkout no tiene herramienta de inicialización reconocida (tools/init-project.sh o target make init). No se han modificado los archivos del proyecto.';output=$ProjectRoot}
    }
    $cmd = 'cd ' + (BashQuote $rootWsl) + ' && make init TITLE_ID=' + (BashQuote $TitleId) + ' APP_NAME=' + (BashQuote $Name) + ' APP_CATEGORY=' + (BashQuote $Category)
  }
  $output = @(& $wsl.path -d $Distribution --exec bash -lc $cmd 2>&1)
  $exit = $LASTEXITCODE
  $log = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
  $actualTitleId = GetProjectTitleId $ProjectRoot
  $valid = ($exit -eq 0 -and (Test-Path -LiteralPath $paramPath -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $ProjectRoot 'Makefile') -PathType Leaf) -and $actualTitleId -eq $TitleId)
  if (!$valid) { return @{ok=$false;message="La inicialización upstream terminó con código $exit, pero no se pudo validar sce_sys/param.json con $TitleId.";output=$log} }
  $catalogEntry = $script:Catalog | Where-Object id -eq $Template | Select-Object -First 1
  $repository = if ($catalogEntry) { [string]$catalogEntry.repo } else { (GetProjectRemote $ProjectRoot) }
  $summary = @{schema='ps5hs-native-project';template=$Template;repository=$repository;titleId=$TitleId;name=$Name;category=$Category;initializedAt=(Get-Date).ToString('o')}
  WriteUtf8 (Join-Path $ProjectRoot '.ps5hs-project.json') (ConvertTo-Json -InputObject $summary -Depth 5)
  return @{ok=$true;message='Proyecto inicializado con el mecanismo upstream de la plantilla.';output=$log;meta=$summary}
}

function EnsureVulkanProjectSdkBootstrap([string]$ProjectRoot,$Policy) {
  $relativePath = 'ps5/tools/setup-sdk.sh'
  $sourcePath = Join-Path $script:Toolchains 'PS5_VulkanTemplate\ps5\tools\setup-sdk.sh'
  if (!(Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "No está disponible la plantilla local del bootstrap Vulkan: $sourcePath"
  }
  $sourcePath = AssertPS5HSNativePathNoReparsePoints -Path $sourcePath
  $destinationPath = Join-Path $ProjectRoot ($relativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
  $destinationPath = AssertPS5HSNativePathNoReparsePoints -Path $destinationPath
  $destinationParent = Split-Path -Parent $destinationPath
  if (!(Test-Path -LiteralPath $destinationParent -PathType Container)) {
    throw "No está la carpeta esperada del bootstrap Vulkan: $destinationParent"
  }
  $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToUpperInvariant()
  # The native build normalizer converts CRLF/CR to LF before this guard runs.
  # Treat that exact byte-level line-ending normalization as the same template,
  # while continuing to reject any content change.
  $sourceBytes = [IO.File]::ReadAllBytes($sourcePath)
  $normalizedSourceBytes = [System.Collections.Generic.List[byte]]::new()
  for ($i = 0; $i -lt $sourceBytes.Length; $i++) {
    if ($sourceBytes[$i] -eq 13) {
      if ($i + 1 -lt $sourceBytes.Length -and $sourceBytes[$i + 1] -eq 10) { $i++ }
      $null = $normalizedSourceBytes.Add([byte]10)
    } else {
      $null = $normalizedSourceBytes.Add($sourceBytes[$i])
    }
  }
  $sha256 = [Security.Cryptography.SHA256]::Create()
  try {
    $normalizedSourceHash = (($sha256.ComputeHash($normalizedSourceBytes.ToArray()) | ForEach-Object { $_.ToString('X2') }) -join '')
  } finally { $sha256.Dispose() }
  $legacyHash = '4A4E85154510C53992283D82DAD7BF1486F12D4F62750560505AA4753C066043'
  if (Test-Path -LiteralPath $destinationPath) {
    $destinationItem = Get-Item -LiteralPath $destinationPath -Force
    if (($destinationItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "No se reemplazará un bootstrap enlazado: $destinationPath"
    }
    if ($destinationItem.PSIsContainer) {
      throw "La ruta del bootstrap es una carpeta, no un archivo: $destinationPath"
    }
    $destinationHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($destinationHash -eq $sourceHash -or $destinationHash -eq $normalizedSourceHash) { return $false }
    if ($destinationHash -ne $legacyHash) {
      throw "El bootstrap del proyecto tiene cambios no reconocidos (SHA-256 $destinationHash); se conserva sin sobrescribir: $destinationPath"
    }
  }
  $null = InvokePS5HSNativeModificationWithAudit -ProjectRoot $ProjectRoot -Backend 'vulkan-template' -Operation 'repair-offline-vulkan-sdk-bootstrap' -PermissionKey 'allowExecuteUpstreamBuildTools' -RelativePaths @($relativePath) -Policy $Policy -SourceRepository 'mihawk-99/PS5_VulkanTemplate' -Action {
    [IO.File]::Copy($sourcePath, $destinationPath, $true)
  }
  return $true
}
function BuildNativeProject([string]$ProjectPath,[bool]$CleanBeforeBuild=$false,[string]$RequestedTitleId='',[string]$RequestedName='',$Policy=$null) {
  $workspaceRoot = [IO.Path]::GetFullPath($script:Workspace)
  $separator = [string]([IO.Path]::DirectorySeparatorChar)
  if (!$workspaceRoot.EndsWith($separator)) { $workspaceRoot += $separator }
  try { $projectRoot = [IO.Path]::GetFullPath($ProjectPath) }
  catch { return @{ok=$false;message='La ruta del proyecto no es válida.';output=$_.Exception.Message} }
  if (!$projectRoot.StartsWith($workspaceRoot, [StringComparison]::OrdinalIgnoreCase)) {
    return @{ok=$false;message='Solo se permite compilar proyectos creados dentro del workspace de Homebrew Studio.';output=$projectRoot}
  }
  if (!(Test-Path -LiteralPath $projectRoot -PathType Container)) {
    return @{ok=$false;message='No se encuentra la carpeta del proyecto dentro del workspace.';output=$projectRoot}
  }
  $projectRootItem = Get-Item -LiteralPath $projectRoot -Force
  if (($projectRootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    return @{ok=$false;message='No se compilará a través de una carpeta de proyecto enlazada o punto de reanálisis.';output=$projectRoot}
  }
  $markerPath = Join-Path $projectRoot '.ps5hs-project.json'
  if (Test-Path -LiteralPath $markerPath -PathType Leaf) {
    $markerItem = Get-Item -LiteralPath $markerPath -Force
    if (($markerItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      return @{ok=$false;message='El manifiesto del proyecto es un enlace; no se leerá ni modificará.';output=$markerPath}
    }
  }
  $profile = GetProjectProfile $projectRoot
  $template = [string]$profile.template
  if ($template -notin @('nativecpp','hui-gl','vulkan-template')) {
    return @{ok=$false;message=('No hay un perfil de compilación de título compatible: ' + [string]$profile.typeLabel);output=[string]$profile.buildReason;path=$projectRoot;profile=$profile.typeLabel}
  }
  $offlineBackend = GetPS5HSOfflineBackendReadiness $template
  if ($offlineBackend.enforced -and $offlineBackend.status -ne 'validated') {
    $message = "El bundle offline no declara este backend como compilable: $($offlineBackend.status)."
    return @{ok=$false;message=$message;output=($offlineBackend.reason + ' No se han generado ni modificado archivos del proyecto.');path=$projectRoot;templateId=$template;buildStoppedBeforeMutation=$true;offlineStatus=$offlineBackend.status}
  }
  $policy = AssertPS5HSNativeModificationConsent -Backend $template -Policy $Policy -RequirePermissionKeys @('allowExecuteUpstreamBuildTools')
  if ($profile.needsInit) { $policy = AssertPS5HSNativeModificationConsent -Backend $template -Policy $policy -RequirePermissionKeys @('allowExecuteUpstreamGenerationTools','allowExecuteUpstreamBuildTools') }
  $st = GetStatus
  if (!$st.prerequisites.wsl) { return @{ok=$false;message='No hay una distribución WSL inicializada.';output='Configura WSL + Debian y completa su primer arranque.';templateId=$template} }
  if (!$st.prerequisites.wslGitPython) { return @{ok=$false;message='Faltan Git o Python 3 dentro de WSL.';output='Instala git y python3 en la distribución Linux indicada por la documentación upstream.';templateId=$template} }
  $dist = [string]$st.wslDistribution
  if ($profile.needsInit) {
    $titleId = ([string]$RequestedTitleId).Trim().ToUpperInvariant()
    $projectName = ([string]$RequestedName).Trim()
    if (!(TestPS5HSTitleId $titleId) -or !$projectName) {
      return @{ok=$false;message='El proyecto se reconoce, pero requiere inicialización. Introduce un nombre y un TITLE_ID válido (PPSA12345).';output=[string]$profile.typeLabel;path=$projectRoot;templateId=$template;needsInit=$true;titleId=$profile.titleId}
    }
    $initResult = InvokePS5HSNativeTreeModificationWithAudit -ProjectRoot $projectRoot -Backend $template -Operation 'initialize-native-project-from-upstream' -PermissionKey 'allowExecuteUpstreamGenerationTools' -Policy $policy -SourceRepository ([string]$profile.repository) -Action { InitializeNativeProjectFolder $projectRoot $template $titleId $projectName 'game' $dist }
    if (!$initResult.ok) { return @{ok=$false;message=$initResult.message;output=$initResult.output;path=$projectRoot;templateId=$template;needsInit=$true} }
    WriteBuildJobLog $script:ActiveBuildLogPath ([string]$initResult.message)
    if ($initResult.output) { WriteBuildJobLog $script:ActiveBuildLogPath ([string]$initResult.output) }
    $profile = GetProjectProfile $projectRoot
  }
  if (!(Test-Path -LiteralPath $markerPath -PathType Leaf)) {
    if (!$profile.initialized) { return @{ok=$false;message='El proyecto todavía no tiene metadatos de título válidos.';output=$projectRoot;templateId=$template;needsInit=$true} }
    $entry = $script:Catalog | Where-Object id -eq $template | Select-Object -First 1
    $meta = @{schema='ps5hs-native-project';template=$template;repository=$(if($entry){[string]$entry.repo}else{[string]$profile.repository});titleId=[string]$profile.titleId;name=[string]$profile.name;category='game';initializedAt=(Get-Date).ToString('o')}
    $null = InvokePS5HSNativeModificationWithAudit -ProjectRoot $projectRoot -Backend $template -Operation 'write-native-project-metadata' -PermissionKey 'allowExecuteUpstreamBuildTools' -RelativePaths @('.ps5hs-project.json') -Policy $policy -SourceRepository ([string]$profile.repository) -Action {
      WriteUtf8 $markerPath (ConvertTo-Json -InputObject $meta -Depth 5)
    }
  }
  try { $meta = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json }
  catch { return @{ok=$false;message='El manifiesto del proyecto no se puede leer.';output=$_.Exception.Message} }
  if ($template -in @('nativecpp','hui-gl') -and $policy.allowWindowsBuildEntrypointPatch) {
    try { $null = ApplyPS5HSWindowsBuildEntrypointPatch -ProjectRoot $projectRoot -Policy $policy -Backend $template -SourceRepository ([string]$profile.repository) }
    catch { return @{ok=$false;message='No se pudo aplicar el ajuste autorizado de build.ps1.';output=$_.Exception.Message;path=$projectRoot;templateId=$template} }
  }
  $studioGeneratedUi = $false
  if ($template -eq 'hui-gl') {
    $generatedSource = Join-Path $projectRoot 'src/concepts/ps5hs_generated.cpp'
    $studioGeneratedUi = ([bool]$meta.generatedFromStudio -or (Test-Path -LiteralPath $generatedSource -PathType Leaf))
  }
  if ($studioGeneratedUi) {
    if ($policy.allowOpenGlRuntimeProfile) {
      try {
        $null = InvokePS5HSNativeModificationWithAudit -ProjectRoot $projectRoot -Backend $template -Operation 'apply-opengl-standalone-runtime-profile' -PermissionKey 'allowOpenGlRuntimeProfile' -RelativePaths @('src/app/shell.cpp','src/app/shell_render.cpp','.ps5hs-native-runtime.json') -Policy $policy -SourceRepository ([string]$profile.repository) -Action { ApplyPS5HSStandaloneNativeUiProfile $projectRoot }
        if ($script:ActiveBuildLogPath) { WriteBuildJobLog $script:ActiveBuildLogPath 'Perfil de runtime OpenGL aplicado con autorización y auditoría SHA-256.' }
      } catch {
        return @{ok=$false;message='La compilación se detuvo porque no se pudo aplicar/verificar el perfil OpenGL autorizado.';output=$_.Exception.Message;path=$projectRoot;templateId=$template;buildStoppedBeforeCompile=$true}
      }
    } elseif ($script:ActiveBuildLogPath) { WriteBuildJobLog $script:ActiveBuildLogPath 'Perfil de runtime OpenGL omitido por política: se mantiene el comportamiento upstream existente.' }
  }
  if ($template -eq 'hui-gl' -and $policy.allowOpenGlEuropeanAtlas) {
    try {
      $null = InvokePS5HSNativeModificationWithAudit -ProjectRoot $projectRoot -Backend $template -Operation 'enable-opengl-european-font-atlas' -PermissionKey 'allowOpenGlEuropeanAtlas' -RelativePaths @('tools/bake-fonts.sh') -Policy $policy -SourceRepository ([string]$profile.repository) -Action { EnableEuropeanFontAtlas $projectRoot }
    } catch { return @{ok=$false;message=$_.Exception.Message;output=$_.Exception.Message;path=$projectRoot;templateId=$template} }
  } elseif ($template -eq 'hui-gl' -and $script:ActiveBuildLogPath) { WriteBuildJobLog $script:ActiveBuildLogPath 'Atlas tipográfico europeo omitido por política; se conserva la configuración upstream.' }
  if ($template -eq 'hui-gl') {
    $sdkSeed = SeedProjectOpenGlSdkCache $projectRoot
    if ($sdkSeed.seeded -and $script:ActiveBuildLogPath) { WriteBuildJobLog $script:ActiveBuildLogPath 'SDK ps5-opengl copiado desde toolchains/ps5-opengl-sdk con SHA-256 verificado.' }
    elseif(!$sdkSeed.seeded -and $script:ActiveBuildLogPath) { WriteBuildJobLog $script:ActiveBuildLogPath ('No hay tarball local del SDK en toolchains/ps5-opengl-sdk: '+[string]$sdkSeed.reason) 'WARN' }
  }
  try { $null = NormalizeNativeBuildFilesWithAudit -ProjectRoot $projectRoot -Policy $policy -Backend $template -SourceRepository ([string]$profile.repository) }
  catch { return @{ok=$false;message='No se pudieron normalizar los finales de línea de los archivos nativos con la política actual.';output=$_.Exception.Message;templateId=$template} }
  $scriptPath = ''
  if ($template -in @('nativecpp','hui-gl')) {
    if (!(Test-Path -LiteralPath (Join-Path $projectRoot 'Makefile') -PathType Leaf)) {
      return @{ok=$false;message='La carpeta no contiene un Makefile upstream.';output=$projectRoot;templateId=$template}
    }
  } else {
    $scriptPath = Join-Path $projectRoot 'ps5/tools/build.sh'
    if (!(Test-Path $scriptPath)) { return @{ok=$false;message='Falta ps5/tools/build.sh en el título Vulkan generado.';output=$projectRoot;templateId=$template} }
  }
  if ($template -eq 'vulkan-template') {
    try {
      $sdkBootstrapUpdated = EnsureVulkanProjectSdkBootstrap -ProjectRoot $projectRoot -Policy $policy
      if ($sdkBootstrapUpdated) {
        WriteBuildJobLog $script:ActiveBuildLogPath 'Bootstrap del SDK Vulkan actualizado desde toolchains/ y registrado en .ps5hs-modifications.json.'
      }
    } catch {
      return @{ok=$false;message='No se pudo actualizar con seguridad el bootstrap SDK del proyecto Vulkan.';output=$_.Exception.Message;path=$projectRoot;templateId=$template;buildStoppedBeforeCompile=$true}
    }
  }
  $st = GetStatus
  if (!$st.prerequisites.wsl) { return @{ok=$false;message='No hay una distribución WSL inicializada.';output='Configura WSL + Debian y completa su primer arranque.';templateId=$template} }
  if (!$st.prerequisites.wslGitPython) { return @{ok=$false;message='Faltan Git o Python 3 dentro de WSL.';output='Instala git y python3 en la distribución Linux indicada por la documentación upstream.';templateId=$template} }
  $dist = [string]$st.wslDistribution
  $dependencyLog = @()
  try {
    if ($template -eq 'vulkan-template') {
      foreach ($dependencyId in @('vulkan-radv','vulkan-sdk','ps5-mesa')) {
        $entry = $script:Catalog | Where-Object id -eq $dependencyId | Select-Object -First 1
        if (!$entry) { throw "No está registrada la dependencia $dependencyId." }
        $installed = InstallRepo $entry
        $dependencyLog += [string]$installed.message
        if (!$installed.ok) { throw "No se pudo preparar $($entry.name): $($installed.message)" }
      }
      $vulkanDir = Join-Path $script:Toolchains 'PS5_Vulkan'
      $payloadSdkDir = Join-Path $script:Toolchains 'PS5_PayloadSDK'
      $mesaDir = Join-Path $script:Toolchains 'PS5_Mesa'
      $requiredVendorSources = @(
        @{path=$vulkanDir;name='PS5_Vulkan';repository='mihawk-99/PS5_Vulkan';files=@('README.md','Makefile','tools/build.sh','tools/setup-native-dependencies.sh')},
        @{path=$payloadSdkDir;name='PS5_PayloadSDK';repository='mihawk-99/PS5_PayloadSDK';files=@('README.md','platform/tools/setup-sdk.sh')},
        @{path=$mesaDir;name='PS5_Mesa';repository='mihawk-99/PS5_Mesa';files=@('README.md','meson.build')}
      )
      foreach($source in $requiredVendorSources) {
        $manifestPath=Join-Path $source.path '.ps5hs-source.json'
        $hasCheckout=Test-Path -LiteralPath (Join-Path $source.path '.git') -PathType Container
        $hasSourceManifest=$false
        if(Test-Path -LiteralPath $manifestPath -PathType Leaf) {
          try {
            $manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $manifestRepository=[string]$manifest.repository
            $manifestMirror=[string]$manifest.mirrorRepository
            $manifestSource=[string]$manifest.sourceRepository
            $hasSourceManifest=($manifestRepository -eq [string]$source.repository) -or ($manifestMirror -eq [string]$source.repository) -or ($manifestSource -eq [string]$source.repository)
          } catch { $hasSourceManifest=$false }
        }
        $missingFiles=@($source.files | Where-Object { !(Test-Path -LiteralPath (Join-Path $source.path $_) -PathType Leaf) })
        if((!$hasCheckout -and !$hasSourceManifest) -or $missingFiles.Count -gt 0) {
          throw ("La fuente local $($source.name) no pasa la validación de vendorización. Faltan archivos: " + ($missingFiles -join ', ') + ".")
        }
      }
      $helperRelativePaths = @('tools/ninja-build.sh','tools/build-host-tools.sh')
      $auditRelativePaths = @($helperRelativePaths) + @('.ps5hs-compatibility.json')
      $missingHelpers = @($helperRelativePaths | Where-Object { !(Test-Path -LiteralPath (Join-Path $vulkanDir ($_ -replace '/', [IO.Path]::DirectorySeparatorChar)) -PathType Leaf) })
      if ($missingHelpers.Count -gt 0) {
        if (!$policy.allowVulkanBuildHelperRestore) { throw ('Faltan helpers de build en PS5_Vulkan (' + ($missingHelpers -join ', ') + '). No se han restaurado: autoriza «Restaurar scripts auxiliares Vulkan» y vuelve a compilar.') }
        $restored = @(InvokePS5HSNativeModificationWithAudit -ProjectRoot $vulkanDir -Backend $template -Operation 'restore-missing-vulkan-build-helpers' -PermissionKey 'allowVulkanBuildHelperRestore' -RelativePaths $auditRelativePaths -Policy $policy -SourceRepository 'blackbearreloaded/ps5-native-app-boilerplate' -Action { EnsureVulkanBuildSupport $vulkanDir })
        if ($restored.Count -gt 0) { $dependencyLog += 'Se restauraron helpers upstream con autorización y auditoría SHA-256; detalle en .ps5hs-compatibility.json y .ps5hs-modifications.json.' }
      }
    }
    $projectWsl = ConvertToWslPath $projectRoot
    $wsl = CmdInfo 'wsl.exe'
    if (!$wsl.ok) { throw 'wsl.exe no está disponible.' }
    $ccacheProbe = @(& $wsl.path -d $dist --exec bash -lc 'command -v ccache >/dev/null 2>&1 && printf yes || printf no' 2>$null)
    $ccacheEnabled = (($ccacheProbe -join '').Trim() -eq 'yes')
    $ccacheValue = if ($ccacheEnabled) { '1' } else { '0' }
    $cleanCommand = ''
    if ($CleanBeforeBuild -and $template -in @('nativecpp','hui-gl')) {
      $cleanCommand = "if make -qp 2>/dev/null | grep -qE '^[[:space:]]*clean[[:space:]]*:'; then echo '[CLEAN] Ejecutando make clean'; make clean; else echo '[CLEAN] El Makefile no declara target clean; no se borran archivos por conjetura'; fi && "
    } elseif ($CleanBeforeBuild -and $template -eq 'vulkan-template') {
      $dependencyLog += 'Se solicitó clean, pero no se ha confirmado un target clean en la raíz Vulkan; se conserva la salida anterior y se ejecuta el build upstream.'
    }
    if ($template -eq 'hui-gl') {
      $nativeEntry = $script:Catalog | Where-Object id -eq 'nativecpp' | Select-Object -First 1
      $openglEntry = $script:Catalog | Where-Object id -eq 'opengl' | Select-Object -First 1
      if (!$nativeEntry -or !$openglEntry) { throw 'Faltan las entradas de Native App Boilerplate o PS5 OpenGL en el catálogo.' }
      foreach ($entry in @($nativeEntry,$openglEntry)) {
        $depResult = InstallRepo $entry
        if (!$depResult.ok) { throw "No se pudo preparar dependencia $($entry.name): $($depResult.message)" }
        $dependencyLog += ([string]$entry.name + ': ' + [string]$depResult.message)
      }
      $nativeDir = Join-Path $script:Toolchains $nativeEntry.folder
      $openglDir = Join-Path $script:Toolchains $openglEntry.folder
      # The source snapshot intentionally excludes third_party/ and cannot rebuild Mesa/PSBC
      # offline from a clean checkout. Resolve the verified 1.0.2 release SDK instead of running
      # make sdk-gl46 against incomplete sources. Only this pinned archive can use network fallback;
      # all native/title dependency bootstrapping remains local-only.
      $uiEntry = $script:Catalog | Where-Object id -eq 'hui-gl' | Select-Object -First 1
      if (!$uiEntry) { throw 'No está registrada la plantilla PS5 Homebrew UI para resolver su SDK OpenGL fijado.' }
      $uiDir = Join-Path $script:Toolchains $uiEntry.folder
      $sdkFetcher = Join-Path $uiDir 'tools/fetch-opengl-sdk.sh'
      if (!(Test-Path -LiteralPath $sdkFetcher -PathType Leaf)) {
        throw "Falta el resolvedor local del SDK OpenGL fijado: $sdkFetcher"
      }
      $sdkFetcherWsl = ConvertToWslPath $sdkFetcher
      $toolchainsWsl = ConvertToWslPath $script:Toolchains
      $sdkCmd = 'export PS5HS_LOCAL_TOOLCHAINS_ONLY=1 PS5HS_TOOLCHAINS_ROOT=' + (BashQuote $toolchainsWsl) + ' && bash ' + (BashQuote $sdkFetcherWsl)
      WriteBuildJobLog $script:ActiveBuildLogPath 'Resolviendo SDK OpenGL 1.0.2 desde el archivo local empaquetado; se verifica SHA-256 del archivo y manifiesto interno. No se consulta Internet.'
      $sdkOutput = @(& $wsl.path -d $dist --exec bash -lc $sdkCmd 2>&1 | ForEach-Object { $line=$_.ToString(); WriteBuildJobLog $script:ActiveBuildLogPath $line; $line })
      $sdkExit = $LASTEXITCODE
      $openglPrefix = ([string](@($sdkOutput | Select-Object -Last 1)[0])).Trim()
      if ($sdkExit -ne 0 -or [string]::IsNullOrWhiteSpace($openglPrefix) -or $openglPrefix -notmatch '^/') {
        $sdkLogText = ($sdkOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
        throw "No se pudo resolver el SDK OpenGL 1.0.2 verificado (código $sdkExit). $sdkLogText"
      }
      WriteBuildJobLog $script:ActiveBuildLogPath ('SDK OpenGL fijado y manifiesto verificado: ' + $openglPrefix)
      $nativeWsl = ConvertToWslPath $nativeDir
      $toolchainsWslForProject = ConvertToWslPath $script:Toolchains
      $cmd = 'cd ' + (BashQuote $projectWsl) + ' && export PS5_NATIVE_APP_TEMPLATE=' + (BashQuote $nativeWsl) + ' PS5_OPENGL_PREFIX=' + (BashQuote $openglPrefix) + ' PS5HS_LOCAL_TOOLCHAINS_ONLY=1 PS5HS_TOOLCHAINS_ROOT=' + (BashQuote $toolchainsWslForProject) + ' USE_CCACHE=' + $ccacheValue + ' && make opengl && '
      if (Test-Path -LiteralPath (Join-Path $projectRoot 'tools/bake-fonts.sh') -PathType Leaf) { $cmd += 'bash tools/bake-fonts.sh && ' }
      $cmd += $cleanCommand + 'USE_CCACHE=' + $ccacheValue + ' make'
    } elseif ($template -eq 'nativecpp') {
      $toolchainsWslForNative = ConvertToWslPath $script:Toolchains
      $cmd = 'cd ' + (BashQuote $projectWsl) + ' && export PS5HS_LOCAL_TOOLCHAINS_ONLY=1 PS5HS_TOOLCHAINS_ROOT=' + (BashQuote $toolchainsWslForNative) + ' && ' + $cleanCommand + 'USE_CCACHE=' + $ccacheValue + ' make'
    } else {
      $vulkanWsl = ConvertToWslPath $vulkanDir
      $payloadSdkWsl = ConvertToWslPath $payloadSdkDir
      $payloadSdkSnapshotWsl = ConvertToWslPath (Join-Path $script:Toolchains 'PS5_PayloadSDK-pinned-611893fc')
      $mesaWsl = ConvertToWslPath $mesaDir
      $buildScriptWsl = ConvertToWslPath $scriptPath
      # The title build consumes the already-built RADV archive, host ELF/FSELF tool,
      # runtime and SDK caches produced by PS5_Vulkan's own scripts. Keep its SDK
      # cache separate from the title's later pin (they intentionally use distinct revisions).
      $refreshNotices = 'python3 ps5/tools/build-assets.py --notices'
      $toolchainsWslForVulkan = ConvertToWslPath $script:Toolchains
      $bootstrap = 'cd ' + (BashQuote $projectWsl) + ' && export PS5HS_LOCAL_TOOLCHAINS_ONLY=1 PS5HS_TOOLCHAINS_ROOT=' + (BashQuote $toolchainsWslForVulkan) + ' && ' + $refreshNotices + ' && cd ' + (BashQuote $vulkanWsl) +
        ' && USE_CCACHE=' + $ccacheValue + ' PS5_PAYLOAD_SDK_FORK=' + (BashQuote $payloadSdkWsl) + ' bash tools/setup-native-dependencies.sh' +
        ' && USE_CCACHE=' + $ccacheValue + ' bash tools/build-host-tools.sh' +
        ' && PS5_PAYLOAD_SDK_FORK=' + (BashQuote $payloadSdkWsl) + ' bash tools/rebuild-libc.sh' +
        ' && PS5_PAYLOAD_SDK_FORK=' + (BashQuote $payloadSdkWsl) + ' PS5_MESA_FORK=' + (BashQuote $mesaWsl) + ' bash tools/build-radv.sh release'
      $cmd = $bootstrap + ' && cd ' + (BashQuote $projectWsl) + ' && USE_CCACHE=' + $ccacheValue + ' PS5_VULKAN_DIR=' + (BashQuote $vulkanWsl) + ' PS5_PAYLOAD_SDK_FORK=' + (BashQuote $payloadSdkWsl) + ' PS5_PAYLOAD_SDK_SNAPSHOT=' + (BashQuote $payloadSdkSnapshotWsl) + ' bash ' + (BashQuote $buildScriptWsl)
    }
    # Preserve the last usable title if a rebuild fails. A successful build is accepted only
    # when the pipeline exits zero and an eboot.bin plus title metadata can be verified.
    WriteBuildJobLog $script:ActiveBuildLogPath 'Ejecutando el pipeline real de WSL/Make/CMake/Ninja. La salida se transmite al registro mientras avanza.'
    $buildInvocation = InvokePS5HSNativeTreeModificationWithAudit -ProjectRoot $projectRoot -Backend $template -Operation 'execute-native-upstream-build-pipeline' -PermissionKey 'allowExecuteUpstreamBuildTools' -Policy $policy -SourceRepository ([string]$profile.repository) -Action {
      $capturedOutput = @(& $wsl.path -d $dist --exec bash -lc $cmd 2>&1 | ForEach-Object {
        $line = $_.ToString()
        WriteBuildJobLog $script:ActiveBuildLogPath $line
        $line
      })
      $capturedExit = $LASTEXITCODE
      return @{output=@($capturedOutput | ForEach-Object { $_.ToString() });exitCode=[int]$capturedExit}
    }
    $output = @($buildInvocation.output)
    $exit = [int]$buildInvocation.exitCode
    $buildLog = ($output | ForEach-Object { $_.ToString() }) -join "`r`n"
    if ($dependencyLog.Count) { $buildLog = (($dependencyLog -join "`r`n") + "`r`n" + $buildLog) }
    $artifact = ''
    $eboots = @(GetProjectEbootFolders $projectRoot)
    if ($eboots.Count -gt 0) {
      $candidate = $eboots[0]
      $titleFolder = Split-Path -Parent $candidate.FullName
      $paramPath = Join-Path $titleFolder 'sce_sys\\param.json'
      if (!(Test-Path -LiteralPath $paramPath -PathType Leaf)) { $paramPath = Join-Path $projectRoot 'sce_sys\\param.json' }
      if (!(Test-Path -LiteralPath $paramPath -PathType Leaf)) { $paramPath = Join-Path $projectRoot 'ps5\sce_sys\param.json' }
      if (Test-Path -LiteralPath $paramPath -PathType Leaf) { $artifact = $candidate.FullName }
    }
    if ($exit -eq 0 -and $artifact) {
      return @{ok=$true;message='El build upstream finalizó correctamente: eboot.bin y sce_sys/param.json verificados.';output=$buildLog;path=$projectRoot;artifact=$artifact;templateId=$template;titleId=[string]$meta.titleId;exitCode=$exit}
    }
    return @{ok=$false;message="El build upstream terminó con código $exit o no produjo un título actual verificable (eboot.bin + sce_sys/param.json).";output=$buildLog;path=$projectRoot;artifact=$artifact;templateId=$template;titleId=[string]$meta.titleId;exitCode=$exit;diagnostics=@(@{severity='error';title='Título nativo incompleto';message='Se requiere un eboot.bin generado en esta compilación y metadatos sce_sys/param.json. Los ZIP/PKG residuales no se consideran ejecutables.';location=$template})}
  } catch {
    $failure = [string]$_.Exception.Message
    $failureOutput = (@($dependencyLog) + @($failure) | Where-Object { $_ }) -join [Environment]::NewLine
    if ($script:ActiveBuildLogPath) { WriteBuildJobLog $script:ActiveBuildLogPath $failure }
    return @{ok=$false;message=$failure;output=$failureOutput;path=$projectRoot;templateId=$template;titleId=[string]$meta.titleId}
  }
}
function WriteNativeVisualAssets($Body,[string]$ProjectRoot) {
  $incoming = @($Body.nativeAssets | Where-Object { $_ })
  if ($incoming.Count -gt 16) { throw 'Máximo de 16 imágenes RGBA nativas por título.' }
  if ($incoming.Count -eq 0) { return @{count=0;manifest=''} }
  $directory = Join-Path $ProjectRoot 'assets/ps5hs'
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
  $manifest = @()
  $seenAssetIds = @{}
  foreach ($asset in $incoming) {
    $assetId = [string]$asset.id
    if ($assetId -notmatch '^[A-Za-z0-9_-]{1,80}$') { throw 'ID de recurso nativo no válido.' }
    if ($seenAssetIds.ContainsKey($assetId)) { throw "ID de recurso nativo duplicado: $assetId" }
    $seenAssetIds[$assetId] = $true
    if ([string]$asset.encoding -ne 'rgba8-little-endian-v1') { throw "Codificación de imagen no admitida para $assetId." }
    $width = 0; $height = 0
    if (![int]::TryParse([string]$asset.width,[ref]$width) -or ![int]::TryParse([string]$asset.height,[ref]$height) -or $width -lt 1 -or $height -lt 1 -or $width -gt 512 -or $height -gt 512) {
      throw "Dimensiones inválidas para el recurso $assetId (máximo 512×512)."
    }
    $encoded = [string]$asset.base64
    if ([string]::IsNullOrWhiteSpace($encoded) -or $encoded.Length -gt 1400000) { throw "El contenido RGBA de $assetId está vacío o excede el límite." }
    try { $bytes = [Convert]::FromBase64String($encoded) } catch { throw "Base64 inválido en el recurso $assetId." }
    $expectedLength = 8 + ($width * $height * 4)
    if ($bytes.Length -ne $expectedLength -or [BitConverter]::ToUInt32($bytes,0) -ne [uint32]$width -or [BitConverter]::ToUInt32($bytes,4) -ne [uint32]$height) {
      throw "La cabecera o la longitud RGBA de $assetId no coincide con sus dimensiones."
    }
    $fileName = $assetId + '.rgba'
    $destination = Join-Path $directory $fileName
    $temporary = $destination + '.tmp'
    try {
      [IO.File]::WriteAllBytes($temporary,$bytes)
      Move-Item -LiteralPath $temporary -Destination $destination -Force | Out-Null
    } finally {
      # A failed write or rename must not leave an untracked temporary asset.
      if (Test-Path -LiteralPath $temporary -PathType Leaf) {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
      }
    }
    $manifest += @{id=$assetId;file=('ps5hs/'+$fileName);width=$width;height=$height;bytes=$bytes.Length;sha256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant();sourceName=[IO.Path]::GetFileName([string]$asset.sourceName)}
  }
  WriteUtf8 (Join-Path $directory 'manifest.json') (ConvertTo-Json -InputObject @($manifest) -Depth 10)
  return @{count=$manifest.Count;manifest='assets/ps5hs/manifest.json'}
}

function RegisterVulkanNativeAssets($Body,[string]$ProjectRoot) {
  $incoming = @($Body.nativeAssets | Where-Object { $_ })
  if ($incoming.Count -eq 0) { return @{count=0;programId=''} }
  $manifestPath = Join-Path $ProjectRoot 'ps5/assets.json'
  $samplesPath = Join-Path $ProjectRoot 'ps5/src/samples.cpp'
  if (!(Test-Path $manifestPath -PathType Leaf) -or !(Test-Path $samplesPath -PathType Leaf)) {
    throw 'La plantilla Vulkan no contiene el manifiesto de recursos o src/samples.cpp.'
  }
  $sampleText = Get-Content -LiteralPath $samplesPath -Raw
  $programMatch = [regex]::Match($sampleText,'(?s)#define PS5_SAMPLES\s*\\\s*SAMPLE\(([A-Za-z0-9_]+),')
  if (!$programMatch.Success) { throw 'No se pudo detectar el identificador de programa del título Vulkan.' }
  $programId = $programMatch.Groups[1].Value
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  $existing = @($manifest.assets | Where-Object { $_.title -notlike 'PS5 Homebrew Studio user asset:*' })
  $records = @()
  $licenseRel = 'licenses/PS5HS-USER-ASSETS.txt'
  $licensePath = Join-Path (Join-Path $ProjectRoot 'ps5') $licenseRel
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $licensePath) | Out-Null
  WriteUtf8 $licensePath @'
PS5 Homebrew Studio user-supplied assets

The assets listed as user-provided were supplied by the project author through
PS5 Homebrew Studio. The IDE does not grant or imply any copyright licence.
Before distributing a title, its author must confirm permission to use and
redistribute every supplied image and retain any notices required by its owner.
'@
  foreach ($asset in $incoming) {
    $assetId = [string]$asset.id
    if ($assetId -notmatch '^[A-Za-z0-9_-]{1,80}$') { throw 'ID de recurso Vulkan no válido.' }
    $fileName = $assetId + '.rgba'
    $sourceRel = 'assets/ps5hs/' + $fileName
    $assetRel = 'ps5hs/' + $fileName
    $sourcePath = Join-Path $ProjectRoot ($sourceRel.Replace('/',[IO.Path]::DirectorySeparatorChar))
    if (!(Test-Path $sourcePath -PathType Leaf)) { throw "No se encuentra el recurso RGBA que debe empaquetarse: $sourceRel" }
    $records += [pscustomobject]@{
      path = $assetRel
      from = 'file'
      source = $sourceRel
      used_by = @($programId)
      title = ('PS5 Homebrew Studio user asset: ' + [IO.Path]::GetFileNameWithoutExtension($fileName))
      author = 'User supplied through PS5 Homebrew Studio'
      licence = 'User-provided; redistribution rights must be confirmed by the user'
      url = 'Local file supplied by the project author'
      licence_file = $licenseRel
    }
  }
  $manifest.assets = @($existing) + @($records)
  WriteUtf8 $manifestPath (ConvertTo-Json -InputObject $manifest -Depth 100)
  return @{count=$records.Count;programId=$programId;manifest='ps5/assets.json'}
}
function InstallVulkanTextureRuntime($Body,[string]$ProjectRoot,[string]$ProgramId) {
  $incoming = @($Body.nativeAssets | Where-Object { $_ })
  if ($incoming.Count -gt 16) { throw 'Máximo de 16 texturas Vulkan.' }
  $programPath = Join-Path $ProjectRoot ('examples/' + $ProgramId + '/' + $ProgramId + '.cpp')
  if (!(Test-Path $programPath -PathType Leaf)) { throw "No se encuentra el programa Vulkan generado: $programPath" }
  $screenPath = Join-Path $ProjectRoot ('examples/' + $ProgramId + '/kit/screen.cpp')
  if (!(Test-Path $screenPath -PathType Leaf)) { throw "No se encuentra la pantalla Vulkan generada: $screenPath" }
  $programSource = Get-Content -LiteralPath $programPath -Raw
  $screenSource = Get-Content -LiteralPath $screenPath -Raw
  $kitHeaderPath = Join-Path $ProjectRoot 'ps5/ui/kit.hpp'
  if (!(Test-Path $kitHeaderPath -PathType Leaf)) { throw "No se encuentra la cabecera Vulkan del proyecto: $kitHeaderPath" }
  $kitHeaderSource = Get-Content -LiteralPath $kitHeaderPath -Raw
  if ($programSource.Contains('gPs5hsTextureHandles')) {
    $legacyMarker = $programSource.IndexOf('gPs5hsTextureHandles', [StringComparison]::Ordinal)
    $legacyStart = $programSource.LastIndexOf('namespace ps5ui {', $legacyMarker, [StringComparison]::Ordinal)
    $legacyEndMarker = '} // namespace ps5ui'
    $legacyEnd = $programSource.IndexOf($legacyEndMarker, $legacyMarker, [StringComparison]::Ordinal)
    if ($legacyStart -lt 0 -or $legacyEnd -lt 0) { throw 'El runtime Vulkan previo está incompleto; no se puede migrar de forma segura fuera del wrapper.' }
    $programSource = $programSource.Remove($legacyStart, $legacyEnd + $legacyEndMarker.Length - $legacyStart)
  }
  if (!$programSource.Contains('#include "kit.hpp"')) { throw 'No se puede conectar el runtime de texturas: falta include kit.hpp en el programa.' }
  $screenHeader = '#include "ui/fonts.hpp"'
  if (!$screenSource.Contains($screenHeader)) { throw 'No se puede instalar el runtime Vulkan: falta el encabezado ui/fonts.hpp en kit/screen.cpp.' }
  if (!$kitHeaderSource.Contains('#include <cstdint>')) { throw 'La cabecera kit.hpp no incluye cstdint; no se instalarán declaraciones con tipos incompletos.' }
  if (!$kitHeaderSource.Contains('#include <string_view>')) {
    if (!$kitHeaderSource.Contains('#include <string>')) { throw 'No se pudo añadir string_view a la cabecera kit.hpp sin alterar sus includes.' }
    $kitHeaderSource = $kitHeaderSource.Replace('#include <string>', '#include <string>' + [Environment]::NewLine + '#include <string_view>')
  }
  $textureForDeclaration = 'std::uint32_t ps5hs_texture_for(std::string_view asset_path);'
  $loadTexturesDeclaration = 'void ps5hs_load_textures(hui::gfx::VkRenderer &renderer);'
  $hasTextureForDeclaration = $kitHeaderSource.Contains($textureForDeclaration)
  $hasLoadTexturesDeclaration = $kitHeaderSource.Contains($loadTexturesDeclaration)
  if ($hasTextureForDeclaration -xor $hasLoadTexturesDeclaration) { throw 'kit.hpp contiene una declaración parcial del runtime Vulkan; se conserva para revisión.' }
  if (!$hasTextureForDeclaration) {
    $namespaceMarker = 'namespace ps5ui {'
    if ([regex]::Matches($kitHeaderSource, [regex]::Escape($namespaceMarker)).Count -ne 1) { throw 'No se encontró una apertura única de namespace ps5ui en kit.hpp.' }
    $declarations = '// Visual PS5 native texture runtime API.' + [Environment]::NewLine + $textureForDeclaration + [Environment]::NewLine + $loadTexturesDeclaration + [Environment]::NewLine
    $kitHeaderSource = $kitHeaderSource.Replace($namespaceMarker, $namespaceMarker + [Environment]::NewLine + $declarations)
  }
  $assetPaths = @($incoming | ForEach-Object { 'ps5hs/' + ([string]$_.id) + '.rgba' } | Sort-Object -Unique)
  if ($assetPaths.Count -gt 0) { $pathLiterals = ($assetPaths | ForEach-Object { '        ' + (ConvertTo-Json -InputObject $_ -Compress) }) -join [Environment]::NewLine }
  else { $pathLiterals = '        nullptr' }
  $helper = @"
#include <cstdint>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace ps5ui {
namespace { std::unordered_map<std::string, std::uint32_t> gPs5hsTextureHandles; }
std::uint32_t ps5hs_texture_for(std::string_view asset_path) {
    const auto found = gPs5hsTextureHandles.find(std::string(asset_path));
    return found == gPs5hsTextureHandles.end() ? 0u : found->second;
}
void ps5hs_load_textures(hui::gfx::VkRenderer &renderer) {
    static constexpr const char *kPaths[] = {
$pathLiterals
    };
    for (const char *relative : kPaths) {
        if (relative == nullptr) continue;
        std::string bytes;
        const std::string path = std::string("/app0/assets/") + relative;
        if (!hui::save::read_file(path, &bytes, 1048584u) || bytes.size() < 8u) continue;
        const auto *raw = reinterpret_cast<const unsigned char *>(bytes.data());
        const std::uint32_t width = static_cast<std::uint32_t>(raw[0]) | (static_cast<std::uint32_t>(raw[1]) << 8) | (static_cast<std::uint32_t>(raw[2]) << 16) | (static_cast<std::uint32_t>(raw[3]) << 24);
        const std::uint32_t height = static_cast<std::uint32_t>(raw[4]) | (static_cast<std::uint32_t>(raw[5]) << 8) | (static_cast<std::uint32_t>(raw[6]) << 16) | (static_cast<std::uint32_t>(raw[7]) << 24);
        if (width == 0u || height == 0u || width > 512u || height > 512u || bytes.size() != 8u + static_cast<std::size_t>(width) * height * 4u) continue;
        const std::uint32_t texture = renderer.create_texture(static_cast<int>(width), static_cast<int>(height), raw + 8u);
        if (texture != 0u) gPs5hsTextureHandles[relative] = texture;
    }
}
} // namespace ps5ui

"@
  if (!$screenSource.Contains('#include "kit.hpp"')) {
    $screenSource = $screenSource.Replace($screenHeader, $screenHeader + [Environment]::NewLine + '#include "kit.hpp"')
  }
  if (!$screenSource.Contains('gPs5hsTextureHandles')) {
    $screenSource = $screenSource.Replace('#include "kit.hpp"', '#include "kit.hpp"' + [Environment]::NewLine + $helper)
  }
  $programSource = $programSource.Replace('ps5ui::ps5hs_load_textures(kit.renderer);','::ps5ui::ps5hs_load_textures(kit.renderer);')
  if (!$programSource.Contains('ps5hs_load_textures(kit.renderer)')) {
    if (!$programSource.Contains('prepareKit();')) { throw 'No se encontró prepareKit() para cargar las texturas Vulkan.' }
    $programSource = $programSource.Replace('prepareKit();', 'prepareKit();' + [Environment]::NewLine + '        ::ps5ui::ps5hs_load_textures(kit.renderer);')
  }
  WriteUtf8 $kitHeaderPath $kitHeaderSource
  WriteUtf8 $screenPath $screenSource
  WriteUtf8 $programPath $programSource
  return @{ok=$true;count=$incoming.Count;source=$screenPath;entrypoint=$programPath}
}

function PrepareNativeUnicodeFonts($Body,[string]$ProjectRoot,[string]$Backend) {
  $font = $Body.nativeFont
  if (!$font -or [string]::IsNullOrWhiteSpace([string]$font.base64)) { return @{enabled=$false;glyphCount=0} }
  $policy = AssertPS5HSNativeModificationConsent -Backend $Backend -Policy $Body.nativeModifications -RequirePermissionKeys @('allowCustomUnicodeFont')
  $null = AssertPS5HSNativeModificationManifestWritable -ProjectRoot $ProjectRoot
  $fileName = [IO.Path]::GetFileName([string]$font.fileName)
  if ($fileName -notmatch '\.ttf$') { throw 'La fuente personalizada debe ser TrueType (.ttf). OTF/CFF no es compatible con el horneador incluido.' }
  $encoded = [string]$font.base64
  if ($encoded.Length -gt 28000000) { throw 'La fuente TTF supera el máximo de 20 MiB.' }
  try { $fontBytes = [Convert]::FromBase64String($encoded) } catch { throw 'El contenido base64 de la fuente TTF es inválido.' }
  if ($fontBytes.Length -lt 256 -or $fontBytes.Length -gt (20 * 1024 * 1024)) { throw 'La fuente TTF está vacía, truncada o supera el máximo de 20 MiB.' }

  $sourceDir = Join-Path $ProjectRoot '.ps5hs-font-source'
  New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null
  $sourceFont = Join-Path $sourceDir 'PS5HS-User-Font.ttf'
  $codepointPath = Join-Path $sourceDir 'codepoints.txt'
  [IO.File]::WriteAllBytes($sourceFont,$fontBytes)

  $points = [System.Collections.Generic.SortedSet[int]]::new()
  for ($cp = 0x20; $cp -le 0x7e; $cp++) { $null = $points.Add($cp) }
  $builtIn = 'Listo cruceta para navegar X para activar Teclado de pantalla Escribe con la cruceta y confirma las teclas Espacio Borrar Limpiar Aceptar Cancelar Confirmar seleccionar Atrás para guardar Edición cancelada valor actualizado Opción · ¿¡áéíóúÁÉÍÓÚñÑüÜ€…‹›'
  for ($i = 0; $i -lt $builtIn.Length; $i++) {
    if ([char]::IsHighSurrogate($builtIn[$i]) -and $i + 1 -lt $builtIn.Length) { $cp = [char]::ConvertToUtf32($builtIn,$i); $i++ }
    else { $cp = [int][char]$builtIn[$i] }
    if ($cp -ge 0x20) { $null = $points.Add([int]$cp) }
  }
  foreach ($rawPoint in @($font.codepoints)) {
    $cp = 0
    if (![int]::TryParse([string]$rawPoint,[ref]$cp) -or $cp -lt 0x20 -or $cp -gt 0x10ffff -or ($cp -ge 0xd800 -and $cp -le 0xdfff)) {
      throw ('El IDE envió un punto de código Unicode inválido: ' + [string]$rawPoint)
    }
    $null = $points.Add($cp)
  }
  if ($points.Count -gt 2500) { throw "El proyecto necesita $($points.Count) glifos únicos; el límite por fuente es 2500. Reduce el repertorio." }
  $nl = [Environment]::NewLine
  $lines = @($points | ForEach-Object { $_.ToString('X') })
  WriteUtf8 $codepointPath (($lines -join $nl) + $nl)

  $st = GetStatus
  if (!$st.prerequisites.wsl -or !$st.prerequisites.wslGitPython) { throw 'El horneado de fuentes Unicode necesita una distribución WSL con Git y Python 3.' }
  $distribution = [string]$st.wslDistribution

  if ($Backend -eq 'vulkan-ui') {
    $setupPath = Join-Path $ProjectRoot 'ps5/ui/setup-kit.sh'
    if (!(Test-Path -LiteralPath $setupPath -PathType Leaf)) { throw 'La plantilla Vulkan no contiene ps5/ui/setup-kit.sh.' }
    $setup = [IO.File]::ReadAllText($setupPath)
    $stampOld = 'stamp="$revision src assets/fonts assets/audio third_party/fonts"'
    $archiveOld = 'src assets/fonts assets/audio third_party/fonts LICENSE \'
    if ($setup.Contains($stampOld)) { $setup = $setup.Replace($stampOld,'stamp="$revision src assets/fonts assets/audio third_party/fonts tools/font-baker third_party/stb"') }
    elseif (!$setup.Contains('tools/font-baker third_party/stb')) { throw 'La configuración del kit Vulkan cambió; no se puede exportar el horneador Unicode.' }
    if ($setup.Contains($archiveOld)) { $setup = $setup.Replace($archiveOld,'src assets/fonts assets/audio third_party/fonts tools/font-baker third_party/stb LICENSE \') }
    elseif (!$setup.Contains('tools/font-baker third_party/stb LICENSE')) { throw 'No se pudo ampliar la lista de fuentes del kit Vulkan.' }
    WriteUtf8 $setupPath $setup
    $projectWsl = ConvertToWslPath $ProjectRoot
    $wsl = CmdInfo 'wsl.exe'
    if (!$wsl.ok) { throw 'wsl.exe no está disponible para exportar el kit Vulkan.' }
    $setupCommand = 'cd ' + (BashQuote $projectWsl) + ' && bash ps5/ui/setup-kit.sh'
    $setupOutput = @(& $wsl.path -d $distribution --exec bash -lc $setupCommand 2>&1)
    $setupExit = $LASTEXITCODE
    if ($setupExit -ne 0) { throw ('No se pudo exportar el horneador de fuentes del kit Vulkan: ' + (($setupOutput | ForEach-Object { $_.ToString() }) -join $nl)) }
    $kitRoot = Join-Path $ProjectRoot '.deps/hui'
  } else {
    $kitRoot = $ProjectRoot
  }

  $bakerPath = Join-Path $kitRoot 'tools/font-baker/bake_font.cpp'
  $headerPath = Join-Path $kitRoot 'src/gfx/font_format.hpp'
  $stbPath = Join-Path $kitRoot 'third_party/stb/stb_truetype.h'
  foreach ($required in @($bakerPath,$headerPath,$stbPath)) {
    if (!(Test-Path -LiteralPath $required -PathType Leaf)) { throw "Falta una dependencia del horneador Unicode: $required" }
  }
  $baker = [IO.File]::ReadAllText($bakerPath)
  $baker = [regex]::Replace($baker, '\r\n?', [string][char]10)
  if (!$baker.Contains('const bool custom_glyphs = argc > 6')) {
    $selector = '    const bool european = argc > 6 && std::strcmp(argv[6], "european") == 0;'
    if (!$baker.Contains($selector)) { throw 'El upstream cambió la interfaz del font-baker; se cancela la compilación.' }
    $selectorReplacement = @'
    const bool european = argc > 6 && std::strcmp(argv[6], "european") == 0;
    const bool custom_glyphs = argc > 6 && std::strcmp(argv[6], "custom") == 0;
    std::vector<int> selected_codepoints;
    if (custom_glyphs) {
        if (argc <= 7) { std::fprintf(stderr, "custom glyph mode requires a codepoint file\n"); return 2; }
        std::ifstream glyph_file(argv[7]);
        if (!glyph_file) { std::fprintf(stderr, "cannot read codepoint file %s\n", argv[7]); return 1; }
        int codepoint = 0;
        while (glyph_file >> std::hex >> codepoint) {
            if (codepoint < 32 || codepoint > 0x10ffff || (codepoint >= 0xd800 && codepoint <= 0xdfff)) {
                std::fprintf(stderr, "invalid Unicode scalar in %s\n", argv[7]); return 2;
            }
            selected_codepoints.push_back(codepoint);
        }
        std::sort(selected_codepoints.begin(), selected_codepoints.end());
        selected_codepoints.erase(std::unique(selected_codepoints.begin(), selected_codepoints.end()), selected_codepoints.end());
        if (selected_codepoints.empty()) { std::fprintf(stderr, "empty Unicode codepoint list\n"); return 2; }
    } else { selected_codepoints = codepoints(european); }
'@
    $baker = $baker.Replace($selector,$selectorReplacement)
    $loopNeedle = '    for (int codepoint : codepoints(european))'
    if (!$baker.Contains($loopNeedle)) { throw 'No se localizó el bucle de glifos del font-baker upstream.' }
    $baker = $baker.Replace($loopNeedle,'    for (int codepoint : selected_codepoints)')
    $missingNeedle = @'
        if (codepoint != ' ' && stbtt_FindGlyphIndex(&font, codepoint) == 0)
        {
            std::fprintf(stderr, "skipping U+%04X (not in font)\n", codepoint);
            continue;
        }
'@
    $missingReplacement = @'
        if (codepoint != ' ' && stbtt_FindGlyphIndex(&font, codepoint) == 0)
        {
            if (custom_glyphs) {
                std::fprintf(stderr, "selected font lacks required codepoint U+%04X\n", codepoint);
                return 1;
            }
            std::fprintf(stderr, "skipping U+%04X (not in font)\n", codepoint);
            continue;
        }
'@
    $missingNeedle = [regex]::Replace($missingNeedle, '\r\n?', [string][char]10)
    $missingReplacement = [regex]::Replace($missingReplacement, '\r\n?', [string][char]10)
    if (!$baker.Contains($missingNeedle)) { throw 'No se pudo activar la comprobación de glifos ausentes del font-baker.' }
    $baker = $baker.Replace($missingNeedle,$missingReplacement)
    [IO.File]::WriteAllText($bakerPath,$baker,$script:Utf8)
  }

  $kitFonts = Join-Path $kitRoot 'third_party/fonts'
  $null = New-Item -ItemType Directory -Force -Path $kitFonts
  $kitFont = Join-Path $kitFonts 'PS5HS-User-Font.ttf'
  $kitCodepoints = Join-Path $kitFonts 'PS5HS-Unicode-Codepoints.txt'
  Copy-Item -LiteralPath $sourceFont -Destination $kitFont -Force
  Copy-Item -LiteralPath $codepointPath -Destination $kitCodepoints -Force
  $bakeScript = Join-Path $kitRoot 'tools/bake-fonts.sh'
  if (Test-Path -LiteralPath $bakeScript -PathType Leaf) {
    $bakeText = [IO.File]::ReadAllText($bakeScript)
    if (!$bakeText.Contains('PS5HS_CUSTOM_UNICODE_FONT_BEGIN')) {
      $guard = @'
# PS5HS_CUSTOM_UNICODE_FONT_BEGIN
PS5HS_BAKE_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PS5HS_CUSTOM_FONT="$PS5HS_BAKE_SCRIPT_DIR/../third_party/fonts/PS5HS-User-Font.ttf"
PS5HS_CUSTOM_POINTS="$PS5HS_BAKE_SCRIPT_DIR/../third_party/fonts/PS5HS-Unicode-Codepoints.txt"
if [[ -f "$PS5HS_CUSTOM_FONT" && -f "$PS5HS_CUSTOM_POINTS" ]]; then
  echo "[PS5HS] Custom Unicode atlas already baked; preserving it."
  exit 0
fi
# PS5HS_CUSTOM_UNICODE_FONT_END
'@
      $shebang = [regex]::Match($bakeText, '\A#![^\r\n]*(?:\r?\n|$)')
      $bakeLineEnding = if ($bakeText.Contains("`r`n")) { "`r`n" } else { "`n" }
      $guard = [regex]::Replace($guard, '\r\n?', $bakeLineEnding)
      if ($shebang.Success) { $bakeText = $bakeText.Insert($shebang.Length, $guard + $bakeLineEnding) }
      else { $bakeText = $guard + $bakeLineEnding + $bakeText }
      WriteUtf8 $bakeScript $bakeText
    }
  }
  $kitRootWsl = ConvertToWslPath $kitRoot
  $fontWsl = ConvertToWslPath $kitFont
  $codepointsWsl = ConvertToWslPath $kitCodepoints
  $outputFontsWsl = ConvertToWslPath (Join-Path $kitRoot 'assets/fonts')
  $buildCommand = 'cd ' + (BashQuote $kitRootWsl) + ' || exit 1; mkdir -p build/host assets/fonts; cxx=clang++; command -v "$cxx" >/dev/null 2>&1 || cxx=c++; command -v "$cxx" >/dev/null 2>&1 || exit 127; "$cxx" -std=c++20 -O2 -w tools/font-baker/bake_font.cpp -o build/host/ps5hs-bake-font || exit $?; for face in inter-regular inter-semibold montserrat-medium dejavu-sans-mono press-start-2p patrick-hand; do build/host/ps5hs-bake-font ' + (BashQuote $fontWsl) + ' ' + (BashQuote $outputFontsWsl) + '/"$face".huifont 56 8 4096 custom ' + (BashQuote $codepointsWsl) + ' || exit $?; done'
  $wsl = CmdInfo 'wsl.exe'
  if (!$wsl.ok) { throw 'wsl.exe no está disponible para compilar el atlas Unicode.' }
  $output = @(& $wsl.path -d $distribution --exec bash -lc $buildCommand 2>&1)
  $exit = $LASTEXITCODE
  $log = ($output | ForEach-Object { $_.ToString() }) -join $nl
  if ($exit -ne 0) { throw ('Falló el horneado de la fuente Unicode. Comprueba que la TTF contiene los glifos requeridos. ' + $log) }

  $notice = @"
Fuente TTF personalizada: $fileName
Glifos Unicode solicitados: $($points.Count)
Backend: $Backend

El archivo TTF y la lista de codepoints se conservan en .ps5hs-font-source/ para reconstrucción local. El IDE no concede derechos sobre la fuente; verifica su licencia antes de distribuir el título.
"@
  WriteUtf8 (Join-Path $ProjectRoot 'PS5HS-UNICODE-FONTS.txt') $notice
  WriteBuildJobLog $script:ActiveBuildLogPath ("Fuente Unicode personalizada horneada: " + $fileName + "; " + $points.Count + " codepoints; seis atlas SDF generados; la auditoría se registra al finalizar.")
  return @{enabled=$true;glyphCount=$points.Count;fileName=$fileName;notice='PS5HS-UNICODE-FONTS.txt'}
}

function RestoreNativeVisualReplacement([string]$TargetPath,[string]$BackupPath) {
  if ([string]::IsNullOrWhiteSpace($BackupPath) -or !(Test-Path -LiteralPath $BackupPath -PathType Container)) {
    return @{restored=$false;failedPath='';backupPath=$BackupPath;error='No se encuentra la copia de seguridad.'}
  }
  $failedPath = ''
  if (Test-Path -LiteralPath $TargetPath) {
    $failedPath = $TargetPath + '.ps5hs-failed-' + [guid]::NewGuid().ToString('N').Substring(0,8)
    try { Move-Item -LiteralPath $TargetPath -Destination $failedPath -ErrorAction Stop }
    catch { return @{restored=$false;failedPath='';backupPath=$BackupPath;error=('No se pudo apartar el intento fallido: ' + $_.Exception.Message)} }
  }
  try {
    Move-Item -LiteralPath $BackupPath -Destination $TargetPath -ErrorAction Stop
    return @{restored=$true;failedPath=$failedPath;backupPath='';error=''}
  } catch {
    $restoreError = $_.Exception.Message
    if ($failedPath -and (Test-Path -LiteralPath $failedPath -PathType Container) -and !(Test-Path -LiteralPath $TargetPath)) {
      try { Move-Item -LiteralPath $failedPath -Destination $TargetPath -ErrorAction Stop; $failedPath = '' } catch { $restoreError = $_.Exception.Message }
    }
    return @{restored=$false;failedPath=$failedPath;backupPath=$BackupPath;error=('No se pudo restaurar la copia previa: ' + $restoreError)}
  }
}

function BuildNativeVisualProject($Body) {
  WriteBuildJobLog $script:ActiveBuildLogPath 'Validando el modelo visual, el backend y los metadatos del título…'
  $backend = [string]$Body.backend
  if ($backend -notin @('opengl-ui','vulkan-ui')) {
    return @{ok=$false;message='Backend nativo visual desconocido.';output=$backend}
  }
  $offlineBackend = GetPS5HSOfflineBackendReadiness $backend
  if ($offlineBackend.enforced -and $offlineBackend.status -ne 'validated') {
    $message = "El bundle offline no declara este backend como compilable: $($offlineBackend.status)."
    WriteBuildJobLog $script:ActiveBuildLogPath $message 'ERROR'
    WriteBuildJobLog $script:ActiveBuildLogPath ([string]$offlineBackend.reason) 'ERROR'
    return @{ok=$false;message=$message;output=[string]$offlineBackend.reason;backend=$backend;buildStoppedBeforeMutation=$true;offlineStatus=$offlineBackend.status}
  }
  $integrationPermissionKey = if ($backend -eq 'opengl-ui') { 'allowOpenGlTemplateIntegration' } else { 'allowVulkanTemplateIntegration' }
  $requiredPermissions = @('allowExecuteUpstreamGenerationTools','allowExecuteUpstreamBuildTools',$integrationPermissionKey)
  $hasCustomFont = ($null -ne $Body.nativeFont -and ![string]::IsNullOrWhiteSpace([string]$Body.nativeFont.base64))
  $hasPresentationAssets = ($null -ne $Body.icon -or $null -ne $Body.selectionBackground -or $null -ne $Body.launchBackground -or $null -ne $Body.audio)
  if ($hasCustomFont) { $requiredPermissions += 'allowCustomUnicodeFont' }
  if ($hasPresentationAssets) { $requiredPermissions += 'allowExecuteUpstreamAssetTools' }
  $requiredPermissions = @($requiredPermissions | Select-Object -Unique)
  try { $policy = AssertPS5HSNativeModificationConsent -Backend $backend -Policy $Body.nativeModifications -RequirePermissionKeys $requiredPermissions }
  catch { return @{ok=$false;message='Operación detenida antes de modificar el proyecto: falta consentimiento explícito.';output=$_.Exception.Message;backend=$backend;buildStoppedBeforeMutation=$true} }
  $name = [string]$Body.project.name
  $titleId = ([string]$Body.titleId).Trim().ToUpperInvariant()
  $code = [string]$Body.programCode
  if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._-]{0,39}$') {
    return @{ok=$false;message='Nombre inválido. Usa entre 1 y 40 caracteres ASCII.';output=$name}
  }
  if (!(TestPS5HSTitleId $titleId)) {
    return @{ok=$false;message='TITLE_ID inválido. Usa un identificador PPSA12345 distinto de PPSA00000.';output=$titleId}
  }
  $requiredFactory = if ($backend -eq 'vulkan-ui') { 'make_screen' } else { 'make_ps5hs_generated' }
  if ($code.Length -lt 2000 -or !$code.Contains($requiredFactory) -or !$code.Contains('GeneratedScreen')) {
    return @{ok=$false;message='El código no corresponde al generador C++20 del backend seleccionado. No se ha creado un título.';output='Regenera el fuente desde la pestaña Código.'}
  }

  $created = $null
  $projectRoot = ''
  $replacementBackupPath = ''
  $expectedTemplate = if ($backend -eq 'opengl-ui') { 'hui-gl' } else { 'vulkan-template' }
  $slugForTarget = Slug $name
  if ($backend -eq 'opengl-ui') {
    $suffixForTarget = $slugForTarget.ToUpperInvariant() -replace '[^A-Z0-9]',''
    $suffixForTarget = ($suffixForTarget + '0000000000000000').Substring(0,16)
    $targetCandidate = Join-Path $script:Workspace ($suffixForTarget + '-OpenGL-UI')
  } else { $targetCandidate = Join-Path $script:Workspace ($slugForTarget + '-Vulkan') }
  if (Test-Path -LiteralPath $targetCandidate -PathType Container) {
    $targetItem = Get-Item -LiteralPath $targetCandidate -Force
    if (($targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      return @{ok=$false;message='No se puede sobrescribir una carpeta enlazada o punto de reanálisis. El IDE no escribirá a través de ese destino.';output=[string]$targetCandidate;path=[string]$targetCandidate;exitCode=2}
    }
    if (!$Body.overwriteExisting) {
      return @{ok=$false;message='La carpeta de destino ya existe. Cambia el nombre del título o marca «Sobrescribir» para reemplazar únicamente un proyecto de Homebrew Studio de la misma plantilla.';output=[string]$targetCandidate;path=[string]$targetCandidate;exitCode=2}
    }
    $existingMarker = Join-Path $targetCandidate '.ps5hs-project.json'
    if (!(Test-Path -LiteralPath $existingMarker -PathType Leaf)) {
      # Legacy projects created by older Studio releases lack this marker. They are only
      # eligible for migration if their native scaffold is recognizable and TITLE_ID matches.
      $legacyRequiredFiles = if ($backend -eq 'opengl-ui') {
        @('Makefile','sce_sys/param.json','src/main.cpp','tools/prepare-opengl.sh')
      } else {
        @('Makefile','sce_sys/param.json','README.md','ps5/src/samples.cpp','ps5/tools/build.sh')
      }
      $legacyMissingFiles = @($legacyRequiredFiles | Where-Object {
        !(Test-Path -LiteralPath (Join-Path $targetCandidate $_) -PathType Leaf)
      })
      if ($legacyMissingFiles.Count -gt 0) {
        return @{ok=$false;message='No se puede reemplazar de forma segura: la carpeta no tiene manifiesto ni coincide con la estructura de un proyecto nativo antiguo de Homebrew Studio.';output=([string]$targetCandidate + [Environment]::NewLine + 'Faltan: ' + ($legacyMissingFiles -join ', '));path=[string]$targetCandidate;exitCode=2}
      }
      $legacyParamPath = Join-Path $targetCandidate 'sce_sys/param.json'
      try { $legacyParam = Get-Content -LiteralPath $legacyParamPath -Raw | ConvertFrom-Json } catch {
        return @{ok=$false;message='No se puede adoptar la carpeta antigua: sce_sys/param.json no se puede leer.';output=$_.Exception.Message;path=[string]$targetCandidate;exitCode=2}
      }
      if ([string]$legacyParam.titleId -ine $titleId) {
        return @{ok=$false;message='No se puede adoptar la carpeta antigua: TITLE_ID no coincide. No se ha movido ni sobrescrito nada.';output=('Detectado: ' + [string]$legacyParam.titleId + '; solicitado: ' + $titleId);path=[string]$targetCandidate;exitCode=2}
      }
      $existingMeta = @{schema='ps5hs-native-project';template=$expectedTemplate;name=$name;titleId=$titleId}
      WriteBuildJobLog $script:ActiveBuildLogPath 'Proyecto antiguo sin manifiesto reconocido por su estructura y TITLE_ID; se conservará completo en una copia de seguridad antes de regenerar.'
    } else {
      try { $existingMeta = Get-Content -LiteralPath $existingMarker -Raw | ConvertFrom-Json } catch {
        return @{ok=$false;message='No se puede sobrescribir: el manifiesto existente no se puede leer.';output=$_.Exception.Message;path=[string]$targetCandidate;exitCode=2}
      }
    }
    if ($existingMeta.schema -ne 'ps5hs-native-project' -or [string]$existingMeta.template -ne $expectedTemplate) {
      return @{ok=$false;message='No se puede sobrescribir: el destino no es un proyecto de Homebrew Studio de la misma plantilla.';output=[string]$targetCandidate;path=[string]$targetCandidate;exitCode=2}
    }
    if ([string]$existingMeta.name -ine $name -or [string]$existingMeta.titleId -ine $titleId) {
      return @{ok=$false;message='El destino comparte un nombre de carpeta con otro título, pero su nombre o TITLE_ID es distinto. No se sobrescribirá; cambia el nombre para evitar la colisión.';output=[string]$targetCandidate;path=[string]$targetCandidate;exitCode=2}
    }
    $replacementBackupPath = $targetCandidate + '.ps5hs-backup-' + [guid]::NewGuid().ToString('N').Substring(0,8)
    try {
      Move-Item -LiteralPath $targetCandidate -Destination $replacementBackupPath -ErrorAction Stop
    } catch {
      $replacementBackupPath = ''
      return @{ok=$false;message='No se pudo apartar de forma segura el proyecto existente. No se ha borrado ni sobrescrito.';output=$_.Exception.Message;path=[string]$targetCandidate;exitCode=2}
    }
    WriteBuildJobLog $script:ActiveBuildLogPath ('Proyecto anterior preservado como copia de seguridad: ' + $replacementBackupPath)
  }
  try {
    if ($backend -eq 'opengl-ui') {
      $created = NewNativeTitle $name $titleId 'game' 'hui-gl' $policy
    } else {
      # A UI title is required: GeneratedScreen implements the upstream Concept contract.
      $created = NewVulkanTitle $name $titleId 'aurora' $policy
    }
    if (!$created -or !$created.ok) {
      $failurePath = [string]$created.path
      $failureOutput = [string]$created.output
      $failedProjectPath = ''
      if ($replacementBackupPath -and (Test-Path -LiteralPath $replacementBackupPath -PathType Container)) {
        $restore = RestoreNativeVisualReplacement $targetCandidate $replacementBackupPath
        $failedProjectPath = [string]$restore.failedPath
        $replacementBackupPath = [string]$restore.backupPath
        if ($restore.restored) {
          $failurePath = $targetCandidate
          $failureOutput += ([Environment]::NewLine + 'Se restauró la versión previa en su carpeta original.')
          if ($failedProjectPath) { $failureOutput += ([Environment]::NewLine + 'La generación incompleta se conserva en: ' + $failedProjectPath) }
        } elseif ($replacementBackupPath) {
          $failureOutput += ([Environment]::NewLine + 'La versión previa se conserva en: ' + $replacementBackupPath)
          if ($restore.error) { $failureOutput += ([Environment]::NewLine + [string]$restore.error) }
        }
      }
      return @{ok=$false;message=[string]$created.message;output=$failureOutput;path=$failurePath;failedProjectPath=$(if($failedProjectPath){$failedProjectPath}else{$null});titleId=$titleId;backend=$backend;backupPath=$(if($replacementBackupPath){$replacementBackupPath}else{$null})}
    }

    $projectRoot = [IO.Path]::GetFullPath([string]$created.path)
    $workspaceRoot = [IO.Path]::GetFullPath($script:Workspace) + [IO.Path]::DirectorySeparatorChar
    if (!$projectRoot.StartsWith($workspaceRoot,[StringComparison]::OrdinalIgnoreCase)) {
      throw 'El generador produjo una ruta fuera del workspace autorizado.'
    }

    if ($backend -eq 'opengl-ui') {
      $sdkSeed = SeedProjectOpenGlSdkCache $projectRoot
      if ($sdkSeed.seeded -and $script:ActiveBuildLogPath) { WriteBuildJobLog $script:ActiveBuildLogPath 'SDK ps5-opengl copiado desde toolchains/ps5-opengl-sdk con SHA-256 verificado.' }
      elseif(!$sdkSeed.seeded -and $script:ActiveBuildLogPath) { WriteBuildJobLog $script:ActiveBuildLogPath ('No hay tarball local del SDK en toolchains/ps5-opengl-sdk: '+[string]$sdkSeed.reason) 'WARN' }
    }

    if ($backend -eq 'opengl-ui') {
      $sourcePath = Join-Path $projectRoot 'src/concepts/ps5hs_generated.cpp'
      $headerPath = Join-Path $projectRoot 'src/concepts/concepts.hpp'
      $registryPath = Join-Path $projectRoot 'src/concepts/registry.cpp'
      foreach ($requiredPath in @($headerPath,$registryPath,(Join-Path $projectRoot 'Makefile'),(Join-Path $projectRoot 'tools/build.sh'))) {
        if (!(Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
          throw "La plantilla OpenGL no contiene el archivo requerido: $requiredPath"
        }
      }
      $headerOriginal = Get-Content -LiteralPath $headerPath -Raw
      $headerUpdated = $headerOriginal
      if ($headerUpdated -notmatch 'make_ps5hs_generated') {
        $needle = '} // namespace hui::concepts'
        if (!$headerUpdated.Contains($needle)) { throw 'No se pudo localizar el límite del namespace en concepts.hpp.' }
        $declaration = 'std::unique_ptr<app::Concept> make_ps5hs_generated(app::Context &context);'
        $headerUpdated = $headerUpdated.Replace($needle,($declaration + [Environment]::NewLine + [Environment]::NewLine + $needle))
      }
      $registry = @'
 // Generated registry: exposes the Studio screen as the active UI concept.
#include "concepts/concepts.hpp"
namespace hui::app {
std::span<const ConceptFactory> concept_registry() {
    static constexpr ConceptFactory kFactories[] = { concepts::make_ps5hs_generated };
    return kFactories;
}
} // namespace hui::app
'@
      $integrationPaths = @('src/concepts/concepts.hpp','src/concepts/registry.cpp','src/concepts/ps5hs_generated.cpp')
      $null = InvokePS5HSNativeModificationWithAudit -ProjectRoot $projectRoot -Backend $backend -Operation 'integrate-opengl-generated-screen' -PermissionKey 'allowOpenGlTemplateIntegration' -RelativePaths $integrationPaths -Policy $policy -SourceRepository 'blackbearreloaded/ps5-homebrew-ui' -Action {
        if ($headerUpdated -cne $headerOriginal) { WriteUtf8 $headerPath $headerUpdated }
        WriteUtf8 $registryPath $registry
        WriteUtf8 $sourcePath $code
      }
    } else {
      $samplesPath = Join-Path $projectRoot 'ps5/src/samples.cpp'
      if (!(Test-Path $samplesPath -PathType Leaf)) { throw 'El título Vulkan generado no contiene ps5/src/samples.cpp.' }
      $samplesText = Get-Content -LiteralPath $samplesPath -Raw
      $programMatch = [regex]::Match($samplesText,'(?s)#define PS5_SAMPLES\s*\\\s*SAMPLE\(([A-Za-z0-9_]+),')
      if (!$programMatch.Success) { throw 'No se pudo resolver la ruta del programa Vulkan desde src/samples.cpp.' }
      $programId = $programMatch.Groups[1].Value
      $sourceRelative = 'examples/' + $programId + '/kit/screen.cpp'
      $sourcePath = Join-Path $projectRoot ($sourceRelative.Replace('/',[IO.Path]::DirectorySeparatorChar))
      if (!(Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "El generador Vulkan no dejó la pantalla del programa esperado: $sourcePath"
      }
      $null = InvokePS5HSNativeModificationWithAudit -ProjectRoot $projectRoot -Backend $backend -Operation 'integrate-vulkan-generated-screen' -PermissionKey 'allowVulkanTemplateIntegration' -RelativePaths @($sourceRelative) -Policy $policy -SourceRepository 'mihawk-99/PS5_VulkanTemplate' -Action { WriteUtf8 $sourcePath $code }
    }
    if ($backend -eq 'opengl-ui') {
      $projectMetaPath = Join-Path $projectRoot '.ps5hs-project.json'
      if (!(Test-Path -LiteralPath $projectMetaPath -PathType Leaf)) { throw 'No se encuentra el manifiesto del proyecto OpenGL generado.' }
      try { $projectMeta = Get-Content -LiteralPath $projectMetaPath -Raw | ConvertFrom-Json }
      catch { throw 'El manifiesto del título OpenGL generado no se puede leer.' }
      if ([string]$projectMeta.schema -ne 'ps5hs-native-project' -or [string]$projectMeta.template -ne 'hui-gl') {
        throw 'El título generado no coincide con la plantilla OpenGL esperada.'
      }
      Add-Member -InputObject $projectMeta -NotePropertyName 'generatedFromStudio' -NotePropertyValue $true -Force
      if ($policy.allowOpenGlRuntimeProfile) { Add-Member -InputObject $projectMeta -NotePropertyName 'nativeRuntimeProfile' -NotePropertyValue 'standalone-native-ui-v1' -Force }
      $null = InvokePS5HSNativeModificationWithAudit -ProjectRoot $projectRoot -Backend $backend -Operation 'write-opengl-studio-project-metadata' -PermissionKey $integrationPermissionKey -RelativePaths @('.ps5hs-project.json') -Policy $policy -SourceRepository 'blackbearreloaded/ps5-homebrew-ui' -Action {
        WriteUtf8 $projectMetaPath (ConvertTo-Json -InputObject $projectMeta -Depth 10)
      }
      if (!$policy.allowOpenGlRuntimeProfile) { WriteBuildJobLog $script:ActiveBuildLogPath 'Se conserva el comportamiento de runtime upstream: el desarrollador no autorizó desactivar el HUD/capturas de mando.' }
    }
    $incomingVisualAssets = @($Body.nativeAssets | Where-Object { $_ })
    if ($incomingVisualAssets.Count -gt 0) {
      $assetIds = @()
      foreach ($asset in $incomingVisualAssets) {
        $assetId = [string]$asset.id
        if ($assetId -notmatch '^[A-Za-z0-9_-]{1,80}$') { throw 'ID de recurso nativo no válido.' }
        $assetIds += $assetId
      }
      $assetMutationPaths = @('assets/ps5hs/manifest.json') + @($assetIds | Select-Object -Unique | ForEach-Object { 'assets/ps5hs/' + $_ + '.rgba' })
      $assetResult = InvokePS5HSNativeModificationWithAudit -ProjectRoot $projectRoot -Backend $backend -Operation 'write-user-selected-native-image-assets' -PermissionKey $integrationPermissionKey -RelativePaths $assetMutationPaths -Policy $policy -SourceRepository 'user-supplied-assets' -Action { WriteNativeVisualAssets $Body $projectRoot }
    } else { $assetResult = WriteNativeVisualAssets $Body $projectRoot }
    if ($Body.nativeFont -and ![string]::IsNullOrWhiteSpace([string]$Body.nativeFont.base64)) {
      $unicodeFontResult = InvokePS5HSNativeTreeModificationWithAudit -ProjectRoot $projectRoot -Backend $backend -Operation 'prepare-custom-unicode-font-tools-and-atlases' -PermissionKey 'allowCustomUnicodeFont' -Policy $policy -SourceRepository 'blackbearreloaded/ps5-homebrew-ui' -Action { PrepareNativeUnicodeFonts $Body $projectRoot $backend }
    } else { $unicodeFontResult = PrepareNativeUnicodeFonts $Body $projectRoot $backend }
    if ($unicodeFontResult.enabled) {
      $assetResult.unicodeFont = $unicodeFontResult
      WriteBuildJobLog $script:ActiveBuildLogPath ("Fuente Unicode personalizada lista: " + [string]$unicodeFontResult.fileName + "; " + [string]$unicodeFontResult.glyphCount + " glifos. El build conservará los atlas personalizados.")
    }
    if ($backend -eq 'vulkan-ui') {
      $samplesPath = Join-Path $projectRoot 'ps5/src/samples.cpp'
      if (!(Test-Path $samplesPath -PathType Leaf)) { throw 'La plantilla Vulkan no contiene ps5/src/samples.cpp para resolver el programa de texturas.' }
      $samplesText = Get-Content -LiteralPath $samplesPath -Raw
      $programMatch = [regex]::Match($samplesText,'(?s)#define PS5_SAMPLES\s*\\\s*SAMPLE\(([A-Za-z0-9_]+),')
      if (!$programMatch.Success) { throw 'No se pudo resolver el identificador de programa Vulkan para el runtime de texturas.' }
      $programId = $programMatch.Groups[1].Value
      if ($assetResult.count -gt 0) {
        $assetIntegrationPaths = @('ps5/assets.json','ps5/licenses/PS5HS-USER-ASSETS.txt')
        $vulkanAssetResult = InvokePS5HSNativeModificationWithAudit -ProjectRoot $projectRoot -Backend $backend -Operation 'register-vulkan-user-assets' -PermissionKey 'allowVulkanTemplateIntegration' -RelativePaths $assetIntegrationPaths -Policy $policy -SourceRepository 'mihawk-99/PS5_VulkanTemplate' -Action { RegisterVulkanNativeAssets $Body $projectRoot }
        $programId = [string]$vulkanAssetResult.programId
        $assetResult.manifest = [string]$vulkanAssetResult.manifest
      }
      $runtimeRelative = 'examples/' + $programId + '/' + $programId + '.cpp'
      $runtimeScreenRelative = 'examples/' + $programId + '/kit/screen.cpp'
      $null = InvokePS5HSNativeModificationWithAudit -ProjectRoot $projectRoot -Backend $backend -Operation 'install-vulkan-texture-runtime' -PermissionKey 'allowVulkanTemplateIntegration' -RelativePaths @($runtimeRelative,$runtimeScreenRelative,'ps5/ui/kit.hpp') -Policy $policy -SourceRepository 'mihawk-99/PS5_VulkanTemplate' -Action { InstallVulkanTextureRuntime $Body $projectRoot $programId }
      $assetResult.runtimeSource = Join-Path (Join-Path (Join-Path $projectRoot 'examples') $programId) ($programId + '.cpp')
      if ($assetResult.count -eq 0) {
        WriteBuildJobLog $script:ActiveBuildLogPath 'No se han seleccionado imágenes nativas; el runtime Vulkan conserva el contrato de textura con su registro vacío.'
      }
    }
    $markerPath = Join-Path $projectRoot '.ps5hs-project.json'
    $null = InvokePS5HSNativeModificationWithAudit -ProjectRoot $projectRoot -Backend $backend -Operation 'write-visual-project-metadata' -PermissionKey $integrationPermissionKey -RelativePaths @('ps5hs-model.json','.ps5hs-project.json') -Policy $policy -SourceRepository 'PS5 Homebrew Studio generated metadata' -Action {
      WriteUtf8 (Join-Path $projectRoot 'ps5hs-model.json') (ConvertTo-Json -InputObject $Body.project -Depth 100)
      $projectMetaForAudit = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
      $projectMetaForAudit | Add-Member -NotePropertyName visualBackend -NotePropertyValue $backend -Force
      $projectMetaForAudit | Add-Member -NotePropertyName generatedFromStudio -NotePropertyValue $true -Force
      $projectMetaForAudit | Add-Member -NotePropertyName generatedSource -NotePropertyValue ([string]$sourcePath) -Force
      $projectMetaForAudit | Add-Member -NotePropertyName visualModel -NotePropertyValue 'ps5hs-model.json' -Force
      WriteUtf8 $markerPath (ConvertTo-Json -InputObject $projectMetaForAudit -Depth 20)
    }
    $meta = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json

    $presentationBody = @{ path = $projectRoot; nativeModifications = $policy }
    $presentationRequested = $false
    foreach ($assetKey in @('icon','selectionBackground','launchBackground','audio')) {
      if ($null -ne $Body.$assetKey) {
        $presentationBody[$assetKey] = $Body.$assetKey
        $presentationRequested = $true
      }
    }

    $parts = @()
    if ($created.output) { $parts += [string]$created.output }
    $parts += "Pantalla C++20 inyectada en plantilla upstream: $sourcePath"
    $parts += 'Se conservaron el renderer, los metadatos y el pipeline de compilación del repositorio.'
    if ($backend -eq 'vulkan-ui' -and $assetResult.count -gt 0) { $parts += 'Texturas Vulkan RGBA8 conectadas a VkRenderer::create_texture y registradas en ps5/assets.json.' }
    if ($assetResult.count -gt 0) { $parts += "Recursos RGBA empaquetados: $($assetResult.count) en $($assetResult.manifest)." }
    if ($presentationRequested) {
      $presentationResult = UpdateNativePresentationAssets $presentationBody
      $parts += 'Recursos de presentación aplicados antes de compilar (sce_sys/icon0.png, pic0.dds, pic1.dds y/o snd0.at9).'
      if ($presentationResult.output) { $parts += [string]$presentationResult.output }
      WriteBuildJobLog $script:ActiveBuildLogPath 'Recursos de presentación preparados por la herramienta upstream antes de iniciar el build.'
    }
    WriteBuildJobLog $script:ActiveBuildLogPath 'Código C++20 generado e inyectado. Preparando dependencias y compilación…'
    $build = BuildNativeProject $projectRoot $false $titleId $name $policy
    if ($build.output) { $parts += [string]$build.output }
    $combined = $parts -join "`r`n"
    if ($build.ok) {
      if ($replacementBackupPath -and (Test-Path -LiteralPath $replacementBackupPath -PathType Container)) {
        try {
          Remove-Item -LiteralPath $replacementBackupPath -Recurse -Force -ErrorAction Stop
          $replacementBackupPath = ''
        } catch {
          $combined += ([Environment]::NewLine + 'La compilación terminó bien, pero no se pudo borrar la copia previa. Se conserva en: ' + $replacementBackupPath)
        }
      }
      return @{ok=$true;message='La pantalla visual se generó como C++20, se compiló con el pipeline upstream y se encontró un artefacto verificable.';output=$combined;path=$projectRoot;artifact=$build.artifact;titleId=$titleId;backend=$backend;templateId=$meta.template;exitCode=0;backupPath=$(if($replacementBackupPath){$replacementBackupPath}else{$null})}
    }
    $failedProjectPath = ''
    $resultPath = $projectRoot
    $failureMessage = 'La pantalla C++ se ha generado, pero el pipeline upstream no produjo un artefacto verificable.'
    if ($replacementBackupPath -and (Test-Path -LiteralPath $replacementBackupPath -PathType Container)) {
      $restore = RestoreNativeVisualReplacement $targetCandidate $replacementBackupPath
      $failedProjectPath = [string]$restore.failedPath
      $replacementBackupPath = [string]$restore.backupPath
      if ($restore.restored) {
        $resultPath = $targetCandidate
        $failureMessage = 'La compilación falló. Se ha restaurado la versión anterior; el intento fallido se conserva por separado.'
        if ($failedProjectPath) { $combined += ([Environment]::NewLine + 'Proyecto fallido preservado para diagnóstico: ' + $failedProjectPath) }
      } else {
        $combined += ([Environment]::NewLine + 'No se pudo restaurar la versión previa automáticamente.')
        if ($replacementBackupPath) { $combined += ([Environment]::NewLine + 'Copia previa preservada en: ' + $replacementBackupPath) }
        if ($restore.error) { $combined += ([Environment]::NewLine + [string]$restore.error) }
      }
    }
    return @{ok=$false;message=$failureMessage;output=$combined;path=$resultPath;failedProjectPath=$(if($failedProjectPath){$failedProjectPath}else{$null});titleId=$titleId;backend=$backend;templateId=$meta.template;artifact=$build.artifact;exitCode=$build.exitCode;diagnostics=$build.diagnostics;backupPath=$(if($replacementBackupPath){$replacementBackupPath}else{$null})}
  } catch {
    $failureOutput = $_.Exception.Message + "`r`n" + [string]$created.output
    $failedProjectPath = ''
    $failurePath = $projectRoot
    if ($replacementBackupPath -and (Test-Path -LiteralPath $replacementBackupPath -PathType Container)) {
      $restore = RestoreNativeVisualReplacement $targetCandidate $replacementBackupPath
      $failedProjectPath = [string]$restore.failedPath
      $replacementBackupPath = [string]$restore.backupPath
      if ($restore.restored) {
        $failurePath = $targetCandidate
        $failureOutput += ([Environment]::NewLine + 'Se restauró la versión previa en su carpeta original.')
        if ($failedProjectPath) { $failureOutput += ([Environment]::NewLine + 'El proyecto fallido se conserva en: ' + $failedProjectPath) }
      } else {
        if ($replacementBackupPath) { $failureOutput += ([Environment]::NewLine + 'La versión previa está preservada en: ' + $replacementBackupPath) }
        if ($restore.error) { $failureOutput += ([Environment]::NewLine + [string]$restore.error) }
      }
    }
    return @{ok=$false;message='No se pudo generar o compilar el proyecto visual nativo.';output=$failureOutput;path=$failurePath;failedProjectPath=$(if($failedProjectPath){$failedProjectPath}else{$null});titleId=$titleId;backend=$backend;backupPath=$(if($replacementBackupPath){$replacementBackupPath}else{$null})}
  }
}

function SaveProject($P,[string]$Code) {
  $name = Slug ([string]$P.name)
  $dir = Join-Path $script:Workspace $name
  if (Test-Path -LiteralPath $dir) {
    $dirItem = Get-Item -LiteralPath $dir -Force
    if (($dirItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or !$dirItem.PSIsContainer) {
      return @{ok=$false;message='No se puede guardar: la carpeta de destino es un archivo o un enlace. No se ha escrito nada.';path=$dir;name=$name}
    }
    $nativeMarker = Join-Path $dir '.ps5hs-project.json'
    $sharpMarker = Join-Path $dir 'native/.ps5hs-sharp-project.json'
    $nativeParam = Join-Path $dir 'sce_sys/param.json'
    $nativeMakefile = Join-Path $dir 'Makefile'
    $nativeMainCpp = Join-Path $dir 'src/main.cpp'
    $vulkanBuild = Join-Path $dir 'ps5/tools/build.sh'
    $vulkanParam = Join-Path $dir 'ps5/sce_sys/param.json'
    $looksLikeNativeTitle = ((Test-Path -LiteralPath $nativeParam -PathType Leaf) -and ((Test-Path -LiteralPath $nativeMakefile -PathType Leaf) -or (Test-Path -LiteralPath $nativeMainCpp -PathType Leaf))) -or
      ((Test-Path -LiteralPath $vulkanBuild -PathType Leaf) -and (Test-Path -LiteralPath $vulkanParam -PathType Leaf))
    $payloadMarker = Join-Path $dir '.ps5hs-payload-project.json'
    $ownedPs5LinkProject = $false
    if ([string]$P.backend -eq 'ps5link' -and (Test-Path -LiteralPath $nativeMarker -PathType Leaf)) {
      try { $existingNativeMeta = Get-Content -LiteralPath $nativeMarker -Raw | ConvertFrom-Json; $ownedPs5LinkProject = ($existingNativeMeta.schema -eq 'ps5hs-native-project' -and $existingNativeMeta.template -eq 'ps5link' -and $existingNativeMeta.generatedFromStudio -eq $true) } catch { $ownedPs5LinkProject = $false }
    }
    $ownedPayloadProject = $false
    if ([string]$P.backend -eq 'payload' -and (Test-Path -LiteralPath $payloadMarker -PathType Leaf)) {
      try { $payloadMeta = Get-Content -LiteralPath $payloadMarker -Raw | ConvertFrom-Json; $ownedPayloadProject = ($payloadMeta.schema -eq 'ps5hs-payload-project' -and $payloadMeta.backend -eq 'payload') } catch { $ownedPayloadProject = $false }
    }
    if (((Test-Path -LiteralPath $nativeMarker -PathType Leaf) -and !$ownedPs5LinkProject) -or (Test-Path -LiteralPath $sharpMarker -PathType Leaf) -or $looksLikeNativeTitle -or ((Test-Path -LiteralPath $payloadMarker -PathType Leaf) -and !$ownedPayloadProject)) {
      return @{ok=$false;message='No se puede guardar el proyecto visual con este nombre porque la carpeta parece pertenecer a un título nativo/OpenGL/Vulkan o SharpProspero. Cambia el nombre del proyecto visual para evitar alterar sus archivos.';path=$dir;name=$name;collision=$true}
    }
  } else {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  WriteProjectFiles $P $Code $dir
  if([string]$P.backend -eq 'ps5link' -and $P.manualCode -ne $true){$null=WritePS5LinkVisualBridge $P $dir;$null=WritePS5LinkGameSceneHeader $P $dir}
  if([string]$P.backend -eq 'payload'){$sourceName=if([string]$P.payloadLanguage -eq 'cpp'){'src/main.cpp'}else{'src/main.c'};$description=if([string]$P.payloadLanguage -eq 'cpp'){'Entrada C++20 del payload PS5. Usa Compilar para producir un ELF64 con el PS5 Payload SDK local.'}else{'Entrada C del payload PS5. Usa Compilar para producir un ELF64 con el PS5 Payload SDK local.'}}
  elseif([string]$P.backend -in @('opengl-ui','vulkan-ui')){$sourceName='GeneratedScreen.cpp';$description='C++20 generado contra el contrato hui::app::Concept. Usa Compilar para inyectarlo en la plantilla upstream y construir un título.'}
  elseif([string]$P.backend -eq 'vulkan-compute'){$sourceName='compute-graph.json';$description='Grafo editable con shaders GLSL 450, recursos, dimensiones y pases Vulkan Compute. Compilar SPIR-V ejecuta el compilador local y guarda los módulos verificados en una carpeta de workspace separada.'}
  elseif([string]$P.backend -eq 'ps5link'){$sourceName='src/main.c';$description=if($P.manualCode -eq $true){'Código C del juego en modo manual.'}else{'Motor AGC generado desde Juego 3D; escena, interfaz y flujos generados en src/.'}}
  else{$sourceName='Program.cs';$description='Código C# generado/actual.'}
  if([string]$P.payloadBuildMode -ne 'upstream-makefile'){
    $readme="# $($P.name)`r`n`r`nProyecto PS5 Homebrew Studio. Backend: $($P.backend).`r`n`r`n- project.json: modelo del editor.`r`n- ${sourceName}: $description`r`n- assets/: recursos importados.`r`n"
    WriteUtf8 (Join-Path $dir 'README.md') $readme
  }
  return @{ok=$true;path=$dir;name=$name}
}
function ExportProject($P,[string]$Code) {
  $name=Slug $P.name;$id=[guid]::NewGuid().ToString('N').Substring(0,8);$dir=Join-Path $script:Exports ($name+'-'+$id);New-Item -ItemType Directory -Force -Path $dir|Out-Null;WriteProjectFiles $P $Code $dir
  if([string]$P.backend -eq 'ps5link' -and $P.manualCode -ne $true){$null=WritePS5LinkVisualBridge $P $dir;$null=WritePS5LinkGameSceneHeader $P $dir}
  if([string]$P.backend -in @('opengl-ui','vulkan-ui')){$backendNote='GeneratedScreen.cpp implementa la pantalla nativa. El ZIP contiene el modelo y el fuente generado, no un eboot.bin compilado; pulsa Compilar para usar el generador y pipeline upstream.'}
  elseif([string]$P.backend -eq 'vulkan-compute'){$backendNote='compute-graph.json contiene el grafo editable, sus shaders GLSL 450 y los recursos de almacenamiento. El ZIP no incluye binarios SPIR-V; pulsa Compilar SPIR-V para generarlos y verificarlos localmente.'}
  elseif([string]$P.backend -eq 'payload'){$sourceName=if([string]$P.payloadLanguage -eq 'cpp'){'src/main.cpp'}else{'src/main.c'};$backendNote="El código fuente del payload se encuentra en $sourceName. Exportar guarda el proyecto, no compila el ELF; pulsa Compilar para obtenerlo."}
  elseif([string]$P.backend -eq 'ps5link'){$backendNote=if($P.manualCode -eq $true){'src/main.c contiene el código C manual y src/ps5hs_visual.c contiene el puente de componentes.'}else{'El proyecto incluye src/main.c generado por el motor AGC visual, la escena en src/ps5hs_game_scene.h, los flujos en src/ps5hs_visual.c y el modelo visual en project.json.'}}
  else{$backendNote='El código fuente generado se encuentra en Program.cs.'}
  WriteUtf8 (Join-Path $dir 'README.md') ("# $($P.name)`r`n`r`nProyecto exportado desde PS5 Homebrew Studio.`r`nBackend: $($P.backend).`r`n$backendNote`r`nEl modelo editable está en project.json; los recursos importados están en assets/. Consulta las licencias y dependencias de cada SDK en su repositorio original. No se incluyen binarios propietarios de Sony.`r`n")
  $file=$name+'-'+$id+'.zip';$path=Join-Path $script:Exports $file;Compress-Archive -Path (Join-Path $dir '*') -DestinationPath $path -CompressionLevel Optimal -Force;return @{ok=$true;url='/downloads/'+$file;fileName=$file;path=$path}
}
function TestPS5HSPayloadElf([string]$Path) {
  if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $item = Get-Item -LiteralPath $Path -Force
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -lt 64) { return $false }
  $stream = $null
  try {
    $stream = [IO.File]::OpenRead($Path)
    $header = New-Object byte[] 20
    if ($stream.Read($header,0,$header.Length) -ne $header.Length) { return $false }
    $type = [BitConverter]::ToUInt16($header,16)
    $machine = [BitConverter]::ToUInt16($header,18)
    return ($header[0] -eq 0x7f -and $header[1] -eq 0x45 -and $header[2] -eq 0x4c -and $header[3] -eq 0x46 -and $header[4] -eq 2 -and $header[5] -eq 1 -and $type -in @(2,3,0xFE10) -and $machine -eq 62)
  } catch { return $false }
  finally { if ($stream) { $stream.Dispose() } }
}
function TestPS5HSPayloadRelativePath([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Contains('\') -or $Value.Contains(':') -or $Value -match '[\x00-\x1f]' -or $Value.StartsWith('/')) { return $false }
  return ($Value -match '^[A-Za-z0-9 _().+/-]+$' -and @($Value.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count -eq 0)
}
function GetPS5HSPayloadScopedPath([string]$Scope,[string]$RelativePath,[string]$ProjectRoot) {
  if (!(TestPS5HSPayloadRelativePath $RelativePath)) { throw ("Ruta payload no segura: " + $RelativePath) }
  $base = if ($Scope -eq 'project') { $ProjectRoot } elseif ($Scope -eq 'ide') { $script:Root } else { throw ("Ámbito local no admitido: " + $Scope) }
  $baseFull = [IO.Path]::GetFullPath($base)
  $candidate = [IO.Path]::GetFullPath((Join-Path $baseFull ($RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar)))
  if (!$candidate.StartsWith(($baseFull.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)) { throw ("Ruta fuera de la raíz " + $Scope + ": " + $RelativePath) }
  $null = AssertPS5HSNativePathNoReparsePoints -Path $candidate
  return $candidate
}
function GetPS5HSPayloadDependencySpec([string]$ProjectRoot,$Marker,[bool]$RequireBuild=$false) {
  $relative = if ($Marker -and $Marker.dependenciesManifest) { [string]$Marker.dependenciesManifest } else { '.ps5hs-payload-dependencies.json' }
  try { $projectManifest = GetPS5HSPayloadScopedPath 'project' $relative $ProjectRoot }
  catch { return @{ok=$false;message='Ruta no segura para el manifiesto de dependencias.';output=$_.Exception.Message} }
  $profileName = if ($Marker -and $Marker.dependencyProfile) { [string]$Marker.dependencyProfile } else { '' }
  if (!$profileName -and $Marker -and [string]$Marker.sourceRepository -eq 'drakmor/ShadowMountPlus') { $profileName = 'shadowmountplus' }
  if ($profileName -and $profileName -notmatch '^[a-z][a-z0-9_-]{0,63}$') { return @{ok=$false;message='Identificador de perfil de dependencias inválido.';output=$profileName} }
  if (Test-Path -LiteralPath $projectManifest -PathType Leaf) { $manifestPath = $projectManifest }
  elseif ($profileName) {
    $manifestPath = Join-Path $PSScriptRoot ('payload-dependency-profiles\' + $profileName + '.json')
    if (!(Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return @{ok=$false;message='No se encuentra el perfil offline de dependencias solicitado.';output=$manifestPath} }
    try { $null = AssertPS5HSNativePathNoReparsePoints -Path $manifestPath } catch { return @{ok=$false;message='El perfil de dependencias atraviesa una ruta enlazada.';output=$_.Exception.Message} }
  } elseif ($RequireBuild) {
    return @{ok=$false;message='El payload upstream necesita un manifiesto local de compilación y dependencias.';output='Añade .ps5hs-payload-dependencies.json con build.makefile, build.target y build.artifact. No se consultará Internet.'}
  } else {
    $empty = [pscustomobject]@{schema='ps5hs-payload-dependencies';version=1;requiredCommands=@();requiredPaths=@();packages=@();compiler=[pscustomobject]@{cFlags=@();cxxFlags=@();linkFlags=@();libraries=@();linkFiles=@()};build=$null}
    return @{ok=$true;path='';profile='';manifest=$empty}
  }
  try { $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json }
  catch { return @{ok=$false;message='El manifiesto de dependencias no es JSON válido.';output=$manifestPath + ': ' + $_.Exception.Message} }
  if ($manifest.schema -ne 'ps5hs-payload-dependencies' -or $manifest.version -ne 1) { return @{ok=$false;message='Esquema/versión del manifiesto de dependencias no compatible.';output=$manifestPath} }
  if ($null -ne $manifest.packages -and $manifest.packages -is [string]) { return @{ok=$false;message='packages debe ser una lista.';output=$manifestPath} }
  $ids = @()
  foreach ($package in @($manifest.packages)) { if (!$package -or [string]$package.id -notmatch '^[a-z][a-z0-9_-]{0,63}$') { return @{ok=$false;message='Cada dependencia necesita un id seguro.';output=$manifestPath} }; $ids += [string]$package.id }
  if (@($ids | Select-Object -Unique).Count -ne $ids.Count) { return @{ok=$false;message='El manifiesto repite un id de paquete.';output=$manifestPath} }
  $toolchainMajor = $null
  $declaredToolchainMajor = if ($manifest.toolchain -and $manifest.toolchain.PSObject.Properties['llvmMajor']) { [string]$manifest.toolchain.llvmMajor } else { '' }
  $legacyToolchainMajor = if ($manifest.build -and $manifest.build.PSObject.Properties['llvmMajor']) { [string]$manifest.build.llvmMajor } else { '' }
  if ($declaredToolchainMajor -and $legacyToolchainMajor -and $declaredToolchainMajor -ne $legacyToolchainMajor) { return @{ok=$false;message='toolchain.llvmMajor y build.llvmMajor especifican versiones distintas.';output=$manifestPath} }
  $toolchainMajor = if ($declaredToolchainMajor) { $declaredToolchainMajor } else { $legacyToolchainMajor }
  if ($toolchainMajor -and ($toolchainMajor -notmatch '^[0-9]{2}$' -or [int]$toolchainMajor -lt 15)) { return @{ok=$false;message='La versión LLVM solicitada debe ser compatible con PS5 Payload SDK (LLVM 15 o posterior).' ;output=$toolchainMajor} }
  if ($null -ne $manifest.hostPackages -and $manifest.hostPackages -is [string]) { return @{ok=$false;message='hostPackages debe ser una lista de paquetes Ubuntu.';output=$manifestPath} }
  $hostPackageIds = @()
  foreach ($hostPackage in @($manifest.hostPackages)) {
    if (!$hostPackage -or [string]$hostPackage.id -notmatch '^[a-z][a-z0-9_-]{0,63}$' -or [string]$hostPackage.package -notmatch '^[a-z0-9][a-z0-9+.-]{0,127}$') { return @{ok=$false;message='Cada paquete host necesita un id y nombre Ubuntu válidos.';output=$manifestPath} }
    if ($hostPackage.PSObject.Properties['version'] -and $null -ne $hostPackage.version -and [string]$hostPackage.version -notmatch '^[A-Za-z0-9.+:~_-]{1,128}$') { return @{ok=$false;message='La versión fijada de un paquete Ubuntu no es válida.';output=[string]$hostPackage.id} }
    $hostPackageIds += [string]$hostPackage.id
  }
  if (@($hostPackageIds | Select-Object -Unique).Count -ne $hostPackageIds.Count) { return @{ok=$false;message='El manifiesto repite un id de paquete host.';output=$manifestPath} }
  if ($RequireBuild -and (!$manifest.build -or !(TestPS5HSPayloadRelativePath ([string]$manifest.build.makefile)) -or [string]$manifest.build.target -notmatch '^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$' -or !(TestPS5HSPayloadRelativePath ([string]$manifest.build.artifact)))) { return @{ok=$false;message='El perfil upstream debe declarar makefile, target y artifact seguros.';output=$manifestPath} }
  if ($RequireBuild -and [string]$manifest.build.compiler -and [string]$manifest.build.compiler -ne 'ps5') { return @{ok=$false;message='El compilador debe ser el PS5 Payload SDK local.';output=[string]$manifest.build.compiler} }
  if ($RequireBuild -and $manifest.build.PSObject.Properties['cleanTarget'] -and [string]$manifest.build.cleanTarget -and [string]$manifest.build.cleanTarget -notmatch '^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$') { return @{ok=$false;message='El objetivo clean del perfil no es seguro.';output=[string]$manifest.build.cleanTarget} }
  if ($RequireBuild -and $manifest.build.referenceBuild) {
    $reference = $manifest.build.referenceBuild
    $referenceTime = $reference.buildTime
    if ($referenceTime -is [datetime]) { $referenceTime = $referenceTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ',[System.Globalization.CultureInfo]::InvariantCulture) }
    else { $referenceTime = [string]$referenceTime }
    if ([string]$reference.sourceCommit -notmatch '^[0-9a-fA-F]{40}$' -or [string]$reference.versionTag -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$' -or $referenceTime -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$' -or [string]$reference.sha256 -notmatch '^[0-9a-fA-F]{64}$') { return @{ok=$false;message='Los metadatos del build de referencia están incompletos o no son válidos.';output=$manifestPath} }
    $reference.buildTime = $referenceTime
  }
  return @{ok=$true;path=$manifestPath;profile=$profileName;manifest=$manifest;llvmMajor=$toolchainMajor}
}
function ResolvePS5HSPayloadToolchain($Spec,$Wsl,[string]$Distribution) {
  $resolver = Join-Path $PSScriptRoot 'offline/resolve-payload-toolchain.py'
  if (!(Test-Path -LiteralPath $resolver -PathType Leaf)) { return @{ok=$false;message='Falta el selector local de compilador y enlazador LLVM.';output=$resolver;exitCode=2} }
  try {
    $resolverWsl = ConvertToWslPath $resolver
    $manifestWsl = if ($Spec.path) { ConvertToWslPath ([string]$Spec.path) } else { '' }
  } catch { return @{ok=$false;message='No se pudo validar la ruta del selector de toolchain.';output=$_.Exception.Message;exitCode=2} }
  # WSL's project user remains unprivileged; only the package resolver runs as
  # root so apt can install the project's declared packages from Ubuntu repos.
  $args = @('-d',$Distribution,'--user','root','--exec','python3',$resolverWsl,'--sdk-root','/opt/ps5-payload-sdk')
  if ($manifestWsl) { $args += @('--manifest',$manifestWsl) }
  $output = @(& $Wsl.path @args 2>&1 | ForEach-Object { $_.ToString() })
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) { return @{ok=$false;message='No se pudo resolver el compilador/enlazador LLVM del payload.';output=($output -join [Environment]::NewLine);exitCode=$exitCode} }
  try { $resolved = ($output -join [Environment]::NewLine) | ConvertFrom-Json }
  catch { return @{ok=$false;message='El selector LLVM devolvió un resultado no válido.';output=($output -join [Environment]::NewLine);exitCode=2} }
  if ($resolved.schema -ne 'ps5hs-payload-toolchain-resolved' -or !$resolved.toolchain.major -or !$resolved.toolchain.llvmConfig -or !$resolved.toolchain.compiler -or !$resolved.toolchain.compilerCxx -or !$resolved.toolchain.linker) { return @{ok=$false;message='El selector LLVM no confirmó una pareja compatible de compiladores y enlazador.';output=($output -join [Environment]::NewLine);exitCode=2} }
  $choice = if ($resolved.selection -eq 'explicit') { 'versión fijada por el proyecto' } else { 'versión compatible más reciente disponible en WSL/Ubuntu' }
  $lines = @('LLVM '+[string]$resolved.toolchain.version+' ('+$choice+'); compilador C: '+[string]$resolved.toolchain.compiler+'; compilador C++: '+[string]$resolved.toolchain.compilerCxx+'; enlazador: '+[string]$resolved.toolchain.linker+'; origen: '+[string]$resolved.source+'.')
  foreach ($package in @($resolved.hostPackages)) { $lines += ('Dependencia host '+[string]$package.id+': '+[string]$package.package+' '+[string]$package.resolvedVersion+' ('+[string]$package.source+').') }
  foreach ($package in @($resolved.provisionedPackages)) { $lines += ('Paquete Ubuntu instalado para este proyecto: '+[string]$package+'.') }
  foreach ($action in @($resolved.actions)) { $lines += ('Acción WSL: '+[string]$action.action+'; estado: '+[string]$action.status+'; salida: '+(([string]$action.output -replace '[\r\n]+',' ') -replace '\s{2,}',' ').Trim()) }
  foreach ($warning in @($resolved.warnings)) { $lines += ('Aviso de resolución: '+[string]$warning) }
  return @{ok=$true;resolved=$resolved;output=$lines}
}
function PreparePS5HSPayloadDependencies($Spec,[string]$ProjectRoot,$Wsl,[string]$Distribution) {
  $map = @{}
  if (!@($Spec.manifest.packages).Count) { return @{ok=$true;packages=$map;output=@()} }
  $installer = Join-Path $PSScriptRoot 'offline/install-payload-dependencies.py'
  if (!(Test-Path -LiteralPath $installer -PathType Leaf)) { return @{ok=$false;message='Falta el preparador local de dependencias payload.';output=$installer;exitCode=2} }
  try {
    $manifestWsl = ConvertToWslPath $Spec.path
    $projectWsl = ConvertToWslPath $ProjectRoot
    $ideWsl = ConvertToWslPath $script:Root
    $installerWsl = ConvertToWslPath $installer
    $cacheRoot = Join-Path $script:Runtime 'payload-dependencies'
    $null = AssertPS5HSNativePathNoReparsePoints -Path $script:Runtime
    $null = AssertPS5HSNativePathNoReparsePoints -Path $cacheRoot
    $cacheWsl = ConvertToWslPath $cacheRoot
  } catch { return @{ok=$false;message='No se pudieron validar las rutas de dependencias.';output=$_.Exception.Message;exitCode=2} }
  $args = @('-d',$Distribution,'--exec','python3',$installerWsl,'--manifest',$manifestWsl,'--project-root',$projectWsl,'--ide-root',$ideWsl,'--cache-root',$cacheWsl)
  $output = @(& $Wsl.path @args 2>&1 | ForEach-Object { $_.ToString() })
  if ($LASTEXITCODE -ne 0) { return @{ok=$false;message='No se pudieron preparar dependencias locales o descargar el archivo HTTPS fijado.';output=($output -join [Environment]::NewLine);exitCode=$LASTEXITCODE} }
  try { $resolved = ($output -join [Environment]::NewLine) | ConvertFrom-Json } catch { return @{ok=$false;message='El preparador devolvió un resultado no válido.';output=($output -join [Environment]::NewLine);exitCode=2} }
  if ($resolved.schema -ne 'ps5hs-payload-dependencies-resolved') { return @{ok=$false;message='El preparador no confirmó el esquema esperado.';output=($output -join [Environment]::NewLine);exitCode=2} }
  foreach ($package in @($resolved.packages)) { if (!$package.id -or !$package.root -or $map.ContainsKey([string]$package.id)) { return @{ok=$false;message='El preparador devolvió dependencias duplicadas/incompletas.';output=($output -join [Environment]::NewLine);exitCode=2} }; $map[[string]$package.id]=$package }
  return @{ok=$true;packages=$map;output=@($map.Values | ForEach-Object { 'Dependencia preparada: ' + $_.id + ' ' + $_.version + ' desde ' + $_.source + ' (' + $_.origin + ')' })}
}
function GetPS5HSPayloadManifestList($Object,[string]$Field) {
  if (!$Object -or !$Object.PSObject.Properties[$Field] -or $null -eq $Object.$Field) { return }
  if ($Object.$Field -is [string] -or $Object.$Field -isnot [System.Collections.IEnumerable]) { throw ($Field + ' debe ser una lista.') }
  $values = @($Object.$Field)
  foreach ($value in $values) { if ($value -isnot [string] -or $value -match '[\x00-\x1f]') { throw ($Field + ' contiene un valor inválido.') } }
  if ($values.Count -eq 0) { return }
  return $values
}
function NewPS5HSPayloadBuildConfig($Manifest,$PackageMap,[string]$ProjectRoot,[string]$Language,[string]$OutputPath) {
  $lines = New-Object 'System.Collections.Generic.List[string]'
  $lines.Add('# Generated by PS5 Homebrew Studio from the project dependency manifest.')
  $binPaths=@();$includeFlags=@();$libraryFlags=@();$libraryItems=@()
  foreach($id in @($PackageMap.Keys|Sort-Object)){
    $pkg=$PackageMap[$id];$root=[string]$pkg.root
    if($root -match '[\x00-\x1f#$]'){throw ('Ruta de dependencia incompatible con Make: '+$root)}
    $varId=$id.ToUpperInvariant() -replace '[^A-Z0-9]','_'
    $lines.Add('PS5HS_DEP_'+$varId+'_ROOT := '+$root)
    foreach($field in @('binDirs','includeDirs','libraryDirs')){
      foreach($rel in @(GetPS5HSPayloadManifestList $pkg $field)){
        if(!(TestPS5HSPayloadRelativePath $rel)){throw ('Ruta inválida en '+$id+'.'+$field+': '+$rel)}
        $resolved=$root.TrimEnd('/')+'/'+$rel
        if($field -eq 'binDirs'){$binPaths+= $resolved;$lines.Add('PS5HS_DEP_'+$varId+'_BIN := '+$resolved)}
        elseif($field -eq 'includeDirs'){$includeFlags+='-I'+(BashQuote $resolved);$lines.Add('PS5HS_DEP_'+$varId+'_INCLUDE := '+$resolved)}
        else{$libraryFlags+='-L'+(BashQuote $resolved);$lines.Add('PS5HS_DEP_'+$varId+'_LIB := '+$resolved)}
      }
    }
    foreach($lib in @(GetPS5HSPayloadManifestList $pkg 'libraries')){if($lib -notmatch '^[A-Za-z0-9_+-]+$'){throw ('Nombre de biblioteca inválido: '+$lib)};$libraryItems+='-l'+$lib}
    foreach($rel in @(GetPS5HSPayloadManifestList $pkg 'linkFiles')){if(!(TestPS5HSPayloadRelativePath $rel)){throw ('Ruta de enlace inválida: '+$rel)};$libraryItems+=(BashQuote ($root.TrimEnd('/')+'/'+$rel))}
  }
  $compiler=$Manifest.compiler
  $cFlags=@(GetPS5HSPayloadManifestList $compiler 'cFlags')
  $cxxFlags=@(GetPS5HSPayloadManifestList $compiler 'cxxFlags')
  $linkFlags=@(GetPS5HSPayloadManifestList $compiler 'linkFlags')
  foreach($token in @($cFlags)+@($cxxFlags)+@($linkFlags)){if($token -notmatch '^[A-Za-z0-9_./=,+:@%+-]+$'){throw ('Argumento de compilación no seguro: '+$token)}}
  if($Manifest.build){$linkFlags+=@(GetPS5HSPayloadManifestList $Manifest.build 'linkFlags')}
  foreach($token in $linkFlags){if($token -notmatch '^[A-Za-z0-9_./=,+:@%+-]+$'){throw ('Argumento de enlace no seguro: '+$token)}}
  foreach($lib in @(GetPS5HSPayloadManifestList $compiler 'libraries')){if($lib -notmatch '^[A-Za-z0-9_+-]+$'){throw ('Nombre de biblioteca inválido: '+$lib)};$libraryItems+='-l'+$lib}
  foreach($rel in @(GetPS5HSPayloadManifestList $compiler 'linkFiles')){
    if(!(TestPS5HSPayloadRelativePath $rel)){throw ('Ruta de enlace inválida: '+$rel)}
    $local=GetPS5HSPayloadScopedPath 'project' $rel $ProjectRoot
    if(!(Test-Path -LiteralPath $local -PathType Leaf)){throw ('Falta el archivo de enlace declarado: '+$local)}
    $libraryItems+=(BashQuote (ConvertToWslPath $local))
  }
  if($includeFlags.Count){$lines.Add('override CPPFLAGS += '+($includeFlags -join ' '))}
  if($cFlags.Count){$lines.Add('override CFLAGS += '+(($cFlags|ForEach-Object{BashQuote $_}) -join ' '))}
  if($cxxFlags.Count){$lines.Add('override CXXFLAGS += '+(($cxxFlags|ForEach-Object{BashQuote $_}) -join ' '))}
  if($libraryFlags.Count -or $linkFlags.Count){$lines.Add('override LDFLAGS += '+((@($libraryFlags)+@($linkFlags|ForEach-Object{BashQuote $_})) -join ' '))}
  if($libraryItems.Count){
    $linkVariable='LDLIBS'
    if($Manifest.build -and $Manifest.build.linkVariable){$linkVariable=[string]$Manifest.build.linkVariable}
    if($linkVariable -notin @('LDLIBS','LIBS')){throw ('Variable de enlace no admitida: '+$linkVariable)}
    $lines.Add('override '+$linkVariable+' += '+($libraryItems -join ' '))
  }
  $variables=if($Manifest.build){$Manifest.build.variables}else{$null}
  if($variables){
    foreach($property in $variables.PSObject.Properties){
      $name=[string]$property.Name
      if($name -notmatch '^[A-Z][A-Z0-9_]{0,63}$' -or $name -in @('CC','CXX','PATH','PS5_PAYLOAD_SDK')){throw ('Variable Make no admitida: '+$name)}
      $value=$property.Value
      if($value -and $value.PSObject.Properties['dependency']){
        $dep=[string]$value.dependency
        if(!$PackageMap.ContainsKey($dep)){throw ('Dependencia ausente para variable '+$name+': '+$dep)}
        $resolvedValue=[string]$PackageMap[$dep].root
      }elseif($value -and $value.PSObject.Properties['scope'] -and $value.PSObject.Properties['path']){
        $local=GetPS5HSPayloadScopedPath ([string]$value.scope) ([string]$value.path) $ProjectRoot
        if(!(Test-Path -LiteralPath $local)){throw ('Ruta de Make no encontrada: '+$local)}
        $resolvedValue=ConvertToWslPath $local
      }elseif($value -is [string]){
        if($value -notmatch '^[A-Za-z0-9_./=,+:@%+-]*$'){throw ('Valor literal no seguro para '+$name)}
        $resolvedValue=[string]$value
      }elseif($value -is [System.Collections.IEnumerable]){
        $tokens=@($value);foreach($token in $tokens){if($token -isnot [string] -or $token -notmatch '^[A-Za-z0-9_./=,+:@%+-]+$'){throw ('Lista no segura para '+$name)}}
        $resolvedValue=$tokens -join ' '
      }else{throw ('Variable Make sin referencia segura: '+$name)}
      if($resolvedValue -match '[\x00-\x1f#$]'){throw ('Valor Make incompatible: '+$name)}
      $lines.Add('override '+$name+' := '+$resolvedValue)
    }
  }
  $cc='/opt/ps5-payload-sdk/bin/prospero-clang'+$(if($includeFlags.Count){' '+($includeFlags -join ' ')}else{''})
  $cxx='/opt/ps5-payload-sdk/bin/prospero-clang++'+$(if($includeFlags.Count){' '+($includeFlags -join ' ')}else{''})
  $lines.Add('override CC := '+$cc);$lines.Add('override CXX := '+$cxx)
  if($Language -in @('c','cpp')){$lines.Add('PAYLOAD_LANGUAGE := '+$Language);if($OutputPath){$lines.Add('OUT_ELF := '+$OutputPath)}}
  return @{content=($lines -join [string][char]10);binPaths=$binPaths}
}
function ConvertToPS5HSCStringLiteral([string]$Value) {
  if ($null -eq $Value) { $Value = '' }
  $escaped = $Value.Replace('\','\\').Replace('"','\"').Replace("`r",'\r').Replace("`n",'\n')
  return '"' + $escaped + '"'
}
function ConvertToPS5HSVisualColor([string]$Value,[string]$Fallback) {
  if ($Value -eq 'transparent') { return '0x00000000u' }
  if ($Value -notmatch '^#[0-9a-fA-F]{6}$') { $Value = $Fallback }
  return ('0xFF' + $Value.Substring(1).ToUpperInvariant() + 'u')
}
function GetPS5HSVisualGameSource($P) {
  if (!$P.gameScene -or $P.gameScene.enabled -ne $true) { throw 'Activa la escena Juego 3D para generar el motor visual AGC.' }
  $templatePath=Join-Path $script:Root 'runtime/templates/ps5link-platform-game.c'
  if (!(Test-Path -LiteralPath $templatePath -PathType Leaf)) { throw 'Falta runtime/templates/ps5link-platform-game.c; no se generará un motor vacío.' }
  $templateItem=Get-Item -LiteralPath $templatePath -Force
  if (($templateItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'La plantilla del motor AGC no puede ser un enlace o punto de reanálisis.' }
  $source=[IO.File]::ReadAllText($templatePath,[Text.Encoding]::UTF8)
  if ($source.Length -lt 20000 -or $source -notmatch '(?s)#include\s+"ps5hs_game_scene\.h"' -or $source -notmatch '\bps5hs_game_platforms\b' -or $source -notmatch '\bPS5HS_GAME_OBJECT_COUNT\b' -or $source -notmatch '\bps5hs_game_objects\b' -or $source -notmatch '\bsceAgcDriverSubmitDcb\s*\(' -or $source -notmatch '\bscePadReadState\s*\(') {
    throw 'La plantilla visual AGC no contiene el renderer 3D, la escena completa y la entrada DualSense.'
  }
  return $source
}
function ResolvePS5HSGameActionFunction([string]$Action) {
  switch ($Action) {
    'start' { return 'game_start' }
    'pause' { return 'game_pause' }
    'resume' { return 'game_resume' }
    'restart' { return 'game_restart' }
    'toggleAudio' { return 'game_toggle_audio' }
    default { return '' }
  }
}
function GetPS5HSGameActionBinding($P,[string]$Action) {
  $matches=@($P.flows | Where-Object { $_.enabled -ne $false -and [string]$_.action -eq 'gameAction' -and [string]$_.value -eq $Action })
  if($matches.Count -gt 1){throw "La acción visual '$Action' está conectada más de una vez; deja un único control principal."}
  foreach($flow in $matches) {
    $componentId=[string]$flow.componentId
    $component=@($P.components | Where-Object { [string]$_.id -ceq $componentId } | Select-Object -First 1)
    if(!$component.Count) { throw "La acción visual '$Action' apunta a un componente inexistente: $componentId" }
    $screen=[string]$component[0].screenId
    $screenIndex=-1
    for($i=0;$i -lt @($P.screens).Count;$i++){if([string]$P.screens[$i].id -ceq $screen){$screenIndex=$i;break}}
    if($screenIndex -lt 0){throw "La acción visual '$Action' apunta a una pantalla inexistente: $screen"}
    return @{componentId=$componentId;event=[string]$flow.event;screenIndex=$screenIndex}
  }
  return @{componentId='';event='activate'}
}
function WritePS5LinkVisualBridge($P,[string]$ProjectRoot) {
  $screens = @($P.screens)
  $components = @($P.components)
  $screenIndices = @{}
  for ($i=0; $i -lt $screens.Count; $i++) { $screenIndices[[string]$screens[$i].id] = $i }
  $typeCodes = @{panel=1;card=2;title=3;text=4;button=5;toggle=6;slider=7;stepper=8;select=9;carousel=10;image=11;separator=12;badge=13;progress=14;gauge=15;list=16;input=17}
  $rows = [System.Collections.Generic.List[string]]::new()
  foreach ($component in $components) {
    $screenId = [string]$component.screenId
    if (!$screenIndices.ContainsKey($screenId)) { throw "El componente '$($component.id)' apunta a una pantalla inexistente." }
    $type = [string]$component.type
    if (!$typeCodes.ContainsKey($type)) { throw "Tipo de componente no admitido por el puente AGC: $type" }
    $x = ([double]$component.x).ToString('0.0##',[Globalization.CultureInfo]::InvariantCulture)
    $y = ([double]$component.y).ToString('0.0##',[Globalization.CultureInfo]::InvariantCulture)
    $w = ([double]$component.w).ToString('0.0##',[Globalization.CultureInfo]::InvariantCulture)
    $h = ([double]$component.h).ToString('0.0##',[Globalization.CultureInfo]::InvariantCulture)
    $font = ([double]$component.font).ToString('0.0##',[Globalization.CultureInfo]::InvariantCulture)
    $bg = ConvertToPS5HSVisualColor ([string]$component.bg) '#171B35'
    $fg = ConvertToPS5HSVisualColor ([string]$component.fg) '#EDEBFF'
    $visible = if ($component.visible -eq $false) { 0 } else { 1 }
    $rows.Add(('  {' + (ConvertToPS5HSCStringLiteral ([string]$component.id)) + ', ' + [int]$screenIndices[$screenId] + ', ' + [int]$typeCodes[$type] + ', ' + $x + 'f, ' + $y + 'f, ' + $w + 'f, ' + $h + 'f, ' + $font + 'f, ' + $bg + ', ' + $fg + ', ' + $visible + ', ' + (ConvertToPS5HSCStringLiteral ([string]$component.label)) + '},'))
  }
  if ($rows.Count -eq 0) { $rows.Add('  {0,0,0,0,0,0,0,0,0,0,0,0},') }
  $header = @'
#ifndef PS5HS_VISUAL_H
#define PS5HS_VISUAL_H
#include <stdint.h>
typedef struct {
    const char *id;
    unsigned short screen_index;
    unsigned short type;
    float x, y, w, h, font;
    uint32_t background, foreground;
    int visible;
    const char *label;
} Ps5HSVisualComponent;
extern const Ps5HSVisualComponent ps5hs_visual_components[];
extern const unsigned int ps5hs_visual_component_count;
void ps5hs_dispatch_action(const char *component_id, const char *event_name);
#endif
'@
  $source = [System.Collections.Generic.List[string]]::new()
  $source.Add('#include "ps5hs_visual.h"')
  $source.Add('')
  $source.Add('const Ps5HSVisualComponent ps5hs_visual_components[] = {')
  foreach ($row in $rows) { $source.Add($row) }
  $source.Add('};')
  $source.Add(('const unsigned int ps5hs_visual_component_count = ' + $components.Count + 'u;'))
  $source.Add('')
  $source.Add('static int ps5hs_string_equal(const char *a, const char *b) {')
  $source.Add('    if (!a || !b) return 0;')
  $source.Add('    while (*a && *b && *a == *b) { ++a; ++b; }')
  $source.Add('    return *a == *b;')
  $source.Add('}')
  $source.Add('')
  $flowFunctions = [System.Collections.Generic.List[string]]::new()
  $dispatchRows = [System.Collections.Generic.List[string]]::new()
  foreach ($flow in @($P.flows)) {
    if ($flow.enabled -eq $false) { continue }
    $action=[string]$flow.action
    if($action -eq 'gameAction'){$functionName=ResolvePS5HSGameActionFunction ([string]$flow.value)}
    elseif($action -eq 'callFunction' -and $P.manualCode -eq $true){$functionName=[string]$flow.value}
    else{continue}
    if(!$functionName){throw "Acción integrada de juego no válida en el flujo $($flow.id)."}
    if ($functionName -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,79}$') { throw "Nombre de función C no válido en flujo $($flow.id)." }
    if (!$flowFunctions.Contains($functionName)) { $flowFunctions.Add($functionName) }
    $eventName = [string]$flow.event
    $dispatchRows.Add(('    if (ps5hs_string_equal(component_id, ' + (ConvertToPS5HSCStringLiteral ([string]$flow.componentId)) + ') && (ps5hs_string_equal(event_name, ' + (ConvertToPS5HSCStringLiteral $eventName) + ') || ps5hs_string_equal(event_name, "any"))) { ' + $functionName + '(); return; }'))
  }
  foreach ($functionName in $flowFunctions) { $source.Add(('extern void ' + $functionName + '(void);')) }
  if ($flowFunctions.Count -gt 0) { $source.Add('') }
  $source.Add('void ps5hs_dispatch_action(const char *component_id, const char *event_name) {')
  foreach ($row in $dispatchRows) { $source.Add($row) }
  $source.Add('}')
  WriteUtf8 (Join-Path $ProjectRoot 'src/ps5hs_visual.h') $header
  WriteUtf8 (Join-Path $ProjectRoot 'src/ps5hs_visual.c') ($source -join "`n")
  return @{screens=$screens.Count;components=$components.Count;functionCalls=$dispatchRows.Count;functions=@($flowFunctions)}
}
function ConvertToPS5HSGameFloat([object]$Value,[string]$Field) {
  $number=0.0
  if ($Value -isnot [ValueType] -or ![double]::TryParse([string]$Value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number) -or [double]::IsNaN($number) -or [double]::IsInfinity($number)) { throw "Valor no numérico en la escena 3D: $Field" }
  return $number.ToString('0.0#####',[Globalization.CultureInfo]::InvariantCulture)+'f'
}
function WritePS5LinkGameSceneHeader($P,[string]$ProjectRoot) {
  $scene=$P.gameScene
  if (!$scene -or $scene.enabled -ne $true) { return @{enabled=$false;platforms=0;objects=0;collidableObjects=0;collectibles=0} }
  $platforms=@($scene.platforms)
  $objects=@($scene.objects)
  if ($platforms.Count -lt 2 -or $platforms.Count -gt 128) { throw 'La escena AGC necesita entre 2 y 128 plataformas visuales.' }
  if ($objects.Count -gt 128) { throw 'La escena AGC admite hasta 128 objetos 3D decorativos.' }
  $ids=@{}
  foreach($item in $platforms){if(!$item.id -or $ids.ContainsKey([string]$item.id)){throw 'La escena contiene un bloque de plataforma sin ID o duplicado.'};$ids[[string]$item.id]=$true}
  foreach($object in $objects){
    if(!$object.id -or [string]$object.id -notmatch '^[A-Za-z_][A-Za-z0-9_-]{0,63}$' -or $ids.ContainsKey([string]$object.id)){throw 'La escena contiene un objeto 3D sin ID seguro o con un ID duplicado.'};$ids[[string]$object.id]=$true
    if([string]$object.shape -notin @('box','diamond','sphere','cylinder','cone','pyramid')){throw "El objeto 3D '$($object.id)' tiene una forma geométrica no compatible."}
    foreach($field in @('x','y','z','halfWidth','halfHeight','halfDepth','rotationY','collisionHalfWidth','collisionHalfHeight','collisionHalfDepth','collisionOffsetY')){
      if($object.$field -isnot [ValueType]){throw "El objeto 3D '$($object.id)' no tiene $field numérico."}
      $number=[double]$object.$field;if([double]::IsNaN($number)-or[double]::IsInfinity($number)){throw "El objeto 3D '$($object.id)' tiene un valor no finito en $field."}
    }
    if([Math]::Abs([double]$object.x)-gt 500-or[Math]::Abs([double]$object.z)-gt 500-or[Math]::Abs([double]$object.y)-gt 100-or[double]$object.halfWidth-lt 0.1-or[double]$object.halfWidth-gt 20.5-or[double]$object.halfHeight-lt 0.1-or[double]$object.halfHeight-gt 20.5-or[double]$object.halfDepth-lt 0.1-or[double]$object.halfDepth-gt 20.5-or[double]$object.rotationY-lt -360-or[double]$object.rotationY-gt 360){throw "La geometría del objeto 3D '$($object.id)' excede los límites del editor."}
    if($object.collisionEnabled -isnot [bool]){throw "El objeto 3D '$($object.id)' necesita un estado de colisión booleano."}
    if([double]$object.collisionHalfWidth-lt 0.1-or[double]$object.collisionHalfWidth-gt 20.5-or[double]$object.collisionHalfHeight-lt 0.1-or[double]$object.collisionHalfHeight-gt 20.5-or[double]$object.collisionHalfDepth-lt 0.1-or[double]$object.collisionHalfDepth-gt 20.5-or[double]$object.collisionOffsetY-lt -20.5-or[double]$object.collisionOffsetY-gt 20.5){throw "La caja de colisión del objeto 3D '$($object.id)' excede los límites del editor."}
    if([string]$object.color -notmatch '^#[0-9a-fA-F]{6}$'){throw "El objeto 3D '$($object.id)' necesita un color #RRGGBB válido."}
  }
  $spawnId=[string]$scene.player.spawnPlatformId
  $spawnIndex=-1;for($i=0;$i -lt $platforms.Count;$i++){if([string]$platforms[$i].id -eq $spawnId){$spawnIndex=$i;break}}
  if($spawnIndex -lt 0){throw 'La escena debe asignar el inicio del jugador a una plataforma existente.'}
  $goalIndices=@();for($i=0;$i -lt $platforms.Count;$i++){if($platforms[$i].goal -eq $true){$goalIndices+=,$i}}
  if($goalIndices.Count -ne 1){throw 'La escena debe tener exactamente una plataforma marcada como meta.'}
  $physics=$scene.physics
  $move=ConvertToPS5HSGameFloat $physics.moveSpeed 'moveSpeed';$accel=ConvertToPS5HSGameFloat $physics.acceleration 'acceleration'
  $jump=ConvertToPS5HSGameFloat $physics.jumpSpeed 'jumpSpeed';$gravity=ConvertToPS5HSGameFloat $physics.gravity 'gravity'
  $fall=ConvertToPS5HSGameFloat $physics.fallLimit 'fallLimit';$halfHeight=ConvertToPS5HSGameFloat $physics.playerHalfHeight 'playerHalfHeight'
  $camera=$scene.camera;$appearance=$scene.appearance
  if(!$camera){$camera=@{followDistance=8.7;followHeight=3.4;lookAhead=3.3}}
  if(!$appearance){$appearance=@{skyColor='#100B20';playerColor='#7D89FF';playerAccentColor='#FFD5A5';collectibleColor='#67F3E8';goalColor='#FF9A6B';requireCollectibles=$true}}
  $cameraDistance=ConvertToPS5HSGameFloat $camera.followDistance 'camera.followDistance';$cameraHeight=ConvertToPS5HSGameFloat $camera.followHeight 'camera.followHeight';$cameraLookAhead=ConvertToPS5HSGameFloat $camera.lookAhead 'camera.lookAhead'
  $skyColor=ConvertToPS5HSVisualColor ([string]$appearance.skyColor) '#100B20';$playerColor=ConvertToPS5HSVisualColor ([string]$appearance.playerColor) '#7D89FF';$playerAccentColor=ConvertToPS5HSVisualColor ([string]$appearance.playerAccentColor) '#FFD5A5';$collectibleColor=ConvertToPS5HSVisualColor ([string]$appearance.collectibleColor) '#67F3E8';$goalColor=ConvertToPS5HSVisualColor ([string]$appearance.goalColor) '#FF9A6B'
  $requireCollectibles=if($appearance.requireCollectibles -eq $false){0}else{1}
  $surfaceTextureColors=@($appearance.surfaceTextureColors)
  $surfaceTextureEnabled=0
  if($surfaceTextureColors.Count -gt 0 -and $surfaceTextureColors.Count -ne 256){throw 'La textura de superficie debe tener exactamente 256 muestras de color (16 × 16).'}
  if($surfaceTextureColors.Count -eq 256){$surfaceTextureEnabled=1}
  $surfaceTextureRows=[System.Collections.Generic.List[string]]::new()
  for($textureIndex=0;$textureIndex -lt 256;$textureIndex++){
    $textureColor=if($surfaceTextureEnabled){ConvertToPS5HSVisualColor ([string]$surfaceTextureColors[$textureIndex]) '#34456A'}else{'0xFF34456Au'}
    $surfaceTextureRows.Add('  '+$textureColor+',')
  }
  $defaultLights=@(@{id='light-aurora';name='Foco Aurora';x=-0.8;y=5;z=17;range=18;intensity=0.9;color='#59DFF4'},@{id='light-faro';name='Luz del Faro';x=1.1;y=7;z=45.5;range=20;intensity=1.15;color='#FFD184'})
  $lighting=$scene.lighting
  if(!$lighting){$lighting=@{ambientIntensity=0.34;ambientColor='#B9C8FF';directional=@{enabled=$true;x=-0.4;y=-1;z=-0.6;intensity=0.55;color='#DCE6FF'};points=$defaultLights}}
  $ambientValue=[double]$lighting.ambientIntensity
  if($ambientValue -lt 0 -or $ambientValue -gt 1.5){throw 'La intensidad ambiental debe estar entre 0 y 1.5.'}
  $ambientIntensity=ConvertToPS5HSGameFloat $lighting.ambientIntensity 'lighting.ambientIntensity'
  $ambientColor=ConvertToPS5HSVisualColor ([string]$lighting.ambientColor) '#B9C8FF'
  $sun=$lighting.directional
  if(!$sun){$sun=@{enabled=$true;x=-0.4;y=-1;z=-0.6;intensity=0.55;color='#DCE6FF'}}
  $sunIntensityValue=[double]$sun.intensity
  if($sunIntensityValue -lt 0 -or $sunIntensityValue -gt 1.5){throw 'La intensidad direccional debe estar entre 0 y 1.5.'}
  foreach($field in @('x','y','z')){if([Math]::Abs([double]$sun.$field) -gt 1){throw "La dirección solar $field debe estar entre -1 y 1."}}
  if($sun.enabled -ne $false -and [Math]::Abs([double]$sun.x)+[Math]::Abs([double]$sun.y)+[Math]::Abs([double]$sun.z) -lt 0.01){throw 'La dirección del sol no puede ser un vector nulo.'}
  $sunEnabled=if($sun.enabled -eq $false){0}else{1}
  $sunIntensity=ConvertToPS5HSGameFloat $sun.intensity 'lighting.directional.intensity'
  $sunX=ConvertToPS5HSGameFloat $sun.x 'lighting.directional.x';$sunY=ConvertToPS5HSGameFloat $sun.y 'lighting.directional.y';$sunZ=ConvertToPS5HSGameFloat $sun.z 'lighting.directional.z'
  $sunColor=ConvertToPS5HSVisualColor ([string]$sun.color) '#DCE6FF'
  $pointLights=@($lighting.points)
  if($null -eq $lighting.points){$pointLights=$defaultLights}
  if($pointLights.Count -gt 4){throw 'La escena AGC admite hasta cuatro focos de luz.'}
  $lightIds=@{};$lightRows=[System.Collections.Generic.List[string]]::new()
  foreach($light in $pointLights){
    if(!$light.id -or $lightIds.ContainsKey([string]$light.id)){throw 'La escena contiene un foco de luz sin ID o con un ID duplicado.'};$lightIds[[string]$light.id]=$true
    foreach($field in @('x','y','z','range','intensity')){if($light.$field -isnot [ValueType]){throw "El foco '$($light.id)' no tiene $field numérico."}}
    if([double]$light.x -lt -500 -or [double]$light.x -gt 500 -or [double]$light.z -lt -500 -or [double]$light.z -gt 500 -or [double]$light.y -lt -100 -or [double]$light.y -gt 100){throw "La posición del foco '$($light.id)' está fuera del rango del editor."}
    if([double]$light.range -lt 0.5 -or [double]$light.range -gt 100 -or [double]$light.intensity -lt 0 -or [double]$light.intensity -gt 2.5){throw "El alcance o la intensidad del foco '$($light.id)' exceden los límites."}
    $lx=ConvertToPS5HSGameFloat $light.x "$($light.id).x";$ly=ConvertToPS5HSGameFloat $light.y "$($light.id).y";$lz=ConvertToPS5HSGameFloat $light.z "$($light.id).z";$lr=ConvertToPS5HSGameFloat $light.range "$($light.id).range";$li=ConvertToPS5HSGameFloat $light.intensity "$($light.id).intensity";$lc=ConvertToPS5HSVisualColor ([string]$light.color) '#8DEEFF'
    $lightRows.Add(('  {'+$lx+', '+$ly+', '+$lz+', '+$lr+', '+$li+', '+$lc+'},'))
  }
  $lightCount=$pointLights.Count;$lightStorageCount=[Math]::Max(1,$lightCount)
  if(!$lightRows.Count){$lightRows.Add('  {0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0xFFFFFFFFu},')}
  $actionMacros=[System.Collections.Generic.List[string]]::new()
  foreach($actionSpec in @(@('start','START'),@('pause','PAUSE'),@('resume','RESUME'),@('restart','RESTART'),@('toggleAudio','AUDIO'))){$binding=GetPS5HSGameActionBinding $P $actionSpec[0];$macro=$actionSpec[1];$actionMacros.Add('#define PS5HS_GAME_'+$macro+'_COMPONENT_ID '+(ConvertToPS5HSCStringLiteral $binding.componentId));$actionMacros.Add('#define PS5HS_GAME_'+$macro+'_EVENT '+(ConvertToPS5HSCStringLiteral $binding.event))}
  $hudBadge=@($P.components|Where-Object{[string]$_.type -eq 'badge' -and $_.visible -ne $false}|Select-Object -First 1)
  $hudProgress=@($P.components|Where-Object{[string]$_.type -eq 'progress' -and $_.visible -ne $false}|Select-Object -First 1)
  $hudBadgeId=if($hudBadge.Count){[string]$hudBadge[0].id}else{''};$hudProgressId=if($hudProgress.Count){[string]$hudProgress[0].id}else{''}
  $startBinding=GetPS5HSGameActionBinding $P 'start';$pauseBinding=GetPS5HSGameActionBinding $P 'pause';$resumeBinding=GetPS5HSGameActionBinding $P 'resume';$audioBinding=GetPS5HSGameActionBinding $P 'toggleAudio'
  $menuScreenIndex=if($startBinding.componentId){$startBinding.screenIndex}else{0}
  $pauseScreenIndex=if($resumeBinding.componentId){$resumeBinding.screenIndex}else{$menuScreenIndex}
  $playScreenIndex=if($hudBadge.Count){[array]::IndexOf(@($P.screens|ForEach-Object{[string]$_.id}),[string]$hudBadge[0].screenId)}elseif($hudProgress.Count){[array]::IndexOf(@($P.screens|ForEach-Object{[string]$_.id}),[string]$hudProgress[0].screenId)}elseif($pauseBinding.componentId){$pauseBinding.screenIndex}else{$menuScreenIndex}
  if($platforms[$spawnIndex].collisionEnabled -eq $false){throw 'La plataforma de inicio tiene la colisión desactivada.'}
  if($platforms[$goalIndices[0]].collisionEnabled -eq $false){throw 'La plataforma de meta tiene la colisión desactivada.'}
  if([double]$physics.moveSpeed -le 0 -or [double]$physics.jumpSpeed -le 0 -or [double]$physics.gravity -le 0){throw 'La escena requiere velocidad, salto y gravedad mayores que cero para validar aterrizajes.'}
  $supportNodes=[System.Collections.Generic.List[object]]::new()
  foreach($platform in $platforms){if($platform.collisionEnabled -eq $false){continue};$supportHw=if($platform.collisionHalfWidth -is [ValueType]){[double]$platform.collisionHalfWidth}else{[double]$platform.halfWidth+0.24};$supportHd=if($platform.collisionHalfDepth -is [ValueType]){[double]$platform.collisionHalfDepth}else{[double]$platform.halfDepth+0.24};$supportY=[double]$platform.height+$(if($platform.collisionOffsetY -is [ValueType]){[double]$platform.collisionOffsetY}else{0});$supportNodes.Add(@{id=[string]$platform.id;x=[double]$platform.x;y=$supportY;z=[double]$platform.z;halfWidth=$supportHw;halfDepth=$supportHd})}
  foreach($object in $objects){if($object.collisionEnabled -ne $true){continue};$supportY=[double]$object.y+[double]$object.collisionOffsetY+[double]$object.collisionHalfHeight;$supportNodes.Add(@{id=[string]$object.id;x=[double]$object.x;y=$supportY;z=[double]$object.z;halfWidth=[double]$object.collisionHalfWidth;halfDepth=[double]$object.collisionHalfDepth})}
  $reachable=@{};$reachable[$spawnId]=$true;$changed=$true
  while($changed){
    $changed=$false
    foreach($from in $supportNodes){if(-not $reachable.ContainsKey([string]$from.id)){continue}
      foreach($to in $supportNodes){if($reachable.ContainsKey([string]$to.id)){continue}
        $rise=[double]$to.y-[double]$from.y;$jumpValue=[double]$physics.jumpSpeed;$gravityValue=[double]$physics.gravity;$disc=$jumpValue*$jumpValue-2*$gravityValue*$rise
        if($disc -lt 0){continue}
        $flight=($jumpValue+[Math]::Sqrt([Math]::Max(0,$disc)))/$gravityValue;$reach=[double]$physics.moveSpeed*$flight
        if([Math]::Abs([double]$to.x-[double]$from.x) -gt ($reach+[double]$from.halfWidth+[double]$to.halfWidth+0.34)){continue}
        if([Math]::Abs([double]$to.z-[double]$from.z) -gt ($reach+[double]$from.halfDepth+[double]$to.halfDepth+0.34)){continue}
        $reachable[[string]$to.id]=$true;$changed=$true
      }
    }
  }
  $critical=@($goalIndices);for($i=0;$i -lt $platforms.Count;$i++){if($platforms[$i].collectible -eq $true -or $platforms[$i].checkpoint -eq $true){$critical+=,$i}}
  foreach($i in ($critical | Select-Object -Unique)){if(-not $reachable.ContainsKey([string]$platforms[$i].id)){throw "La plataforma crítica '$($platforms[$i].label)' no es alcanzable desde el inicio con la física y las cajas de colisión actuales."}}
  $rows=[System.Collections.Generic.List[string]]::new();$collectibleIndex=0
  foreach($item in $platforms){
    foreach($field in @('x','height','z','halfWidth','halfDepth')){if($item.$field -isnot [ValueType]){throw "La plataforma $($item.id) no tiene $field numérico."}}
    $x=ConvertToPS5HSGameFloat $item.x "$($item.id).x";$y=ConvertToPS5HSGameFloat $item.height "$($item.id).height";$z=ConvertToPS5HSGameFloat $item.z "$($item.id).z"
    $hw=ConvertToPS5HSGameFloat $item.halfWidth "$($item.id).halfWidth";$hd=ConvertToPS5HSGameFloat $item.halfDepth "$($item.id).halfDepth"
    $collisionHw=if($item.collisionHalfWidth -is [ValueType]){ConvertToPS5HSGameFloat $item.collisionHalfWidth "$($item.id).collisionHalfWidth"}else{ConvertToPS5HSGameFloat ([double]$item.halfWidth+0.24) "$($item.id).collisionHalfWidth"}
    $collisionHh=if($item.collisionHalfHeight -is [ValueType]){ConvertToPS5HSGameFloat $item.collisionHalfHeight "$($item.id).collisionHalfHeight"}else{'0.45f'}
    $collisionHd=if($item.collisionHalfDepth -is [ValueType]){ConvertToPS5HSGameFloat $item.collisionHalfDepth "$($item.id).collisionHalfDepth"}else{ConvertToPS5HSGameFloat ([double]$item.halfDepth+0.24) "$($item.id).collisionHalfDepth"}
    $collisionY=if($item.collisionOffsetY -is [ValueType]){ConvertToPS5HSGameFloat $item.collisionOffsetY "$($item.id).collisionOffsetY"}else{'0.0f'}
    $collisionWidthValue=if($item.collisionHalfWidth -is [ValueType]){[double]$item.collisionHalfWidth}else{[double]$item.halfWidth+0.24};$collisionHeightValue=if($item.collisionHalfHeight -is [ValueType]){[double]$item.collisionHalfHeight}else{0.45};$collisionDepthValue=if($item.collisionHalfDepth -is [ValueType]){[double]$item.collisionHalfDepth}else{[double]$item.halfDepth+0.24};$collisionOffsetValue=if($item.collisionOffsetY -is [ValueType]){[double]$item.collisionOffsetY}else{0.0}
    if($collisionWidthValue -lt 0.1 -or $collisionWidthValue -gt 20.5 -or $collisionHeightValue -lt 0.1 -or $collisionHeightValue -gt 20.5 -or $collisionDepthValue -lt 0.1 -or $collisionDepthValue -gt 20.5 -or $collisionOffsetValue -lt -2 -or $collisionOffsetValue -gt 2){throw "La caja de colisión de '$($item.id)' excede los límites."}
    $shard=if($item.collectible -eq $true){$collectibleIndex++};if($null -eq $shard){$shard=-1}
    $checkpoint=if($item.checkpoint -eq $true){1}else{0};$goal=if($item.goal -eq $true){1}else{0};$collisionEnabled=if($item.collisionEnabled -eq $false){0}else{1}
    $color=ConvertToPS5HSVisualColor ([string]$item.color) '#52D6BE'
    $rows.Add(('  {'+(ConvertToPS5HSCStringLiteral ([string]$item.id))+', '+$x+', '+$y+', '+$z+', '+$hw+', '+$hd+', '+$collisionHw+', '+$collisionHh+', '+$collisionHd+', '+$collisionY+', '+$collisionEnabled+', '+$shard+', '+$checkpoint+', '+$goal+', '+$color+'},'))
  }
  $objectRows=[System.Collections.Generic.List[string]]::new();$shapeCodes=@{box=0;diamond=1;sphere=2;cylinder=3;cone=4;pyramid=5}
  foreach($object in $objects){
    $x=ConvertToPS5HSGameFloat $object.x "$($object.id).x";$y=ConvertToPS5HSGameFloat $object.y "$($object.id).y";$z=ConvertToPS5HSGameFloat $object.z "$($object.id).z"
    $hw=ConvertToPS5HSGameFloat $object.halfWidth "$($object.id).halfWidth";$hh=ConvertToPS5HSGameFloat $object.halfHeight "$($object.id).halfHeight";$hd=ConvertToPS5HSGameFloat $object.halfDepth "$($object.id).halfDepth";$rotation=ConvertToPS5HSGameFloat $object.rotationY "$($object.id).rotationY"
    $collisionHw=ConvertToPS5HSGameFloat $object.collisionHalfWidth "$($object.id).collisionHalfWidth";$collisionHh=ConvertToPS5HSGameFloat $object.collisionHalfHeight "$($object.id).collisionHalfHeight";$collisionHd=ConvertToPS5HSGameFloat $object.collisionHalfDepth "$($object.id).collisionHalfDepth";$collisionY=ConvertToPS5HSGameFloat $object.collisionOffsetY "$($object.id).collisionOffsetY";$collisionEnabled=if($object.collisionEnabled){1}else{0}
    $shape=[int]$shapeCodes[[string]$object.shape];$color=ConvertToPS5HSVisualColor ([string]$object.color) '#59DFF4'
    $objectRows.Add(('  {'+(ConvertToPS5HSCStringLiteral ([string]$object.id))+', '+$x+', '+$y+', '+$z+', '+$hw+', '+$hh+', '+$hd+', '+$rotation+', '+$shape+', '+$collisionEnabled+', '+$collisionHw+', '+$collisionHh+', '+$collisionHd+', '+$collisionY+', '+$color+'},'))
  }
  $objectCount=$objects.Count;$objectStorageCount=[Math]::Max(1,$objectCount)
  if(!$objectRows.Count){$objectRows.Add('  {"", 0.0f, 0.0f, 0.0f, 0.5f, 0.5f, 0.5f, 0.0f, 0, 0, 0.5f, 0.5f, 0.5f, 0.0f, 0xFF59DFF4u},')}
  $header=@'
#ifndef PS5HS_GAME_SCENE_H
#define PS5HS_GAME_SCENE_H
#include <stdint.h>
typedef struct {
    const char *id;
    float x, height, z, half_width, half_depth, collision_half_width, collision_half_height, collision_half_depth, collision_offset_y;
    int collision_enabled, shard_id, checkpoint, goal;
    uint32_t top_color;
} Ps5HSGamePlatform;
'@
  $header += "`ntypedef struct { const char *id; float x,y,z,half_width,half_height,half_depth,rotation_y_degrees; int shape,collision_enabled; float collision_half_width,collision_half_height,collision_half_depth,collision_offset_y; uint32_t color; } Ps5HSGameObject;`n"
  $header += "`ntypedef struct { float x,y,z,range,intensity; uint32_t color; } Ps5HSGamePointLight;`n"
  $header += "`n#define PS5HS_GAME_TITLE "+(ConvertToPS5HSCStringLiteral ([string]$P.name))+"`n#define PS5HS_GAME_PLATFORM_COUNT $($platforms.Count)`n#define PS5HS_GAME_OBJECT_COUNT $objectCount`n#define PS5HS_GAME_OBJECT_STORAGE_COUNT $objectStorageCount`n#define PS5HS_GAME_SHARD_COUNT $collectibleIndex`n#define PS5HS_GAME_SPAWN_INDEX $spawnIndex`n#define PS5HS_GAME_GOAL_INDEX $($goalIndices[0])`n#define PS5HS_GAME_MOVE_SPEED $move`n#define PS5HS_GAME_ACCELERATION $accel`n#define PS5HS_GAME_JUMP_SPEED $jump`n#define PS5HS_GAME_GRAVITY $gravity`n#define PS5HS_GAME_FALL_LIMIT $fall`n#define PS5HS_GAME_PLAYER_HALF_HEIGHT $halfHeight`n#define PS5HS_GAME_CAMERA_FOLLOW_DISTANCE $cameraDistance`n#define PS5HS_GAME_CAMERA_FOLLOW_HEIGHT $cameraHeight`n#define PS5HS_GAME_CAMERA_LOOK_AHEAD $cameraLookAhead`n#define PS5HS_GAME_SKY_COLOR $skyColor`n#define PS5HS_GAME_PLAYER_COLOR $playerColor`n#define PS5HS_GAME_PLAYER_ACCENT_COLOR $playerAccentColor`n#define PS5HS_GAME_COLLECTIBLE_COLOR $collectibleColor`n#define PS5HS_GAME_GOAL_COLOR $goalColor`n#define PS5HS_GAME_REQUIRE_COLLECTIBLES $requireCollectibles`n#define PS5HS_GAME_MENU_SCREEN_INDEX $menuScreenIndex`n#define PS5HS_GAME_PAUSE_SCREEN_INDEX $pauseScreenIndex`n#define PS5HS_GAME_PLAY_SCREEN_INDEX $playScreenIndex`n#define PS5HS_GAME_HUD_BADGE_ID "+(ConvertToPS5HSCStringLiteral $hudBadgeId)+"`n#define PS5HS_GAME_HUD_PROGRESS_ID "+(ConvertToPS5HSCStringLiteral $hudProgressId)+"`n"+($actionMacros -join "`n")+"`n"
  $header += "#define PS5HS_GAME_AMBIENT_INTENSITY $ambientIntensity`n#define PS5HS_GAME_AMBIENT_COLOR $ambientColor`n#define PS5HS_GAME_SUN_ENABLED $sunEnabled`n#define PS5HS_GAME_SUN_INTENSITY $sunIntensity`n#define PS5HS_GAME_SUN_X $sunX`n#define PS5HS_GAME_SUN_Y $sunY`n#define PS5HS_GAME_SUN_Z $sunZ`n#define PS5HS_GAME_SUN_COLOR $sunColor`n#define PS5HS_GAME_POINT_LIGHT_COUNT $lightCount`n#define PS5HS_GAME_POINT_LIGHT_STORAGE_COUNT $lightStorageCount`n"
  $header += "static const Ps5HSGamePointLight ps5hs_game_point_lights[PS5HS_GAME_POINT_LIGHT_STORAGE_COUNT] = {`n"+($lightRows -join "`n")+"`n};`n"
  $header += "static const Ps5HSGameObject ps5hs_game_objects[PS5HS_GAME_OBJECT_STORAGE_COUNT] = {`n"+($objectRows -join "`n")+"`n};`n"
  $header += "#define PS5HS_GAME_SURFACE_TEXTURE_SIZE 16`n#define PS5HS_GAME_SURFACE_TEXTURE_ENABLED $surfaceTextureEnabled`n"
  $header += "static const uint32_t ps5hs_game_surface_texture[PS5HS_GAME_SURFACE_TEXTURE_SIZE * PS5HS_GAME_SURFACE_TEXTURE_SIZE] = {`n"+($surfaceTextureRows -join "`n")+"`n};`n"
  $header += "static const Ps5HSGamePlatform ps5hs_game_platforms[PS5HS_GAME_PLATFORM_COUNT] = {`n"+($rows -join "`n")+"`n};`n#endif`n"
  WriteUtf8 (Join-Path $ProjectRoot 'src/ps5hs_game_scene.h') $header
  $collidableObjectCount=@($objects|Where-Object{$_.collisionEnabled -eq $true}).Count
  return @{enabled=$true;platforms=$platforms.Count;objects=$objectCount;collidableObjects=$collidableObjectCount;collectibles=$collectibleIndex;lights=$lightCount;surfaceTexture=($surfaceTextureEnabled -eq 1);goalIndex=$goalIndices[0];spawnIndex=$spawnIndex}
}
function BuildPS5LinkProject($P,[string]$Code,$Policy=$null,[string]$LibcPath='') {
  $backend = 'ps5link'
  $requestedAudioId = [string]$P.gamePresentation.audioAssetId
  $selectedAudioAsset = $null
  $audioUpload = $null
  if ($requestedAudioId) {
    $selectedAudioAsset = @($P.assets | Where-Object { [string]$_.id -ceq $requestedAudioId } | Select-Object -First 1)
    if (!$selectedAudioAsset.Count) { return @{ok=$false;message='La música seleccionada ya no está en Recursos.';output='Vuelve a importar la pista o selecciona otro recurso antes de compilar.';exitCode=2} }
    $selectedAudioAsset = $selectedAudioAsset[0]
    $audioName = [IO.Path]::GetFileName([string]$selectedAudioAsset.fileName)
    if ([IO.Path]::GetExtension($audioName).ToLowerInvariant() -notin @('.at9','.wav','.mp3','.flac','.aiff','.aif','.aifc')) {
      return @{ok=$false;message='Formato de música no compatible con el codificador ATRAC9 integrado.';output='Importa AT9, WAV, MP3, FLAC o AIFF/AIFC desde Recursos.';exitCode=2}
    }
    $audioMatch = [regex]::Match([string]$selectedAudioAsset.dataUrl,'^data:[^,]+;base64,([A-Za-z0-9+/=]+)$')
    if (!$audioMatch.Success) { return @{ok=$false;message='El audio seleccionado no contiene datos importables.';output=$audioName;exitCode=2} }
    try { $audioBytes = [Convert]::FromBase64String($audioMatch.Groups[1].Value) }
    catch { return @{ok=$false;message='Los datos del audio seleccionado están dañados.';output=$audioName;exitCode=2} }
    if ($audioBytes.Length -lt 1 -or $audioBytes.Length -gt 24MB) { return @{ok=$false;message='El audio importado debe ocupar 24 MiB o menos.';output=$audioName;exitCode=2} }
    $audioUpload = @{name=$audioName;data=$audioMatch.Groups[1].Value}
  }
  $requiredBuildPermissions = @('allowPs5LinkProjectIntegration','allowExecuteUpstreamBuildTools')
  if ($audioUpload) { $requiredBuildPermissions += 'allowExecuteUpstreamAssetTools' }
  try {
    $Policy = AssertPS5HSNativeModificationConsent -Backend $backend -Policy $Policy -RequirePermissionKeys $requiredBuildPermissions
  } catch { return @{ok=$false;message='Compilación detenida: faltan permisos para integrar los bloques AGC y ejecutar el compilador/enlazador local.';output=$_.Exception.Message;buildStoppedBeforeMutation=$true;exitCode=2} }
  $name = ([string]$P.name).Trim()
  if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._-]{0,47}$') { return @{ok=$false;message='Nombre de proyecto no válido. Usa hasta 48 caracteres ASCII.';output=$name;exitCode=2} }
  $visualGame=$P.manualCode -ne $true
  if($visualGame){
    try{$Code=GetPS5HSVisualGameSource $P}catch{return @{ok=$false;message='No se pudo generar el motor visual AGC desde la escena.';output=$_.Exception.Message;exitCode=2}}
    $manualFlows=@($P.flows|Where-Object{$_.enabled -ne $false -and [string]$_.action -eq 'callFunction'})
    if($manualFlows.Count){return @{ok=$false;message='El modo visual no admite llamadas C manuales.';output='Convierte esos flujos en acciones integradas del juego desde la pestaña Flujos.';exitCode=2}}
    foreach($flow in @($P.flows|Where-Object{$_.enabled -ne $false -and [string]$_.action -eq 'gameAction'})){
      if(!(ResolvePS5HSGameActionFunction ([string]$flow.value))){return @{ok=$false;message='Un flujo contiene una acción de juego no válida.';output=[string]$flow.id;exitCode=2}}
      try{$null=GetPS5HSGameActionBinding $P ([string]$flow.value)}catch{return @{ok=$false;message='Un flujo visual no está conectado a un componente válido.';output=$_.Exception.Message;exitCode=2}}
    }
  }
  if ([string]::IsNullOrWhiteSpace($Code) -or $Code.Length -gt 1MB) { return @{ok=$false;message='El archivo src/main.c está vacío o supera 1 MiB.';output='Escribe el motor C editable en la pestaña Código.';exitCode=2} }
  if ($Code -notmatch '(?s)#include\s+"ps5hs_visual\.h"' -or $Code -notmatch '\bps5hs_dispatch_action\s*\(' -or $Code -notmatch '\bps5hs_visual_components\b') {
    return @{ok=$false;message='El programa C debe consumir ps5hs_visual.h, ps5hs_visual_components y ps5hs_dispatch_action.';output='Esto comprueba que el motor use tanto los componentes visuales creados por bloques como las funciones enlazadas por sus flujos.';exitCode=2}
  }
  if ($P.gameScene -and $P.gameScene.enabled -eq $true -and ($Code -notmatch '(?s)#include\s+"ps5hs_game_scene\.h"' -or $Code -notmatch '\bps5hs_game_platforms\b' -or $Code -notmatch '\bPS5HS_GAME_MOVE_SPEED\b' -or $Code -notmatch '\bPS5HS_GAME_OBJECT_COUNT\b' -or $Code -notmatch '\bps5hs_game_objects\b')) {
    return @{ok=$false;message='El motor aún no consume la escena 3D completa.';output='El código debe integrar el encabezado ps5hs_game_scene.h e iterar sobre los objetos 3D creados desde el editor. No se afirmará que los objetos dibujados en el lienzo llegan al juego si el código no los consume.';exitCode=2}
  }
  $flows = @($P.flows | Where-Object { $_.enabled -ne $false -and [string]$_.action -eq 'callFunction' })
  if($P.manualCode -eq $true){
    if ($flows.Count -eq 0) { return @{ok=$false;message='No hay flujos activos que enlacen bloques con funciones C.';output='En Lógica, añade al menos una acción «Llamar función C» y conéctala a un componente.';exitCode=2} }
    foreach ($flow in $flows) {
      $functionName = [string]$flow.value
      if ($functionName -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,79}$') { return @{ok=$false;message='Un flujo contiene un identificador C no válido.';output=[string]$flow.id;exitCode=2} }
      $functionPattern = '(?m)^\s*(?:(?:static|inline)\s+)*void\s+' + [regex]::Escape($functionName) + '\s*\('
      if ($Code -notmatch $functionPattern) { return @{ok=$false;message="El flujo llama a '$functionName', pero src/main.c no define esa función void.";output='Declara la función en Código y vuelve a compilar.';exitCode=2} }
    }
  }
  if (@($P.components).Count -eq 0) { return @{ok=$false;message='El proyecto ps5link necesita bloques visuales.';output='Añade componentes desde Diseño para que el título integre la interfaz generada en el IDE.';exitCode=2} }
  $titleId = ([string]$P.settings.titleId).Trim().ToUpperInvariant()
  if (!(TestPS5HSTitleId $titleId)) { return @{ok=$false;message='TITLE_ID no válido.';output='Usa un identificador PPSA seguido de cinco cifras.';exitCode=2} }
  if ([string]::IsNullOrWhiteSpace($LibcPath)) { return @{ok=$false;message='Falta una libc.prx firmada y compatible con el firmware de la consola.';output='Selecciona la copia local correspondiente a tu firmware. El IDE solo la copia al título de salida.';exitCode=2} }
  try { $LibcPath = AssertPS5HSNativePathNoReparsePoints -Path $LibcPath } catch { return @{ok=$false;message='La ruta de libc.prx no es válida.';output=$_.Exception.Message;exitCode=2} }
  if (!(Test-Path -LiteralPath $LibcPath -PathType Leaf) -or (Get-Item -LiteralPath $LibcPath).Length -lt 65536) { return @{ok=$false;message='No se encontró una libc.prx válida en la ruta indicada.';output=$LibcPath;exitCode=2} }
  $iconAssets = @($P.assets | Where-Object { ([string]$_.fileName -match '(?i)\.png$') -and [string]$_.dataUrl -match '^data:image/png;base64,' })
  $requestedIconId = [string]$P.gamePresentation.iconAssetId
  $iconAsset = if ($requestedIconId) { @($iconAssets | Where-Object { [string]$_.id -ceq $requestedIconId } | Select-Object -First 1) } else { @($iconAssets | Select-Object -First 1) }
  if (!$iconAsset.Count) { return @{ok=$false;message='Falta una portada PNG propia para el título.';output='Importa en Recursos una imagen PNG de 512 × 512 creada para Nebula Steps.';exitCode=2} }
  $offlineBackend = GetPS5HSOfflineBackendReadiness $backend
  if ($offlineBackend.enforced -and $offlineBackend.status -ne 'validated') { return @{ok=$false;message="El bundle offline no declara ps5link como validado: $($offlineBackend.status).";output=[string]$offlineBackend.reason;buildStoppedBeforeMutation=$true;offlineStatus=$offlineBackend.status;exitCode=2} }
  $status = GetStatus
  if (!$status.prerequisites.wsl) { return @{ok=$false;message='WSL no tiene una distribución inicializada.';output='No se ha modificado la carpeta del título.';exitCode=2} }
  $wsl = CmdInfo 'wsl.exe'
  if (!$wsl.ok) { return @{ok=$false;message='wsl.exe no está disponible.';output='No se ha modificado la carpeta del título.';exitCode=2} }
  $distribution = [string]$status.wslDistribution
  $toolchainDir = Join-Path $script:Toolchains 'ps5link-sdk'
  $sharpRoot = Join-Path $script:Toolchains 'SharpProspero'
  if (!(Test-Path -LiteralPath (Join-Path $toolchainDir 'linker/link_real.c') -PathType Leaf) -or !(Test-Path -LiteralPath (Join-Path $sharpRoot 'tools/SharpProspero.Bindings.Generator/SharpProspero.Bindings.Generator.csproj') -PathType Leaf)) {
    return @{ok=$false;message='Faltan las fuentes locales de ps5link-sdk o SharpProspero.';output='El backend no descargará ni restaurará dependencias de Internet.';exitCode=2}
  }
  $slug = Slug $name
  $workspace = [IO.Path]::GetFullPath($script:Workspace)
  $null = AssertPS5HSNativePathNoReparsePoints -Path $workspace
  if (!(Test-Path -LiteralPath $workspace -PathType Container)) { New-Item -ItemType Directory -Force -Path $workspace | Out-Null }
  $projectRoot = Join-Path $workspace $slug
  $saved = SaveProject $P $Code
  if (!$saved.ok) { return @{ok=$false;message=[string]$saved.message;output=[string]$saved.path;exitCode=2} }
  $description = ([string]$P.description).Trim()
  if ($description.Length -gt 500) { return @{ok=$false;message='La descripción supera el límite del IDE.';output='Reduce la descripción a 500 caracteres como máximo.';exitCode=2} }
  $projectMeta = @{schema='ps5hs-native-project';template='ps5link';repository='Rufidj/ps5link-sdk';titleId=$titleId;name=$name;description=$description;category='game';visualBackend='ps5link';generatedFromStudio=$true;initializedAt=(Get-Date).ToString('o')}
  $null = InvokePS5HSNativeModificationWithAudit -ProjectRoot $projectRoot -Backend $backend -Operation 'write-ps5link-project-metadata' -PermissionKey 'allowPs5LinkProjectIntegration' -RelativePaths @('.ps5hs-project.json') -Policy $Policy -SourceRepository 'Rufidj/ps5link-sdk' -Action {
    WriteUtf8 (Join-Path $projectRoot '.ps5hs-project.json') (ConvertTo-Json -InputObject $projectMeta -Depth 8)
  }
  $bridge = WritePS5LinkVisualBridge $P $projectRoot
  $gameScene = WritePS5LinkGameSceneHeader $P $projectRoot
  $distRoot = Join-Path $projectRoot 'dist'
  $titleFolder = Join-Path $distRoot $titleId
  $sidecar = Join-Path $distRoot ('.' + $titleId + '.ps5hs.json')
  if (Test-Path -LiteralPath $titleFolder -PathType Container) {
    $owned = $false
    if (Test-Path -LiteralPath $sidecar -PathType Leaf) { try { $owner = Get-Content -LiteralPath $sidecar -Raw | ConvertFrom-Json; $owned = ([string]$owner.schema -eq 'ps5hs-ps5link-title' -and [string]$owner.project -eq $slug -and [string]$owner.titleId -eq $titleId) } catch { $owned = $false } }
    if (!$owned) { return @{ok=$false;message="Ya existe un título en dist/$titleId y no pertenece a este proyecto.";output='Elige otro TITLE_ID para preservar el contenido existente.';exitCode=2;path=$titleFolder} }
    $backupRoot = Join-Path $script:Runtime ('ps5link-backups\' + $slug)
    New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
    $backupPath = Join-Path $backupRoot ($titleId + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    Move-Item -LiteralPath $titleFolder -Destination $backupPath -ErrorAction Stop
  }
  New-Item -ItemType Directory -Force -Path (Join-Path $titleFolder 'sce_sys'),(Join-Path $titleFolder 'sce_module'),(Join-Path $projectRoot 'tools'),(Join-Path $projectRoot 'src') | Out-Null
  $iconName = [IO.Path]::GetFileName([string]$iconAsset[0].fileName)
  $iconPath = Join-Path (Join-Path $projectRoot 'assets') $iconName
  if (!(Test-Path -LiteralPath $iconPath -PathType Leaf)) { return @{ok=$false;message='La imagen de portada no se guardó en assets/.';output=$iconPath;exitCode=2} }
  $iconBytes = [IO.File]::ReadAllBytes($iconPath)
  $iconWidth = if ($iconBytes.Length -ge 24) { [byte[]]@($iconBytes[19],$iconBytes[18],$iconBytes[17],$iconBytes[16]) } else { [byte[]]@(0,0,0,0) }
  $iconHeight = if ($iconBytes.Length -ge 24) { [byte[]]@($iconBytes[23],$iconBytes[22],$iconBytes[21],$iconBytes[20]) } else { [byte[]]@(0,0,0,0) }
  if ($iconBytes.Length -lt 24 -or $iconBytes[0] -ne 137 -or [Text.Encoding]::ASCII.GetString($iconBytes,1,3) -cne 'PNG' -or [BitConverter]::ToUInt32($iconWidth,0) -ne 512 -or [BitConverter]::ToUInt32($iconHeight,0) -ne 512) { return @{ok=$false;message='La portada debe ser un PNG de 512 × 512 píxeles.';output=$iconPath;exitCode=2} }
  Copy-Item -LiteralPath $iconPath -Destination (Join-Path $titleFolder 'sce_sys/icon0.png') -Force
  Copy-Item -LiteralPath $LibcPath -Destination (Join-Path $titleFolder 'sce_module/libc.prx') -Force
  $contentTail = (($slug -replace '[^A-Za-z0-9]','').ToUpperInvariant() + '0000000000000000').Substring(0,16)
  $param = [ordered]@{
    titleId=$titleId;conceptId=$titleId.Substring(4);contentId=('UP9000-' + $titleId + '_00-' + $contentTail);contentVersion='01.000.001';masterVersion='01.00';applicationCategoryType=0;applicationDrmType='free';attribute=1644167168;attribute2=0;attribute3=1048576;contentBadgeType=1;downloadDataSize=256;requiredSystemSoftwareVersion='0x0000000000000000';sdkVersion='0x0000000000000000';versionFileUri='';gameIntent=@{permittedIntents=@(@{intentType='launchActivity'})};ageLevel=@{default=0};amm=@{multimapVaRangeInGib=512;pagetableMemorySizeInMib=256;vaRangeInGib=512};kernel=@{cpuPageTableSize=268435456;gpuPageTableSize=268435456};localizedParameters=@{defaultLanguage='en-US';'en-US'=@{titleName=$name}};pubtools=@{creationDate=(Get-Date -Format 'yyyy-MM-dd 00:00:00');loudnessSnd0='-28.00';toolVersion='2.00'}
  }
  WriteUtf8 (Join-Path $titleFolder 'sce_sys/param.json') (ConvertTo-Json -InputObject $param -Depth 12)
  WriteUtf8 $sidecar (ConvertTo-Json -InputObject @{schema='ps5hs-ps5link-title';project=$slug;titleId=$titleId;updatedAt=(Get-Date).ToString('o')} -Depth 5)
  $presentationResult = $null
  if ($audioUpload) {
    try {
      $presentationResult = UpdateNativePresentationAssets @{path=$projectRoot;audio=$audioUpload;nativeModifications=$Policy}
      if (!$presentationResult.ok) { return @{ok=$false;message='No se pudo preparar la música ATRAC9; el título no se compilará.';output=[string]$presentationResult.output;path=$projectRoot;titleId=$titleId;backend=$backend;exitCode=2} }
    } catch {
      return @{ok=$false;message='No se pudo convertir e integrar la música ATRAC9; se conserva el proyecto para corregirlo.';output=$_.Exception.Message;path=$projectRoot;titleId=$titleId;backend=$backend;exitCode=2}
    }
  }
  $readme = @"
# $name

$description

Juego de plataformas 3D original. Render directo con AGC; el modelo visual y sus flujos proceden de bloques creados en PS5 Homebrew Studio.

Controles: stick izquierdo para moverse, X para saltar, OPTIONS para pausar, CUADRADO para reiniciar y TRIÁNGULO para activar/desactivar el sonido.

Las plataformas, cristales, personaje, partículas, cámara, colisiones, física de salto y efectos sonoros se generan en el propio programa. El motor AGC directo usa ps5link-sdk y los shaders mesh de SharpProspero; revisa sus licencias GPL antes de redistribuir.

La libc.prx se copió desde la ruta local elegida para compilar y debe ser compatible y estar firmada para el firmware de la consola.
"@
  WriteUtf8 (Join-Path $projectRoot 'README.md') $readme
  $projectWsl = ConvertToWslPath $projectRoot
  $rootWsl = ConvertToWslPath $script:Root
  $titleWsl = ConvertToWslPath $titleFolder
  $scriptPath = Join-Path $projectRoot 'tools/build-ps5link.sh'
  $buildScript = @'
#!/usr/bin/env bash
set -euo pipefail
PROJECT="${1:?project root required}"
IDE_ROOT="${2:?IDE root required}"
TITLE="${3:?title output required}"
SDK="$IDE_ROOT/toolchains/ps5link-sdk"
SHARP="$IDE_ROOT/toolchains/SharpProspero"
PSDK="/opt/ps5-payload-sdk"
BUILD="$PROJECT/build/ps5link"
mkdir -p "$BUILD/shaders"
mkdir -p "$BUILD/nuget-empty"
DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 dotnet restore \
  "$SHARP/tools/SharpProspero.Bindings.Generator/SharpProspero.Bindings.Generator.csproj" \
  --source "$BUILD/nuget-empty"
DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 dotnet build \
  "$SHARP/tools/SharpProspero.Bindings.Generator/SharpProspero.Bindings.Generator.csproj" \
  --configuration Release --no-restore
test -x "$PSDK/bin/prospero-clang"
test -x "$PSDK/bin/prospero-clang++"
test -r "$SDK/linker/crt1.S"
test -r "$SDK/shaders/third_party/sharpprospero/mesh_vs.sb"
test -r "$SDK/shaders/third_party/sharpprospero/mesh_ps.sb"
test -r "$SHARP/tools/SharpProspero.Bindings.Generator/bin/Release/net10.0/sharpprospero-bindgen.dll"
python3 "$PROJECT/tools/embed-ps5link-shader.py" "$SDK/shaders/third_party/sharpprospero/mesh_vs.sb" "$BUILD/shaders/mesh_vs_sb.h" mesh_vs_sb
python3 "$PROJECT/tools/embed-ps5link-shader.py" "$SDK/shaders/third_party/sharpprospero/mesh_ps.sb" "$BUILD/shaders/mesh_ps_sb.h" mesh_ps_sb
cc -O2 -Wall -I "$SDK/linker" -o "$BUILD/link_real" \
  "$SDK/linker/link_real.c" "$SDK/linker/elf_object.c" "$SDK/linker/linker.c" \
  "$SDK/linker/dynwriter.c" "$SDK/linker/catalog.c" "$SDK/linker/catalog_extra.c" \
  "$SDK/linker/catalog_lookup.c" "$SDK/linker/nid.c" "$SDK/linker/sha1.c"
"$PSDK/bin/prospero-clang" -c "$SDK/linker/crt1.S" -o "$BUILD/crt1_ps5.o"
"$PSDK/bin/prospero-clang" -O2 -Wall -I "$BUILD/shaders" -I "$PROJECT/src" -c "$PROJECT/src/main.c" -o "$BUILD/main.o"
"$PSDK/bin/prospero-clang" -O2 -Wall -I "$PROJECT/src" -c "$PROJECT/src/ps5hs_visual.c" -o "$BUILD/ps5hs_visual.o"
"$BUILD/link_real" "$BUILD/app.elf" "$BUILD/crt1_ps5.o" "$BUILD/main.o" "$BUILD/ps5hs_visual.o"
mkdir -p "$TITLE"
dotnet "$SHARP/tools/SharpProspero.Bindings.Generator/bin/Release/net10.0/sharpprospero-bindgen.dll" self --sign --in "$BUILD/app.elf" --out "$TITLE/eboot.bin"
test -s "$TITLE/eboot.bin"
dotnet "$SHARP/tools/SharpProspero.Bindings.Generator/bin/Release/net10.0/sharpprospero-bindgen.dll" self --inspect --file "$TITLE/eboot.bin"
printf 'ELF64: %s\nSELF: %s\n' "$BUILD/app.elf" "$TITLE/eboot.bin"
sha256sum "$BUILD/app.elf" "$TITLE/eboot.bin"
'@
  WriteUtf8 $scriptPath ($buildScript -replace "`r`n","`n")
  $embedScript = @'
#!/usr/bin/env python3
import pathlib
import sys
source = pathlib.Path(sys.argv[1]).read_bytes()
target = pathlib.Path(sys.argv[2])
name = sys.argv[3]
rows = []
for start in range(0, len(source), 12):
    rows.append("    " + ", ".join(f"0x{b:02x}" for b in source[start:start + 12]) + ",")
text = f"static const unsigned char {name}[] = {{\n" + "\n".join(rows) + f"\n}};\nstatic const unsigned int {name}_len = sizeof({name});\n"
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(text, encoding="ascii")
'@
  WriteUtf8 (Join-Path $projectRoot 'tools/embed-ps5link-shader.py') $embedScript
  $scriptWsl = ConvertToWslPath $scriptPath
  $buildCommand = 'bash ' + (BashQuote $scriptWsl) + ' ' + (BashQuote $projectWsl) + ' ' + (BashQuote $rootWsl) + ' ' + (BashQuote $titleWsl)
  $buildOutput = @(& $wsl.path -d $distribution --exec bash -lc $buildCommand 2>&1 | ForEach-Object { $_.ToString() })
  $buildExit = $LASTEXITCODE
  $buildText = ($buildOutput -join "`r`n")
  if ($presentationResult) { $buildText = ([string]$presentationResult.message + "`r`n" + [string]$presentationResult.output + "`r`n" + $buildText) }
  if ($buildExit -ne 0) { return @{ok=$false;message='La compilación AGC ps5link falló; revisa el diagnóstico exacto.';output=$buildText;exitCode=$buildExit;path=$projectRoot;titleId=$titleId;backend=$backend;visualBridge=$bridge} }
  $elfPath = Join-Path $projectRoot 'build/ps5link/app.elf'
  $ebootPath = Join-Path $titleFolder 'eboot.bin'
  if (!(TestPS5HSPayloadElf $elfPath) -or !(Test-Path -LiteralPath $ebootPath -PathType Leaf) -or (Get-Item -LiteralPath $ebootPath).Length -lt 64) {
    return @{ok=$false;message='El pipeline terminó, pero ELF64 o SELF no pasó la verificación de artefactos.';output=$buildText;path=$projectRoot;titleId=$titleId;backend=$backend}
  }
  if($visualGame){$activeGameActions=@($P.flows|Where-Object{$_.enabled -ne $false -and [string]$_.action -eq 'gameAction'}).Count;$buildText += "`r`nPuente visual: $($bridge.components) componente(s) de interfaz y $activeGameActions acción(es) de juego integrada(s)."}
  else{$buildText += "`r`nPuente visual: $($bridge.components) componente(s) y $($bridge.functionCalls) llamada(s) C enlazada(s)."}
  if($gameScene.enabled){$surfaceSummary=if($gameScene.surfaceTexture){"textura de superficie 16 × 16 horneada en vértices AGC"}else{"color plano por plataforma"};$buildText += "`r`nEscena visual AGC: $($gameScene.platforms) plataformas, $($gameScene.objects) objetos 3D ($($gameScene.collidableObjects) con superficie de aterrizaje), $($gameScene.collectibles) cristales, $($gameScene.lights) focos, $surfaceSummary, inicio $($gameScene.spawnIndex), meta $($gameScene.goalIndex)."}
  $buildText += "`r`nTITLE_ID: $titleId`r`nSELF: $ebootPath"
  $buildMessage=if($visualGame){'Título AGC firmado y verificado desde la escena y los flujos visuales.'}else{'Título AGC firmado y verificado desde el código C y sus flujos.'}
  return @{ok=$true;message=$buildMessage;output=$buildText;path=$projectRoot;titleFolder=$titleFolder;projectPath=$projectRoot;artifact=$ebootPath;titleId=$titleId;backend=$backend;visualBridge=$bridge}
}
function BuildPayloadProject($P,[string]$Code,$Policy=$null) {
  $backend = 'payload'
  $offlineBackend = GetPS5HSOfflineBackendReadiness $backend
  if ($offlineBackend.enforced -and $offlineBackend.status -ne 'validated') {
    $message = "El bundle offline no declara este backend como compilable: $($offlineBackend.status)."
    return @{ok=$false;message=$message;output=[string]$offlineBackend.reason;backend=$backend;buildStoppedBeforeMutation=$true;offlineStatus=$offlineBackend.status}
  }
  try {
    $Policy = AssertPS5HSNativeModificationConsent -Backend $backend -Policy $Policy -RequirePermissionKeys @('allowPayloadProjectIntegration','allowExecuteUpstreamBuildTools')
  } catch {
    return @{ok=$false;message='Compilación detenida: faltan permisos explícitos para escribir el proyecto y ejecutar el PS5 Payload SDK.';output=$_.Exception.Message;buildStoppedBeforeMutation=$true;exitCode=2}
  }
  $name = ([string]$P.name).Trim()
  if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._-]{0,47}$') { return @{ok=$false;message='Nombre de payload inválido. Usa hasta 48 caracteres ASCII, empezando por una letra o número.';output=$name;exitCode=2} }
  if ([string]::IsNullOrWhiteSpace($Code)) { return @{ok=$false;message='El payload no contiene código C/C++.';output='Escribe la entrada del payload en el archivo seleccionado en la pestaña Código.';exitCode=2} }
  if ($Code.Length -gt 1MB) { return @{ok=$false;message='El código fuente supera el límite de 1 MiB.';output='Reduce el tamaño del archivo de entrada antes de compilar.';exitCode=2} }
  
  $language = [string]$P.payloadLanguage
  if ($language -notin @('c','cpp')) { return @{ok=$false;message='El lenguaje del payload debe ser C o C++20.';output='Selecciona C o C++20 en la pestaña Código.';exitCode=2} }
  $buildMode = [string]$P.payloadBuildMode
  if ([string]::IsNullOrWhiteSpace($buildMode)) { $buildMode = 'managed' }
  if ($buildMode -notin @('managed','upstream-makefile')) { return @{ok=$false;message='El modo de build del payload no está admitido.';output=$buildMode;exitCode=2} }
  $sourceName = if ($language -eq 'cpp') { 'main.cpp' } else { 'main.c' }
  if (@($P.components).Count -gt 0 -or @($P.flows).Count -gt 0 -or @($P.assets).Count -gt 0) {
    return @{ok=$false;message='El modelo aún contiene widgets, flujos o recursos visuales que un payload no compila.';output='Implementa la lógica en C/C++ y quita los elementos visuales del modelo para evitar que se omitan.';exitCode=2;diagnostics=@(@{severity='error';title='Proyecto visual incompatible con payload';message='El backend compila src/main.c o src/main.cpp; no transforma componentes, flujos ni recursos visuales a código nativo.';location='Proyecto'})}
  }
  $status = GetStatus
  if (!$status.prerequisites.wsl) { return @{ok=$false;message='WSL no tiene una distribución inicializada.';output='Instala y configura la imagen offline WSL de Homebrew Studio antes de compilar payloads.';exitCode=2} }
  $wsl = CmdInfo 'wsl.exe'
  if (!$wsl.ok) { return @{ok=$false;message='wsl.exe no está disponible.';output='No se ha modificado el proyecto.';exitCode=2} }
  $distribution = [string]$status.wslDistribution
  if ([string]::IsNullOrWhiteSpace($distribution) -or $distribution -eq 'No detectada') { return @{ok=$false;message='No se pudo identificar una distribución WSL para el build.';output='No se ha modificado el proyecto.';exitCode=2} }
  $sdkProbe = 'test -r /opt/ps5-payload-sdk/toolchain/prospero.mk && test -x /opt/ps5-payload-sdk/bin/prospero-clang && test -x /opt/ps5-payload-sdk/bin/prospero-clang++ && test -x /opt/ps5-payload-sdk/bin/prospero-lld && command -v make >/dev/null 2>&1'
  $probeOutput = @(& $wsl.path -d $distribution --exec bash -lc $sdkProbe 2>&1 | ForEach-Object { $_.ToString() })
  $probeExit = $LASTEXITCODE
  if ($probeExit -ne 0) { return @{ok=$false;message="El PS5 Payload SDK no está completo en la distribución WSL '$distribution'.";output=($probeOutput -join "`r`n")+"`r`nSe requiere /opt/ps5-payload-sdk y make. No se descarga nada de Internet.";exitCode=$probeExit} }

  $slug = Slug $name
  $workspace = [IO.Path]::GetFullPath($script:Workspace)
  $null = AssertPS5HSNativePathNoReparsePoints -Path $workspace
  if (!(Test-Path -LiteralPath $workspace -PathType Container)) { New-Item -ItemType Directory -Force -Path $workspace | Out-Null }
  $projectRoot = Join-Path $workspace $slug
  $marker = $null
  if (Test-Path -LiteralPath $projectRoot) {
    $rootItem = Get-Item -LiteralPath $projectRoot -Force
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or !$rootItem.PSIsContainer) { return @{ok=$false;message='La carpeta de destino es un archivo o enlace. No se escribirá a través de ella.';output=$projectRoot;exitCode=2} }
    $null = AssertPS5HSNativePathNoReparsePoints -Path $projectRoot
    $markerPath = Join-Path $projectRoot '.ps5hs-payload-project.json'
    if (Test-Path -LiteralPath $markerPath -PathType Leaf) {
      try { $marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json } catch { return @{ok=$false;message='El manifiesto de propiedad payload no es JSON válido; se conserva la carpeta sin modificar.';output=$markerPath;exitCode=2} }
      if ($marker.schema -ne 'ps5hs-payload-project' -or $marker.backend -ne 'payload' -or ($marker.payloadLanguage -and $marker.payloadLanguage -notin @('c','cpp'))) { return @{ok=$false;message='La carpeta no está identificada como un proyecto payload compatible de Homebrew Studio. No se sobrescribirá.';output=$projectRoot;exitCode=2} }
      $markerBuildMode = [string]$marker.buildMode
      if ([string]::IsNullOrWhiteSpace($markerBuildMode)) { $markerBuildMode = 'managed' }
      if ($markerBuildMode -ne $buildMode) { return @{ok=$false;message='El modo de compilación solicitado no coincide con el manifiesto del proyecto.';output=('project.json: ' + $buildMode + '; manifiesto: ' + $markerBuildMode);exitCode=2;buildStoppedBeforeMutation=$true} }
    } else {
      if ($buildMode -eq 'upstream-makefile') { return @{ok=$false;message='El proyecto upstream necesita su manifiesto de integración.';output=$markerPath;exitCode=2;buildStoppedBeforeMutation=$true} }
      $existingProjectFile = Join-Path $projectRoot 'project.json'
      $existingCSource = Join-Path $projectRoot 'src/main.c'
      $existingCppSource = Join-Path $projectRoot 'src/main.cpp'
      $entries = @(Get-ChildItem -LiteralPath $projectRoot -Force -ErrorAction Stop)
      $isSavedPayload = $false
      if ((Test-Path -LiteralPath $existingProjectFile -PathType Leaf) -and ((Test-Path -LiteralPath $existingCSource -PathType Leaf) -or (Test-Path -LiteralPath $existingCppSource -PathType Leaf))) {
        try { $existingProject = Get-Content -LiteralPath $existingProjectFile -Raw | ConvertFrom-Json; $isSavedPayload = ([string]$existingProject.backend -eq 'payload') } catch { $isSavedPayload = $false }
      }
      if ($entries.Count -gt 0 -and !$isSavedPayload) { return @{ok=$false;message='Ya existe una carpeta sin manifiesto payload y no parece un proyecto payload guardado por el IDE. No se sobrescribirá.';output=$projectRoot;exitCode=2} }
    }
  }

  $wslRoot = ConvertToWslPath $projectRoot
  $dependencySpec = GetPS5HSPayloadDependencySpec $projectRoot $marker ($buildMode -eq 'upstream-makefile')
  if (!$dependencySpec.ok) { return @{ok=$false;message=$dependencySpec.message;output=$dependencySpec.output;exitCode=2;buildStoppedBeforeMutation=$true;backend=$backend;offlineStatus='dependencies-missing'} }
  $manifest = $dependencySpec.manifest
  $upstreamMakefile = ''
  $upstreamTarget = ''
  $upstreamSource = ''
  if ($buildMode -eq 'upstream-makefile') {
    $buildSpec = $manifest.build
    try {
      $upstreamMakefile = GetPS5HSPayloadScopedPath 'project' ([string]$buildSpec.makefile) $projectRoot
      $upstreamSourceRelative = if ($marker.sourcePath) { [string]$marker.sourcePath } else { 'src/main.' + $language }
      $upstreamSource = GetPS5HSPayloadScopedPath 'project' $upstreamSourceRelative $projectRoot
      $artifactRelative = [string]$buildSpec.artifact
      $upstreamTarget = [string]$buildSpec.target
      $artifactPath = GetPS5HSPayloadScopedPath 'project' $artifactRelative $projectRoot
    } catch { return @{ok=$false;message='El perfil upstream declara una ruta insegura.';output=$_.Exception.Message;exitCode=2;buildStoppedBeforeMutation=$true} }
    if (!(Test-Path -LiteralPath $upstreamMakefile -PathType Leaf)) { return @{ok=$false;message='Falta el Makefile declarado por el perfil payload.';output=$upstreamMakefile;exitCode=2;buildStoppedBeforeMutation=$true} }
    if (!(Test-Path -LiteralPath $upstreamSource -PathType Leaf)) { return @{ok=$false;message='Falta el archivo de entrada declarado por el proyecto payload.';output=$upstreamSource;exitCode=2;buildStoppedBeforeMutation=$true} }
    $sourceItem = Get-Item -LiteralPath $upstreamSource -Force
    if ($sourceItem.Length -gt 1MB) { return @{ok=$false;message='El archivo de entrada supera el límite de 1 MiB.';output=$upstreamSource;exitCode=2;buildStoppedBeforeMutation=$true} }
    $integrationRepository = if ($marker.sourceRepository) { [string]$marker.sourceRepository } else { 'proyecto payload local' }
  } else {
    $integrationRepository = 'ps5-payload-dev/sdk (offline image)'
  }
  $dependencySetup = PreparePS5HSPayloadDependencies $dependencySpec $projectRoot $wsl $distribution
  if (!$dependencySetup.ok) { return @{ok=$false;message=$dependencySetup.message;output=$dependencySetup.output;exitCode=$dependencySetup.exitCode;buildStoppedBeforeMutation=$true;backend=$backend;offlineStatus='dependencies-missing'} }
  $toolchainSetup = ResolvePS5HSPayloadToolchain $dependencySpec $wsl $distribution
  if (!$toolchainSetup.ok) { $toolchainFailureOutput = (@($dependencySetup.output) + @($toolchainSetup.output)) -join [Environment]::NewLine; return @{ok=$false;message=$toolchainSetup.message;output=$toolchainFailureOutput;exitCode=$toolchainSetup.exitCode;buildStoppedBeforeMutation=$true;backend=$backend;offlineStatus='toolchain-missing'} }
  $resolvedToolchain = $toolchainSetup.resolved.toolchain
  $resolvedToolchainMajor = [string]$resolvedToolchain.major
  $packageMap = $dependencySetup.packages
  $dependencyOutput = @($dependencySetup.output) + @($toolchainSetup.output)
  try {
    $requiredCommands = @('make') + @(GetPS5HSPayloadManifestList $manifest 'requiredCommands')
    $requiredCommands += ('llvm-config-' + $resolvedToolchainMajor)
  }
  catch { return @{ok=$false;message='El manifiesto contiene una lista de herramientas inválida.';output=$_.Exception.Message;exitCode=2;buildStoppedBeforeMutation=$true;offlineStatus='dependencies-invalid'} }
  foreach ($commandName in $requiredCommands) { if ($commandName -notmatch '^[A-Za-z0-9_.+-]+$') { return @{ok=$false;message='El manifiesto declara un nombre de herramienta inválido.';output=[string]$commandName;exitCode=2;buildStoppedBeforeMutation=$true;offlineStatus='dependencies-invalid'} } }
  $requiredCommands = @($requiredCommands | Select-Object -Unique)
  $requiredPathWsl = @()
  try {
    foreach ($entry in @($manifest.requiredPaths)) {
      $scope = [string]$entry.scope
      $relative = [string]$entry.path
      if ($scope -eq 'wsl') {
        if ($relative -notmatch '^/opt/ps5-payload-sdk/[A-Za-z0-9_./+-]+$' -or $relative -match '(^|/)\.\.(/|$)') { throw ('Ruta WSL no permitida: ' + $relative) }
        $requiredPathWsl += $relative
      } else {
        $local = GetPS5HSPayloadScopedPath $scope $relative $projectRoot
        if (!(Test-Path -LiteralPath $local)) { throw ('Falta la ruta requerida: ' + $local) }
        $requiredPathWsl += (ConvertToWslPath $local)
      }
    }
  } catch { return @{ok=$false;message='El manifiesto contiene una ruta requerida insegura o ausente.';output=$_.Exception.Message;exitCode=2;buildStoppedBeforeMutation=$true;offlineStatus='dependencies-missing'} }
  $binPaths = @()
  $requiredExecutables = @()
  try {
    foreach ($pkg in $packageMap.Values) {
      foreach ($relative in @(GetPS5HSPayloadManifestList $pkg 'binDirs')) { if (!(TestPS5HSPayloadRelativePath $relative)) { throw ('Ruta binDirs inválida: ' + $relative) }; $binPaths += ([string]$pkg.root).TrimEnd('/') + '/' + $relative }
      foreach ($relative in @(GetPS5HSPayloadManifestList $pkg 'executableFiles')) {
        if (!(TestPS5HSPayloadRelativePath $relative)) { throw ('Ruta executableFiles inválida: ' + $relative) }
        $requiredExecutables += ([string]$pkg.root).TrimEnd('/') + '/' + $relative
      }
    }
  } catch { return @{ok=$false;message='Una dependencia contiene rutas de herramientas inválidas.';output=$_.Exception.Message;exitCode=2;buildStoppedBeforeMutation=$true;offlineStatus='dependencies-invalid'} }
  $probeParts = @('set -eu')
  if ($binPaths.Count) { $probeParts += ('export PATH=' + (($binPaths | ForEach-Object { BashQuote $_ }) -join ':') + ':"$PATH"') }
  foreach ($commandName in $requiredCommands) { $probeParts += ('command_path=$(type -P ' + (BashQuote $commandName) + ' 2>/dev/null || true); test -n "$command_path" && test -x "$command_path" || { echo ' + (BashQuote ('Falta herramienta ejecutable declarada en WSL: ' + $commandName)) + ' >&2; exit 1; }') }
  $llvmConfigPath = [string]$resolvedToolchain.llvmConfig
  $probeParts += ('llvm_config_version=$(' + (BashQuote $llvmConfigPath) + ' --version); case "$llvm_config_version" in ' + $resolvedToolchainMajor + '.*) printf ' + (BashQuote ('LLVM_CONFIG resuelto a LLVM ' + $resolvedToolchainMajor + ': ')) + '"$llvm_config_version";; *) echo ' + (BashQuote ('El ejecutable ' + $llvmConfigPath + ' no informa LLVM ' + $resolvedToolchainMajor + '.')) + ' >&2; exit 1;; esac')
  foreach ($executable in $requiredExecutables) { $probeParts += ('test -x ' + (BashQuote $executable) + ' || { echo ' + (BashQuote ('Falta permiso de ejecución para herramienta local: ' + $executable)) + ' >&2; exit 1; }') }
  foreach ($requiredPath in $requiredPathWsl) { $probeParts += ('test -e ' + (BashQuote $requiredPath) + ' || { echo ' + (BashQuote ('Falta ruta requerida en WSL: ' + $requiredPath)) + ' >&2; exit 1; }') }
  $dependencyProbe = $probeParts -join '; '
  $dependencyOutputProbe = @(& $wsl.path -d $distribution --exec bash -lc $dependencyProbe 2>&1 | ForEach-Object { $_.ToString() })
  $dependencyExit = $LASTEXITCODE
  if ($dependencyExit -ne 0) { return @{ok=$false;message='Falta una herramienta o ruta que el proyecto payload declara como requisito. No se modificó el proyecto.';output=(($dependencyOutput + $dependencyOutputProbe) -join [Environment]::NewLine) + "`r`nSi falta un paquete host, decláralo en hostPackages dentro de .ps5hs-payload-dependencies.json.";exitCode=$dependencyExit;buildStoppedBeforeMutation=$true;backend=$backend;offlineStatus='dependencies-missing'} }
  $runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
  $relativeElf = if ($buildMode -eq 'upstream-makefile') { $artifactRelative } else { 'build/payload-' + $runId + '/' + $slug + '.elf' }
  if ($buildMode -ne 'upstream-makefile') { try { $artifactPath = GetPS5HSPayloadScopedPath 'project' $relativeElf $projectRoot } catch { return @{ok=$false;message='La ruta de salida ELF no es segura.';output=$_.Exception.Message;exitCode=2;buildStoppedBeforeMutation=$true} } }
  try {
    $config = NewPS5HSPayloadBuildConfig $manifest $packageMap $projectRoot $(if($buildMode -eq 'upstream-makefile'){''}else{$language}) $(if($buildMode -eq 'upstream-makefile'){''}else{$relativeElf})
    $configRoot = Join-Path $script:Runtime 'payload-dependencies/build-config'
    $null = AssertPS5HSNativePathNoReparsePoints -Path $script:Runtime
    $null = AssertPS5HSNativePathNoReparsePoints -Path $configRoot
    New-Item -ItemType Directory -Force -Path $configRoot | Out-Null
    $configPath = Join-Path $configRoot ($runId + '.mk')
    $null = AssertPS5HSNativePathNoReparsePoints -Path $configPath
    WriteUtf8 $configPath $config.content
    $wslConfigPath = ConvertToWslPath $configPath
  } catch { return @{ok=$false;message='No se pudo generar la configuración local del build payload.';output=$_.Exception.Message;exitCode=2;buildStoppedBeforeMutation=$true} }
  $makefile = @'
# Generated by PS5 Homebrew Studio. Edit src/main.c or src/main.cpp for payload code.
PS5_PAYLOAD_SDK ?= /opt/ps5-payload-sdk
include $(PS5_PAYLOAD_SDK)/toolchain/prospero.mk

PAYLOAD_LANGUAGE ?= c
OUT_ELF ?= build/payload.elf
CFLAGS += -Wall -Wextra -Werror -g
ifeq ($(PAYLOAD_LANGUAGE),cpp)
SOURCE := src/main.cpp
COMPILER := $(CXX)
PAYLOAD_FLAGS = -std=c++20 $(CFLAGS) $(CXXFLAGS)
else ifeq ($(PAYLOAD_LANGUAGE),c)
SOURCE := src/main.c
COMPILER := $(CC)
PAYLOAD_FLAGS = $(CFLAGS)
else
$(error PAYLOAD_LANGUAGE must be c or cpp)
endif

.PHONY: all
all: $(OUT_ELF)

$(OUT_ELF): $(SOURCE)
	@mkdir -p "$(dir $@)"
	$(COMPILER) $(CPPFLAGS) $(PAYLOAD_FLAGS) $(LDFLAGS) -o "$@" "$<" $(LDLIBS)
'@
  $makefile = $makefile -replace "`r`n", "`n"
  if ($buildMode -eq 'managed') {
    $dependenciesManifestRelative = if ($marker -and $marker.dependenciesManifest) { [string]$marker.dependenciesManifest } else { '.ps5hs-payload-dependencies.json' }
    $marker = @{schema='ps5hs-payload-project';version=1;backend='payload';payloadLanguage=$language;buildMode='managed';sdk='ps5-payload-dev/sdk';dependenciesManifest=$dependenciesManifestRelative;updatedAt=(Get-Date).ToString('o')}
    if ($dependencySpec.profile) { $marker.dependencyProfile = [string]$dependencySpec.profile }
  }
  $integrationOperation = if ($buildMode -eq 'upstream-makefile') { 'save-upstream-payload-project-model' } else { 'write-payload-project-source-and-build-files' }
  try {
    $integrationResult = InvokePS5HSNativeTreeModificationWithAudit -ProjectRoot $projectRoot -Backend $backend -Operation $integrationOperation -PermissionKey 'allowPayloadProjectIntegration' -Policy $Policy -SourceRepository $integrationRepository -Action {
      $normalizedNativeFiles = 0
      WriteProjectFiles $P $Code $projectRoot
      if ($buildMode -eq 'upstream-makefile') {
        WriteUtf8 $upstreamSource $Code
        $normalizedNativeFiles = NormalizeNativeBuildFiles $projectRoot $false
      }
      if ($buildMode -eq 'managed') {
        WriteUtf8 (Join-Path $projectRoot '.ps5hs-payload.mk') $makefile
        WriteUtf8 (Join-Path $projectRoot '.ps5hs-payload-project.json') (ConvertTo-Json -InputObject $marker -Depth 10)
        $dependencyManifestPath = Join-Path $projectRoot ([string]$marker.dependenciesManifest)
        if (!(Test-Path -LiteralPath $dependencyManifestPath -PathType Leaf) -and !$dependencySpec.profile) {
          $dependencyManifestTemplate = @{schema='ps5hs-payload-dependencies';version=1;toolchain=@{};hostPackages=@();requiredCommands=@();requiredPaths=@();packages=@();compiler=@{cFlags=@();cxxFlags=@();linkFlags=@();libraries=@();linkFiles=@()}}
          WriteUtf8 $dependencyManifestPath (ConvertTo-Json -InputObject $dependencyManifestTemplate -Depth 10)
        }
        $readme = "# $name`r`n`r`nProyecto payload PS5 de Homebrew Studio.`r`n`r`n- `src/$sourceName`: entrada $language del payload.`r`n- `.ps5hs-payload.mk`: reglas administradas para compilar un ELF con el SDK instalado en WSL.`r`n- `.ps5hs-payload-dependencies.json`: herramientas y bibliotecas específicas de este proyecto, con versión/origen verificables.`r`n- `build/`: salidas versionadas por ejecución; no se pisan builds anteriores.`r`n`r`nEl IDE usa primero las herramientas y archivos locales; si falta una dependencia declarada, puede obtenerla de Ubuntu/HTTPS y verificar su versión o SHA-256. El ELF no se instala ni se ejecuta en una consola.`r`n"
        WriteUtf8 (Join-Path $projectRoot 'README.md') $readme
      }
      return @{normalizedNativeFiles=[int]$normalizedNativeFiles}
    }
  } catch { return @{ok=$false;message='No se pudo preparar el proyecto payload con el permiso autorizado.';output=$_.Exception.Message;path=$projectRoot;exitCode=1} }
  if ($integrationResult -and [int]$integrationResult.normalizedNativeFiles -gt 0) { $dependencyOutput += ('Archivos nativos normalizados a LF para WSL: ' + [int]$integrationResult.normalizedNativeFiles) }

  $pathPrefix = ''
  if (@($config.binPaths).Count) { $pathPrefix = 'export PATH=' + ((@($config.binPaths) | ForEach-Object { BashQuote $_ }) -join ':') + ':"$PATH"; ' }
  $llvmPrefix = 'export LLVM_CONFIG=' + (BashQuote $llvmConfigPath) + '; '
  $compilerTrace = 'printf "LLVM_CONFIG=%s\\n" "$LLVM_CONFIG"; "$LLVM_CONFIG" --version; ' + (BashQuote ([string]$resolvedToolchain.compiler)) + ' --version; ' + (BashQuote ([string]$resolvedToolchain.compilerCxx)) + ' --version; ' + (BashQuote ([string]$resolvedToolchain.linker)) + ' --version; /opt/ps5-payload-sdk/bin/prospero-clang --version; /opt/ps5-payload-sdk/bin/prospero-lld --version; '
  # Parse generated overrides first so Make applies them while expanding upstream := assignments and prerequisites.
  if ($buildMode -eq 'upstream-makefile') {
    $wslMakefile = ConvertToWslPath $upstreamMakefile
    $makeTargets = @()
    if ($buildSpec.PSObject.Properties['cleanTarget'] -and [string]$buildSpec.cleanTarget) { $makeTargets += (BashQuote ([string]$buildSpec.cleanTarget)) }
    $makeTargets += (BashQuote $upstreamTarget)
    $makeInvocation = 'make -f ' + (BashQuote $wslConfigPath) + ' -f ' + (BashQuote $wslMakefile) + ' ' + ($makeTargets -join ' ')
    $makeWithReferenceMetadata = $makeInvocation
    $referenceBuild = $buildSpec.referenceBuild
    if ($referenceBuild) { $makeWithReferenceMetadata += ' VERSION_TAG=' + [string]$referenceBuild.versionTag + ' BUILD_TIME=' + [string]$referenceBuild.buildTime }
    $referenceGate = ''
    if ($referenceBuild) {
      $referenceCommit = [string]$referenceBuild.sourceCommit
      $referenceGate = 'if [ "$(git -C ' + (BashQuote $wslRoot) + ' rev-parse HEAD 2>/dev/null || true)" = ' + (BashQuote $referenceCommit) + ' ] && git -C ' + (BashQuote $wslRoot) + ' diff --ignore-space-at-eol --quiet HEAD --; then printf ' + (BashQuote ('Build de referencia: commit ' + $referenceCommit + ' y contenido rastreado equivalente (se ignoran finales de línea); se fijan VERSION_TAG=' + [string]$referenceBuild.versionTag + ' y BUILD_TIME=' + [string]$referenceBuild.buildTime + '.')) + '; ' + $makeWithReferenceMetadata + '; else printf ' + (BashQuote ('Build de referencia omitido: el commit o el contenido rastreado no coincide; se conservan los metadatos dinámicos del proyecto.')) + '; ' + $makeInvocation + '; fi'
    }
    $buildCommand = if ($referenceGate) { $referenceGate } else { $makeInvocation }
    $wslCommand = 'set -eu; ' + $pathPrefix + $llvmPrefix + 'cd ' + (BashQuote $wslRoot) + '; ' + $compilerTrace + $buildCommand
  } else {
    $wslMakefile = ConvertToWslPath (Join-Path $projectRoot '.ps5hs-payload.mk')
    $wslCommand = 'set -eu; ' + $pathPrefix + $llvmPrefix + 'cd ' + (BashQuote $wslRoot) + '; ' + $compilerTrace + 'make -f ' + (BashQuote $wslConfigPath) + ' -f ' + (BashQuote $wslMakefile) + ' all'
  }
  $compileOperation = if ($buildMode -eq 'upstream-makefile') { 'compile-payload-elf-with-project-makefile-and-manifest' } else { 'compile-payload-elf-with-offline-sdk-and-manifest' }
  try {
    $buildInvocation = InvokePS5HSNativeTreeModificationWithAudit -ProjectRoot $projectRoot -Backend $backend -Operation $compileOperation -PermissionKey 'allowExecuteUpstreamBuildTools' -Policy $Policy -SourceRepository $integrationRepository -Action {
      $buildOutput = @(& $wsl.path -d $distribution --exec bash -lc $wslCommand 2>&1 | ForEach-Object { $_.ToString() })
      $buildExit = $LASTEXITCODE
      return @{output=@($buildOutput);exitCode=[int]$buildExit}
    }
  } catch { return @{ok=$false;message='El build payload terminó con una excepción; se conserva el proyecto y la salida anterior.';output=$_.Exception.Message;path=$projectRoot;artifact=$null;exitCode=1} }
  if ($dependencyOutput.Count -gt 0) { $buildInvocation.output = @($dependencyOutput) + @($buildInvocation.output) }
  $buildLog = (@($buildInvocation.output) -join "`r`n")
  if ([int]$buildInvocation.exitCode -ne 0) { return @{ok=$false;message='El compilador del PS5 Payload SDK devolvió un error. El código fuente se conserva para corregirlo.';output=$buildLog;path=$projectRoot;artifact=$null;exitCode=[int]$buildInvocation.exitCode} }
  if (!(TestPS5HSPayloadElf $artifactPath)) { return @{ok=$false;message='El pipeline terminó sin producir un ELF64 válido para x86-64. No se publicará un artefacto no verificable.';output=$buildLog;path=$projectRoot;artifact=$null;exitCode=1;diagnostics=@(@{severity='error';title='ELF de payload no verificable';message='Faltan la cabecera ELF64 little-endian o la arquitectura x86-64 esperadas.';location=$artifactPath})} }
  $artifactSha256 = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
  $referenceArtifactMatches = $null
  $buildLog += "`r`nSHA-256 ELF local: $artifactSha256"
  if ($buildMode -eq 'upstream-makefile' -and $manifest.build.referenceBuild) {
    $referenceArtifactMatches = ($artifactSha256 -eq ([string]$manifest.build.referenceBuild.sha256).ToLowerInvariant())
    $comparisonText = if ($referenceArtifactMatches) { 'coincide byte a byte con el ELF de referencia.' } else { 'difiere del SHA-256 del ELF de referencia.' }
    $buildLog += "`r`nSHA-256 release 1.7beta7: $($manifest.build.referenceBuild.sha256) — $comparisonText"
  }

  try {
    $exportRoot = [IO.Path]::GetFullPath($script:Exports)
    $null = AssertPS5HSNativePathNoReparsePoints -Path $exportRoot
    if (!(Test-Path -LiteralPath $exportRoot -PathType Container)) { New-Item -ItemType Directory -Force -Path $exportRoot | Out-Null }
    $downloadName = $slug + '-' + $runId + '.elf'
    $downloadPath = Join-Path $exportRoot $downloadName
    if (Test-Path -LiteralPath $downloadPath) { throw 'El nombre de descarga ya existe; no se sobrescribirá.' }
    Copy-Item -LiteralPath $artifactPath -Destination $downloadPath
    if (!(TestPS5HSPayloadElf $downloadPath)) { throw 'El archivo publicado no pasó la verificación ELF.' }
  } catch { return @{ok=$false;message='El ELF se compiló, pero no se pudo preparar la descarga local; el artefacto original se conserva.';output=$buildLog+"`r`n"+$_.Exception.Message;path=$projectRoot;artifact=$artifactPath;exitCode=1} }
  $successMessage = 'El PS5 Payload SDK compiló el proyecto y se verificó la cabecera ELF64 x86-64. El archivo está listo para descargar; no se ha ejecutado en consola.'
  return @{ok=$true;message=$successMessage;output=$buildLog;path=$projectRoot;artifact=$artifactPath;artifactUrl=('/downloads/'+$downloadName);downloadPath=$downloadPath;sha256=$artifactSha256;referenceArtifactMatches=$referenceArtifactMatches;exitCode=0;backend=$backend;format='ELF64';architecture='x86_64';offlineStatus=$offlineBackend.status}
}
function BuildSharp($P,[string]$Code,[string]$Backend,[string]$RequestedOutput='Package',$Policy=$null) {
  if ($Backend -eq 'sharp-payload') {
    return @{ok=$false;message='El formato Payload de SharpProspero es un ELF para un proceso ya cargado, no una aplicación con pantalla propia.';output='Crea un proyecto de payload específico o cambia el destino a SharpProspero · Aplicación.';diagnostics=@(@{severity='error';title='Tipo de producto incompatible';message='La interfaz visual necesita un módulo de aplicación nativa.';location='Backend'})}
  }
  if ($Backend -ne 'sharp') {
    return @{ok=$false;message='Backend SharpProspero no reconocido.';output=[string]$Backend}
  }
  $offlineBackend = GetPS5HSOfflineBackendReadiness $Backend
  if ($offlineBackend.enforced -and $offlineBackend.status -ne 'validated') {
    $message = "El bundle offline no declara este backend como compilable: $($offlineBackend.status)."
    return @{ok=$false;message=$message;output=[string]$offlineBackend.reason;backend=$Backend;buildStoppedBeforeMutation=$true;offlineStatus=$offlineBackend.status}
  }
  try {
    $policy = AssertPS5HSNativeModificationConsent -Backend 'sharp' -Policy $Policy -RequirePermissionKeys @('allowSharpTemplateIntegration','allowExecuteUpstreamBuildTools')
  } catch {
    return @{ok=$false;message='Compilación detenida: faltan permisos explícitos para generar el proyecto o ejecutar herramientas upstream.';output=$_.Exception.Message;buildStoppedBeforeMutation=$true;exitCode=2}
  }

  $name = ([string]$P.name).Trim()
  if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._-]{0,39}$') {
    return @{ok=$false;message='Nombre inválido. Usa entre 1 y 40 caracteres ASCII.';output=$name;exitCode=2}
  }
  $titleId = ([string]$P.settings.titleId).Trim().ToUpperInvariant()
  if (!(TestPS5HSTitleId $titleId)) {
    return @{ok=$false;message='Introduce explícitamente un TITLE_ID válido (PPSA12345, distinto de PPSA00000) antes de compilar. No se asignará uno aleatorio.';output=$titleId;exitCode=2}
  }
  if ([string]::IsNullOrWhiteSpace($Code)) {
    return @{ok=$false;message='El generador no entregó código fuente C#.';output='Genera el código C# y vuelve a intentarlo.';exitCode=2}
  }

  $sdk = Join-Path $script:Toolchains 'SharpProspero'
  $buildScript = Join-Path $sdk 'build/build-app.ps1'
  $sampleRoot = Join-Path $sdk 'samples/prospero-ui'
  $sampleProject = Join-Path $sampleRoot 'SampleApp.csproj'
  if (!(Test-Path -LiteralPath $buildScript -PathType Leaf) -or !(Test-Path -LiteralPath $sampleProject -PathType Leaf)) {
    return @{ok=$false;message='SharpProspero o su muestra samples/prospero-ui/SampleApp.csproj no están instalados.';output=$sdk;exitCode=2}
  }
  $status = GetStatus
  if (!$status.prerequisites.dotnet10) { return @{ok=$false;message='.NET SDK 10 no está disponible en Windows.';output='Instala .NET SDK 10 con Configurar entorno.';exitCode=2} }
  if (!$status.prerequisites.wsl) { return @{ok=$false;message='WSL no tiene una distribución inicializada.';output='Configurar entorno → Instalar WSL + Debian. Termina el primer inicio de la distribución.';exitCode=2} }
  if (!$status.prerequisites.wslDotnet10) { return @{ok=$false;message='.NET SDK 10 no está instalado dentro de WSL.';output='Instala .NET SDK 10 en WSL siguiendo docs/setup.md de SharpProspero.';exitCode=2} }

  $slug = Slug $name
  if ([string]::IsNullOrWhiteSpace($slug) -or $slug -match '[\\/]') {
    return @{ok=$false;message='No se pudo obtener un nombre de carpeta seguro para SharpProspero.';output=$slug;exitCode=2}
  }
  $projectHome = Join-Path $script:Workspace $slug
  if (!(Test-Path -LiteralPath $script:Workspace -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $script:Workspace | Out-Null
  }
  if (Test-Path -LiteralPath $projectHome) {
    $projectHomeItem = Get-Item -LiteralPath $projectHome -Force
    if (($projectHomeItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or !$projectHomeItem.PSIsContainer) {
      return @{ok=$false;message='La carpeta del proyecto es un archivo o enlace. No se escribirá a través de ella.';output=$projectHome;exitCode=2}
    }
  } else {
    New-Item -ItemType Directory -Force -Path $projectHome | Out-Null
  }
  $native = Join-Path $projectHome 'native'
  $sharpMarker = Join-Path $native '.ps5hs-sharp-project.json'
  if (Test-Path -LiteralPath $native) {
    $nativeItem = Get-Item -LiteralPath $native -Force
    if (($nativeItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or !$nativeItem.PSIsContainer) {
      return @{ok=$false;message='El destino native existe como archivo/enlace. No se modificará.';output=$native;exitCode=2}
    }
    if (!(Test-Path -LiteralPath $sharpMarker -PathType Leaf)) {
      return @{ok=$false;message='Ya existe una carpeta native sin manifiesto de propiedad de Homebrew Studio. Para evitar sobrescribir código ajeno, cambia el nombre del proyecto o archiva esa carpeta manualmente.';output=$native;path=$native;exitCode=2}
    }
    try { $existingSharpMeta = Get-Content -LiteralPath $sharpMarker -Raw | ConvertFrom-Json }
    catch { return @{ok=$false;message='El manifiesto SharpProspero no es JSON válido. La carpeta se conserva intacta.';output=$sharpMarker;exitCode=2} }
    if ($existingSharpMeta.schema -ne 'ps5hs-sharp-project' -or $existingSharpMeta.template -ne 'prospero-ui') {
      return @{ok=$false;message='El manifiesto no identifica un proyecto SharpProspero administrado por Homebrew Studio. No se sobrescribirá.';output=$native;exitCode=2}
    }
  }

  if (!(Test-Path -LiteralPath $native -PathType Container)) {
    try {
      $null = InvokePS5HSNativeTreeModificationWithAudit -ProjectRoot $native -Backend 'sharp' -Operation 'copy-sharpprospero-upstream-ui-template' -PermissionKey 'allowSharpTemplateIntegration' -Policy $policy -SourceRepository 'SvenGDK/SharpProspero' -Action {
        CopyProjectTree $sampleRoot $native
      }
    } catch {
      return @{ok=$false;message='No se pudo crear la plantilla SharpProspero con el permiso autorizado.';output=$_.Exception.Message;path=$native;exitCode=1}
    }
  }

  $csproj = Join-Path $native 'SampleApp.csproj'
  $metaPath = Join-Path $native 'sce_sys/param.json'
  if (!(Test-Path -LiteralPath $csproj -PathType Leaf) -or !(Test-Path -LiteralPath $metaPath -PathType Leaf)) {
    return @{ok=$false;message='La plantilla SharpProspero no contiene SampleApp.csproj y sce_sys/param.json; no se intentará reparar automáticamente una estructura desconocida.';output=$native;path=$native;exitCode=2}
  }

  try {
    $null = InvokePS5HSNativeTreeModificationWithAudit -ProjectRoot $native -Backend 'sharp' -Operation 'write-sharpprospero-project-source-and-metadata' -PermissionKey 'allowSharpTemplateIntegration' -Policy $policy -SourceRepository 'SvenGDK/SharpProspero' -Action {
      WriteProjectFiles $P $Code $native
      $raw = Get-Content -LiteralPath $csproj -Raw
      $assemblyName = '<AssemblyName>' + $slug + '</AssemblyName>'
      if ($raw.Contains('<AssemblyName>SampleApp</AssemblyName>')) {
        $raw = $raw.Replace('<AssemblyName>SampleApp</AssemblyName>',$assemblyName)
      } elseif (!$raw.Contains($assemblyName)) {
        throw 'SampleApp.csproj ha cambiado: no se reconoce el nombre de ensamblado esperado. No se aplicará un parche por conjetura.'
      }
      if (!$raw.Contains('assets\**\*')) {
        if (!$raw.Contains('</Project>')) { throw 'SampleApp.csproj no contiene el cierre </Project>. No se modificará.' }
        $addition = "  <ItemGroup>`r`n    <None Update=`"assets\**\*`" CopyToOutputDirectory=`"PreserveNewest`" />`r`n  </ItemGroup>`r`n</Project>"
        $raw = $raw.Replace('</Project>',$addition)
      }
      WriteUtf8 $csproj $raw
      $metadata = Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
      $metadata.titleId = $titleId
      $metadata.contentId = ('UP9000-' + $titleId + '_00-0000000000000001')
      $metadata.conceptId = $titleId.Substring(4)
      if ($metadata.localizedParameters -and $metadata.localizedParameters.'en-US') {
        $metadata.localizedParameters.'en-US'.titleName = $name
      }
      WriteUtf8 $metaPath (ConvertTo-Json -InputObject $metadata -Depth 50)
      $sharpMeta = @{schema='ps5hs-sharp-project';template='prospero-ui';repository='SvenGDK/SharpProspero';titleId=$titleId;name=$name;updatedAt=(Get-Date).ToString('o')}
      WriteUtf8 $sharpMarker (ConvertTo-Json -InputObject $sharpMeta -Depth 10)
    }
  } catch {
    return @{ok=$false;message='No se pudo preparar el código/metadata SharpProspero. Revisa la salida; no se tocó ninguna otra carpeta.';output=$_.Exception.Message;path=$native;exitCode=1}
  }

  $outputId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
  $outputDir = Join-Path $native ('out-' + $outputId)
  New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
  if ($RequestedOutput -notin @('Package','Folder')) { $RequestedOutput = 'Package' }
  $buildArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$buildScript,'-ProjectPath',$csproj,'-SdkRoot',$sdk,'-Output',$RequestedOutput,'-OutputFolder',$outputDir)
  try {
    $buildInvocation = InvokePS5HSNativeTreeModificationWithAudit -ProjectRoot $native -Backend 'sharp' -Operation 'execute-sharpprospero-upstream-build' -PermissionKey 'allowExecuteUpstreamBuildTools' -Policy $policy -SourceRepository 'SvenGDK/SharpProspero' -Action {
      $buildOutput = @(& powershell.exe @buildArgs 2>&1 | ForEach-Object { $_.ToString() })
      $buildExit = $LASTEXITCODE
      return @{output=@($buildOutput);exitCode=[int]$buildExit}
    }
    $out = @($buildInvocation.output)
    $exit = [int]$buildInvocation.exitCode
  } catch {
    return @{ok=$false;message='La ejecución de build-app.ps1 falló y se registró el intento.';output=$_.Exception.Message;path=$native;exitCode=1}
  }
  $log = ($out | ForEach-Object { $_.ToString() }) -join "`r`n"
  $artifact = $null
  if (Test-Path -LiteralPath $outputDir -PathType Container) {
    $candidate = Get-ChildItem -LiteralPath $outputDir -Recurse -File -Include '*.pkg','*.elf','eboot.bin' -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($candidate) { $artifact = $candidate.FullName }
  }
  if ($exit -eq 0 -and $artifact) {
    return @{ok=$true;message='SharpProspero terminó y produjo un artefacto verificable. Se han conservado todas las salidas de compilaciones anteriores.';output=$log;artifact=$artifact;path=$native;titleId=$titleId;exitCode=0}
  }
  return @{ok=$false;message="SharpProspero terminó con código $exit o no produjo un artefacto verificable. Las salidas anteriores se han conservado.";output=$log;path=$native;artifact=$artifact;titleId=$titleId;exitCode=$exit;diagnostics=@(@{severity='error';title='Compilación SharpProspero fallida';message='Revisa la salida de build-app.ps1 y la estructura de la plantilla usada.';location='Pipeline SharpProspero'})}
}
function InvokeSetup([string]$Action) {
  if ($Action -ne 'diagnose') {
    return @{
      ok = $false
      message = 'Homebrew Studio solo diagnostica herramientas ya instaladas. No instala Git, .NET, WSL ni paquetes por Internet.'
      output = 'Instala los requisitos del sistema manualmente fuera del IDE y vuelve a ejecutar el diagnóstico.'
    }
  }
  return @{
    ok = $true
    message = 'Diagnóstico local completado. No se han instalado herramientas ni consultado servicios externos.'
    output = (ConvertTo-Json (GetStatus) -Depth 10)
  }
}
function ServeStatic($C,[string]$UrlPath) {
  $relative=[Uri]::UnescapeDataString($UrlPath.TrimStart('/'));if(!$relative){$relative='index.html'}
  if($relative.StartsWith('downloads/')){
    $file=[IO.Path]::GetFileName($relative.Substring(10).Replace('/','\'))
    if($file -notmatch '^[A-Za-z0-9_-]+\.(zip|elf)$'){SendJson $C @{error='Artefacto no disponible'} 404;return}
    $p=Join-Path $script:Exports $file
    if(!(Test-Path -LiteralPath $p -PathType Leaf)){SendJson $C @{error='Artefacto no encontrado'} 404;return}
    $item=Get-Item -LiteralPath $p -Force
    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){SendJson $C @{error='No se sirven artefactos enlazados'} 404;return}
    $extension=[IO.Path]::GetExtension($file).ToLowerInvariant()
    if($extension -eq '.elf' -and !(TestPS5HSPayloadElf $p)){SendJson $C @{error='El archivo no es un ELF payload verificable'} 404;return}
    $type=if($extension -eq '.zip'){'application/zip'}else{'application/octet-stream'}
    $C.Response.Headers['Content-Disposition']="attachment; filename=`"$file`""
    SendBytes $C ([IO.File]::ReadAllBytes($p)) $type
    return
  }
  $relative=$relative.Replace('\','/').TrimStart('/')
  $allowed=@('index.html','styles.css','app.js','runtime/native-generator.js','runtime/payload-generator.js','runtime/native-modification-policy.js','runtime/project-contracts.js','runtime/layer-model.js','runtime/unicode-fonts.js','runtime/compute-graph.js','docs/SDK_MATRIX.md','docs/PROJECT_ECOSYSTEM.md','docs/VULKAN_COMPUTE.md','docs/vulkan-compute-report.schema.json')
  if($relative -notin $allowed){SendJson $C @{error='Ruta no disponible'} 404;return}
  $full=Join-Path $script:Root ($relative.Replace('/','\'));if(!(Test-Path $full -PathType Leaf)){SendJson $C @{error='Archivo no encontrado'} 404;return}
  $ext = [IO.Path]::GetExtension($full).ToLowerInvariant()
  $type = switch ($ext) {
    '.html' { 'text/html; charset=utf-8' }
    '.css'  { 'text/css; charset=utf-8' }
    '.js'   { 'application/javascript; charset=utf-8' }
    '.svg'  { 'image/svg+xml' }
    '.png'  { 'image/png' }
    '.md'   { 'text/markdown; charset=utf-8' }
    default { 'application/octet-stream' }
  }
  SendBytes $C ([IO.File]::ReadAllBytes($full)) $type
}
# TCP loopback server, not HttpListener: avoids admin-only URL ACL setup on a fresh Windows install.
if ($args.Count -ge 2 -and [string]$args[0] -eq '--worker') {
  $jobId = [string]$args[1]
  try {
    $jobDir = GetBuildJobDirectory $jobId
    $script:ActiveBuildLogPath = Join-Path $jobDir 'build.log'
    $script:BuildLogWriteError = $null
    WriteBuildJobLog $script:ActiveBuildLogPath 'Trabajador de compilación iniciado.'
    $requestPath = Join-Path $jobDir 'request.json'
    $jobRequest = Get-Content -LiteralPath $requestPath -Raw | ConvertFrom-Json
    if ([string]$jobRequest.action -eq 'native') { $result = BuildNativeProject ([string]$jobRequest.body.path) ([bool]$jobRequest.body.cleanBeforeBuild) ([string]$jobRequest.body.titleId) ([string]$jobRequest.body.name) $jobRequest.body.nativeModifications }
    elseif ([string]$jobRequest.action -eq 'package') { $result = PackageNativeProjectWithUltraPack $jobRequest.body }
    elseif ([string]$jobRequest.action -eq 'compute') { $result = BuildVulkanComputeProject $jobRequest.body }
    else { $result = BuildNativeVisualProject $jobRequest.body }
    if ($result.ok) { WriteBuildJobLog $script:ActiveBuildLogPath ('COMPLETADO: ' + [string]$result.message) }
    else { WriteBuildJobLog $script:ActiveBuildLogPath ('ERROR: ' + [string]$result.message) }
    if ($result.output -and [string]$jobRequest.action -ne 'compute') { WriteBuildJobLog $script:ActiveBuildLogPath ([string]$result.output) }
    if ($script:BuildLogWriteError) { $result.logWarning = 'No se pudo escribir una parte del registro: ' + [string]$script:BuildLogWriteError }
    WriteUtf8 (Join-Path $jobDir 'result.json') (ConvertTo-Json -InputObject $result -Depth 100)
    exit 0
  } catch {
    $failed = @{ok=$false;message='El trabajador de compilación ha fallado.';output=$_.Exception.Message;exitCode=1}
    try {
      WriteBuildJobLog (Join-Path (GetBuildJobDirectory $jobId) 'build.log') ('ERROR FATAL: ' + $_.Exception.Message)
      WriteUtf8 (Join-Path (GetBuildJobDirectory $jobId) 'result.json') (ConvertTo-Json -InputObject $failed -Depth 20)
    } catch { Write-Host ('No se pudo guardar el resultado del trabajador: ' + $_.Exception.Message) -ForegroundColor Red }
    exit 1
  }
}

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse('127.0.0.1'),47813)
try {
    $listener.Start()
} catch {
    Write-Host "No se pudo iniciar el servicio en $script:Url." -ForegroundColor Red
    Write-Host ("Detalle de Windows: " + $_.Exception.Message) -ForegroundColor Yellow
    try {
        $owners = @(Get-NetTCPConnection -LocalPort 47813 -State Listen -ErrorAction Stop)
        foreach ($owner in $owners) {
            $ownerPid = [int]$owner.OwningProcess
            Write-Host ("PID que ocupa el puerto 47813: " + $ownerPid) -ForegroundColor Cyan
            try {
                $processInfo = Get-CimInstance Win32_Process -Filter ("ProcessId = " + $ownerPid) -ErrorAction Stop
                Write-Host ("Proceso: " + [string]$processInfo.Name) -ForegroundColor Yellow
                if ($processInfo.CommandLine) { Write-Host ("Comando: " + [string]$processInfo.CommandLine) -ForegroundColor DarkYellow }
            } catch { Write-Host 'No se pudo consultar la información del PID.' -ForegroundColor Yellow }
        }
    } catch {
        Write-Host 'No se pudo consultar el PID. Comprueba netstat -ano -p tcp y busca LISTENING en el puerto 47813.' -ForegroundColor Yellow
    }
    Write-Host 'No se ha terminado ningún proceso automáticamente.' -ForegroundColor Yellow
    Read-Host 'Pulsa Intro para cerrar este intento de arranque'
    exit 2
}
Write-Host 'PS5 Homebrew Studio' -ForegroundColor Cyan
Write-Host "Servicio local: $script:Url"
Write-Host 'Solo loopback. Cierra esta ventana para detenerlo.' -ForegroundColor DarkGray
if (!$NoBrowser) { Start-Process $script:Url }
$script:StopServerRequested = $false
$script:ServerCancelHandler = [System.ConsoleCancelEventHandler]{
    param($sender, $eventArgs)
    $eventArgs.Cancel = $true
    $script:StopServerRequested = $true
    try { $listener.Stop() } catch { }
}
[Console]::add_CancelKeyPress($script:ServerCancelHandler)
try {
while (!$script:StopServerRequested -and $listener.Server.IsBound) {
    $client = $null
    $stream = $null
    try {
        $client = $listener.AcceptTcpClient()
        $stream = $client.GetStream()
        $stream.ReadTimeout = 30000
        $stream.WriteTimeout = 30000

        $headerBytes = New-Object 'System.Collections.Generic.List[byte]'
        $tail = New-Object 'System.Collections.Generic.Queue[byte]'
        while ($headerBytes.Count -lt 65536) {
            $v = $stream.ReadByte()
            if ($v -lt 0) { break }
            $headerBytes.Add([byte]$v)
            $tail.Enqueue([byte]$v)
            if ($tail.Count -gt 4) { $null = $tail.Dequeue() }
            if ($tail.Count -eq 4 -and (($tail.ToArray() -join ',') -eq '13,10,13,10')) { break }
        }
        if ($headerBytes.Count -eq 0) { continue }

        $headerText = [Text.Encoding]::ASCII.GetString($headerBytes.ToArray())
        $headLines = $headerText -split "`r`n"
        $requestParts = $headLines[0].Split(' ')
        if ($requestParts.Count -lt 2) { continue }

        $method = $requestParts[0].ToUpperInvariant()
        $target = $requestParts[1]
        $headers = @{}
        foreach ($line in ($headLines | Select-Object -Skip 1)) {
            if (!$line) { continue }
            $ix = $line.IndexOf(':')
            if ($ix -gt 0) {
                $headers[$line.Substring(0, $ix).Trim().ToLowerInvariant()] = $line.Substring($ix + 1).Trim()
            }
        }

        $length = 0
        if ($headers.ContainsKey('content-length')) {
            [int]::TryParse($headers['content-length'], [ref]$length) | Out-Null
        }

        $response = [pscustomobject]@{
            StatusCode = 200
            ContentType = 'application/octet-stream'
            Headers = @{ 'Cache-Control' = 'no-store' }
            Body = [byte[]]@()
        }
        $bodyBytes = [byte[]]@()

        if ($length -gt 100MB) {
            $response.StatusCode = 413
            $response.ContentType = 'text/plain; charset=utf-8'
            $bodyBytes = [Text.Encoding]::UTF8.GetBytes('Request too large')
            $response.Body = $bodyBytes
        }
        else {
            $bodyBytes = New-Object byte[] $length
            $offset = 0
            while ($offset -lt $length) {
                $read = $stream.Read($bodyBytes, $offset, $length - $offset)
                if ($read -le 0) { break }
                $offset += $read
            }
            if ($offset -ne $length) { continue }

            $hostHeader = [string]$headers['host']
            if ($hostHeader -notin @('127.0.0.1:47813', 'localhost:47813')) {
                $response.StatusCode = 403
                $response.ContentType = 'text/plain; charset=utf-8'
                $bodyBytes = [Text.Encoding]::UTF8.GetBytes('Invalid Host')
                $response.Body = $bodyBytes
            }
            else {
                $uri = [Uri]('http://127.0.0.1:47813' + $target)
                $origin = [string]$headers['origin']
                $path = $uri.AbsolutePath
                $request = [pscustomobject]@{
                    HttpMethod = $method
                    Url = $uri
                    ContentEncoding = [Text.Encoding]::UTF8
                    Body = [Text.Encoding]::UTF8.GetString($bodyBytes)
                    Headers = $headers
                }
                $response = [pscustomobject]@{
                    StatusCode = 200
                    ContentType = 'application/octet-stream'
                    Headers = @{ 'Cache-Control' = 'no-store' }
                    Body = [byte[]]@()
                }
                $ctx = [pscustomobject]@{ Request = $request; Response = $response }

                try {
                    if ($method -eq 'POST' -and $path.StartsWith('/api/') -and $origin -and $origin -notin @('http://127.0.0.1:47813', 'http://localhost:47813')) {
                        SendJson $ctx @{ error = 'Origen no permitido' } 403
                    }
                    elseif ($method -eq 'OPTIONS') {
                        SendBytes $ctx ([byte[]]@()) 'text/plain' 204
                    }
                    elseif ($path.StartsWith('/api/')) {
                        if ($method -eq 'GET' -and $path -eq '/api/status') {
                            SendJson $ctx (GetStatus)
                        }
                        elseif ($method -eq 'GET' -and $path -eq '/api/integrations') {
                            SendJson $ctx (GetIntegrationConfig)
                        }
                        elseif ($method -eq 'GET' -and $path -eq '/api/projects') {
                            $items = @()
                            Get-ChildItem $script:Workspace -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                                $projectFile = Join-Path $_.FullName 'project.json'
                                if (Test-Path $projectFile) {
                                    try {
                                        $project = Get-Content $projectFile -Raw | ConvertFrom-Json
                                        $items += @{ name = $project.name; file = $_.Name; backend = $project.backend }
                                    }
                                    catch { }
                                }
                            }
                            SendJson $ctx @{ projects = $items }
                        }
                        elseif ($method -eq 'GET' -and $path -eq '/api/native-projects') {
                            SendJson $ctx @{ projects = (GetGeneratedProjects) }
                        }
                        elseif ($method -eq 'GET' -and $path -match '^/api/build-jobs/[a-f0-9]{32}$') {
                            $jobId = ($path -split '/')[-1]
                            SendJson $ctx (GetNativeBuildJobStatus $jobId)
                        }
                        else {
                            $body = ReadBody $ctx
                            switch ($path) {
                                '/api/ps5link-game-source' {
                                    if (!$body.project -or [string]$body.project.backend -ne 'ps5link' -or $body.project.manualCode -eq $true) {
                                        SendJson $ctx @{ error = 'La vista previa generada requiere un proyecto ps5link en modo visual.' } 400
                                    }
                                    else {
                                        try {
                                            $visualSource = GetPS5HSVisualGameSource $body.project
                                            SendJson $ctx @{ programCode = $visualSource; engine = 'agc-visual-platform-3d'; revision = 1 }
                                        }
                                        catch { SendJson $ctx @{ error = $_.Exception.Message } 400 }
                                    }
                                }
                                '/api/save' {
                                    $result = SaveProject $body.project ([string]$body.programCode)
                                    SendJson $ctx $result
                                }
                                '/api/load' {
                                    $file = [IO.Path]::GetFileName([string]$body.file)
                                    $projectPath = Join-Path (Join-Path $script:Workspace $file) 'project.json'
                                    if (!(Test-Path $projectPath)) {
                                        SendJson $ctx @{ error = 'Proyecto no encontrado' } 404
                                    }
                                    else {
                                        $loadedProject = Get-Content $projectPath -Raw | ConvertFrom-Json
                                        if ([string]$loadedProject.payloadBuildMode -eq 'upstream-makefile') {
                                            $projectRoot = Split-Path -Parent $projectPath
                                            $null = AssertPS5HSNativePathNoReparsePoints -Path $projectRoot
                                            $markerPath = Join-Path $projectRoot '.ps5hs-payload-project.json'
                                            if (!(Test-Path -LiteralPath $markerPath -PathType Leaf)) { throw 'El proyecto upstream no contiene su manifiesto de integración.' }
                                            $null = AssertPS5HSNativePathNoReparsePoints -Path $markerPath
                                            $marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
                                            if ($marker.schema -ne 'ps5hs-payload-project' -or $marker.backend -ne 'payload' -or $marker.buildMode -ne 'upstream-makefile') { throw 'El proyecto upstream no pasa la comprobación de manifiesto.' }
                                            $language = [string]$marker.payloadLanguage
                                            if ($language -notin @('c','cpp')) { $language = [string]$loadedProject.payloadLanguage }
                                            if ($language -notin @('c','cpp')) { throw 'El proyecto upstream no declara un lenguaje C/C++ válido.' }
                                            $sourceRelative = if ($marker.sourcePath) { [string]$marker.sourcePath } else { 'src/main.' + $language }
                                            $sourcePath = GetPS5HSPayloadScopedPath 'project' $sourceRelative $projectRoot
                                            if (!(Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw ('Falta el archivo de entrada: ' + $sourceRelative) }
                                            $sourceItem = Get-Item -LiteralPath $sourcePath -Force
                                            if ($sourceItem.Length -gt 1MB) { throw 'El archivo de entrada supera 1 MiB.' }
                                            $loadedProject.customCode = Get-Content -LiteralPath $sourcePath -Raw
                                            $loadedProject.manualCode = $true
                                            $loadedProject.payloadLanguage = $language
                                        }
                                        SendJson $ctx @{ project = $loadedProject }
                                    }
                                }
                                '/api/export-zip' {
                                    $result = ExportProject $body.project ([string]$body.programCode)
                                    SendJson $ctx $result
                                }
                                '/api/sdk-install' {
                                    $results = @()
                                    foreach ($id in @($body.ids)) {
                                        $entry = $script:Catalog | Where-Object id -eq ([string]$id) | Select-Object -First 1
                                        if (!$entry) {
                                            $results += @{ ok = $false; name = [string]$id; message = 'ID de SDK desconocido.' }
                                            continue
                                        }
                                        try { $results += InstallRepo $entry }
                                        catch { $results += @{ ok = $false; name = $entry.name; message = $_.Exception.Message } }
                                    }
                                    $success = @($results | Where-Object ok).Count
                                    SendJson $ctx @{ ok = ($success -eq $results.Count); message = "$success de $($results.Count) repositorio(s) disponibles."; results = $results }
                                }
                                '/api/setup' {
                                    SendJson $ctx (InvokeSetup ([string]$body.action))
                                }
                                '/api/template-create' {
                                    $templateId=[string]$body.templateId
                                    if($templateId -eq 'vulkan-template') {
                                        $result = NewVulkanTitle ([string]$body.name) ([string]$body.titleId) ([string]$body.design) $body.nativeModifications
                                    }
                                    elseif($templateId -in @('nativecpp','hui-gl')) {
                                        $category=[string]$body.category;if(!$category){$category='game'}
                                        $result = NewNativeTitle ([string]$body.name) ([string]$body.titleId) $category $templateId $body.nativeModifications
                                    }
                                    else { $result=@{ok=$false;message='Generador upstream no reconocido.';output='';templateId=$templateId} }
                                    SendJson $ctx $result
                                }
                                '/api/integration-config' {
                                    $result = SetIntegrationConfig $body
                                    SendJson $ctx $result
                                }
                                '/api/package-ultrapack/start' {
                                    SendJson $ctx (StartNativeBuildJob $body 'package')
                                }
                                '/api/native-presentation-assets' {
                                    try {
                                        SendJson $ctx (UpdateNativePresentationAssets $body)
                                    }
                                    catch {
                                        SendJson $ctx @{ ok = $false; error = $_.Exception.Message } 400
                                    }
                                }
                                '/api/build-native' {
                                    $result = BuildNativeProject ([string]$body.path) ([bool]$body.cleanBeforeBuild) ([string]$body.titleId) ([string]$body.name) $body.nativeModifications
                                    SendJson $ctx $result
                                }
                                '/api/build-native/start' {
                                    SendJson $ctx (StartNativeBuildJob $body 'native')
                                }
                                '/api/build-visual-native/start' {
                                    SendJson $ctx (StartNativeBuildJob $body 'visual')
                                }
                                '/api/build-vulkan-compute/start' {
                                    SendJson $ctx (StartNativeBuildJob $body 'compute')
                                }
                                '/api/build-visual-native' {
                                    $result = BuildNativeVisualProject $body
                                    SendJson $ctx $result
                                }
                                '/api/build' {
                                    $backend = [string]$body.backend
                                    if ($backend -eq 'payload') {
                                        $result = BuildPayloadProject $body.project ([string]$body.programCode) $body.nativeModifications
                                        SendJson $ctx $result
                                    }
                                    elseif ($backend -in @('sharp', 'sharp-payload')) {
                                        $result = BuildSharp $body.project ([string]$body.programCode) $backend ([string]$body.output) $body.nativeModifications
                                        SendJson $ctx $result
                                    }
                                    elseif ($backend -eq 'ps5link') {
                                        $result = BuildPS5LinkProject $body.project ([string]$body.programCode) $body.nativeModifications ([string]$body.libcPath)
                                        SendJson $ctx $result
                                    }
                                    else {
                                        if ($backend -eq 'ps5sdk') {
                                            $message = 'PS5SDK es un backend de payload ELF C/C++. No ofrece un toolkit de UI que pueda representar fielmente los controles visuales del proyecto. No se reutiliza código C# como si fuera C válido.'
                                        }
                                        elseif ($backend -eq 'payload') {
                                            $message = 'ps5-payload-dev/sdk es un backend de payload C/C++. Los widgets del editor pertenecen a aplicaciones; la compilación necesita un proyecto y una entrada de payload C/C++.'
                                        }
                                        elseif ($backend -eq 'ps5link') {
                                            $message = 'ps5link-sdk produce títulos nativos y requiere ps5-payload-sdk, SharpProspero para empaquetado y libc.prx compatible del usuario. El IDE no presenta el código generado de SharpProspero como C válido.'
                                        }
                                        elseif ($backend -eq 'etahen') {
                                            $message = 'etaHEN-Plugins crea daemons/plugins para etaHEN, no aplicaciones de interfaz independientes. Se requiere un proyecto de plugin y su estructura upstream.'
                                        }
                                        else {
                                            $message = 'Backend no reconocido.'
                                        }
                                        SendJson $ctx @{
                                            ok = $false
                                            message = $message
                                            output = 'No se ha iniciado una compilación incompatible.'
                                            diagnostics = @(@{ severity = 'error'; title = 'Backend incompatible con el modelo visual'; message = $message; location = 'Backend' })
                                        }
                                    }
                                }
                                default {
                                    SendJson $ctx @{ error = 'Ruta API no encontrada'; path = $path } 404
                                }
                            }
                        }
                    }
                    else {
                        ServeStatic $ctx $path
                    }
                }
                catch {
                    SendJson $ctx @{ error = $_.Exception.Message } 500
                    Write-Host ('[ERROR] ' + $_.Exception.Message) -ForegroundColor Yellow
                }

                $response = $ctx.Response
                $bodyBytes = [byte[]]$response.Body
            }
        }

        $status = [int]$response.StatusCode
        $reason = switch ($status) {
            200 { 'OK' }
            204 { 'No Content' }
            400 { 'Bad Request' }
            403 { 'Forbidden' }
            404 { 'Not Found' }
            413 { 'Payload Too Large' }
            500 { 'Internal Server Error' }
            default { 'OK' }
        }
        $contentType = [string]$response.ContentType
        $responseHead = "HTTP/1.1 $status $reason`r`nContent-Type: $contentType`r`nContent-Length: $($bodyBytes.Length)`r`nConnection: close`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`n`r`n"
        $headBytes = [Text.Encoding]::ASCII.GetBytes($responseHead)
        $stream.Write($headBytes, 0, $headBytes.Length)
        if ($bodyBytes.Length -gt 0) { $stream.Write($bodyBytes, 0, $bodyBytes.Length) }
        $stream.Flush()
    }
    catch {
        Write-Host ('[REQUEST ERROR] ' + $_.Exception.Message) -ForegroundColor Yellow
    }
    finally {
        if ($stream) { $stream.Dispose() }
        if ($client) { $client.Close() }
    }
}
} catch {
    Write-Host ("[SERVER STOP] " + $_.Exception.Message) -ForegroundColor Yellow
} finally {
    try { [Console]::remove_CancelKeyPress($script:ServerCancelHandler) } catch { }
    try { $listener.Stop() } catch { }
    Write-Host 'PS5 Homebrew Studio: listener detenido; puerto local 47813 liberado.' -ForegroundColor DarkGray
}

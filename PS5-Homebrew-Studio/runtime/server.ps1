# PS5 Homebrew Studio · Windows local service (PowerShell 5.1+)
# Localhost only: project filesystem and process execution are not exposed to the LAN.
$ErrorActionPreference = 'Stop'
$script:Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script:Toolchains = Join-Path $script:Root 'toolchains'
$script:Runtime = Join-Path $script:Root '.runtime'
$script:Exports = Join-Path $script:Runtime 'exports'
$script:Workspace = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PS5HomebrewStudio\Projects'
$script:Url = 'http://127.0.0.1:47813/'
$script:Utf8 = [System.Text.UTF8Encoding]::new($false)
@($script:Toolchains,$script:Runtime,$script:Exports,$script:Workspace) | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }
$script:Catalog = @(
  @{id='sharp';name='SharpProspero';repo='SvenGDK/SharpProspero';branch='main';folder='SharpProspero';role='Aplicaciones nativas / payload C#';license='GPL-3.0-or-later';description='SDK C# y toolchain de aplicaciones nativas, interfaz, gráficos, audio, entrada, red y payloads.'},
  @{id='ps5sdk';name='PS5SDK';repo='PS5Dev/PS5SDK';branch='main';folder='PS5SDK';role='Payload ELF C/C++';license='GPL-2.0';description='SDK en desarrollo para ELF/payloads y homebrew sencillo; no construye títulos completos.'},
  @{id='payload';name='ps5-payload-dev/sdk';repo='ps5-payload-dev/sdk';branch='master';folder='ps5-payload-sdk';role='SDK de payloads C/C++';license='GPL-3.0-or-later';description='SDK con enlace dinámico, prospero-clang, herramientas y muestras de payload.'},
  @{id='ps5link';name='ps5link-sdk';repo='Rufidj/ps5link-sdk';branch='master';folder='ps5link-sdk';role='Título nativo / eboot.bin';license='GPL-3.0';description='Enlazador para títulos nativos. Requiere dependencias y libc.prx compatible para empaquetar.'},
  @{id='etahen';name='etaHEN-Plugins';repo='etaHEN/etaHEN-Plugins';branch='main';folder='etaHEN-Plugins';role='Plugins/daemons etaHEN';license='GPL-3.0';description='SDK para plugins de etaHEN Toolbox; no equivale a una aplicación GUI independiente.'},
  @{id='nid';name='libNidResolver';repo='astrelsky/libNidResolver';branch='main';folder='libNidResolver';role='Dependencia etaHEN';license='Consultar upstream';description='Submódulo declarado por etaHEN-Plugins; el ZIP de GitHub no contiene submódulos.'},
  @{id='nativecpp';name='PS5 Native App Boilerplate';repo='blackbearreloaded/ps5-native-app-boilerplate';branch='main';folder='ps5-native-app-boilerplate';role='Fundación C/C++20 para títulos nativos';license='GPL-3.0-or-later';description='Base de aplicación nativa con runtime reproducible, metadatos y empaquetado; clona con submódulos.';category='source';method='git'},
  @{id='opengl';name='PS5 OpenGL 4.6';repo='blackbearreloaded/ps5-opengl';branch='main';folder='ps5-opengl';role='Renderer OpenGL 4.6 / GLSL 4.60';license='GPL-3.0-or-later';description='Pila Mesa/Gallium, EGL, compilación de shaders, SDK estático, puente SDL2 y ejemplos.';category='source';method='git'},
  @{id='hui-gl';name='PS5 Homebrew UI (OpenGL)';repo='blackbearreloaded/ps5-homebrew-ui';branch='main';folder='ps5-homebrew-ui';role='Kit de interfaz OpenGL';license='GPL-3.0-or-later';description='Biblioteca UI con componentes, temas, diseños, movimiento y audio; orientada a ps5-opengl.';category='source';method='git'},
  @{id='vulkan-template';name='PS5 Vulkan Template';repo='mihawk-99/PS5_VulkanTemplate';branch='main';folder='PS5_VulkanTemplate';role='Plantilla Vulkan/RADV con generador';license='MIT base; UI opcional GPL-3.0-or-later';description='Fundación Vulkan, ejemplos, test runner y new-title.py para crear títulos nativos.';category='source';method='git'},
  @{id='vulkan-radv';name='PS5_Vulkan / RADV';repo='mihawk-99/PS5_Vulkan';branch='main';folder='PS5_Vulkan';role='Driver Vulkan Mesa/RADV';license='GPL-3.0-or-later';description='Driver Vulkan y capa de plataforma para el stack RADV de PS5; requiere componentes compañeros.';category='source';method='git'},
  @{id='vulkan-sdk';name='PS5_PayloadSDK (fork RADV)';repo='mihawk-99/PS5_PayloadSDK';branch='main';folder='PS5_PayloadSDK';role='SDK compañero de PS5 Vulkan';license='Revisar upstream';description='Fork del SDK con capa PS5, requerido por la plantilla Vulkan en un commit exacto; necesita el historial Git que contiene ese commit.';category='source';method='git';fullHistory=$true},
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
function WriteUtf8([string]$Path,[string]$Content) { [IO.File]::WriteAllText($Path,$Content,$script:Utf8) }

# Normalizes build-critical text copied from Windows checkouts before Make/WSL consumes it.
# This preserves file bytes except CR characters used as line endings and never touches binaries.
function NormalizeNativeBuildFiles([string]$ProjectRoot) {
  $root = [IO.Path]::GetFullPath($ProjectRoot)
  $allowedExtensions = @('.sh','.sha256','.c','.cc','.cpp','.h','.hpp','.ld','.mk','.s','.cmake','.yml','.yaml')
  $allowedNames = @('Makefile','GNUmakefile','CMakeLists.txt','.gitattributes')
  $normalized = 0
  foreach ($item in (Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction Stop)) {
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
  if (Test-Path -LiteralPath $attributesPath -PathType Leaf) {
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
function GetStatus {
  $dot=CmdInfo 'dotnet.exe'; if(!$dot.ok){$dot=CmdInfo 'dotnet'}; $dot10=$false; $dotVersion='No detectado'
  if($dot.ok){try{$list=(& $dot.path --list-sdks 2>$null|Out-String);$dot10=[bool]($list -match '(?m)^10\.[0-9.]+');$dotVersion=((& $dot.path --version 2>$null|Out-String).Trim())}catch{}}
  $wsl=CmdInfo 'wsl.exe';$wslOk=$false;$wslDist='No detectada';$wslDot=$false;$wslGitPython=$false
  if($wsl.ok){try{$dist=(& $wsl.path -l -q 2>$null|Out-String);$exitWsl=$LASTEXITCODE;$clean=$dist -replace "`0",'';$entries=@($clean.Trim() -split "`r?`n"|ForEach-Object{$_.Trim()}|Where-Object{$_ -and $_ -notmatch 'no installed distributions|no hay distribuciones instaladas|Windows Subsystem for Linux|distribuciones instaladas'});$wslOk=($exitWsl -eq 0 -and $entries.Count -gt 0);if($wslOk){$wslDist=$entries[0] -replace '^\*\s*','';& $wsl.path -d $wslDist --exec bash -lc 'dotnet --list-sdks 2>/dev/null | grep -q "^10\."' 2>$null;$wslDot=($LASTEXITCODE -eq 0);& $wsl.path -d $wslDist --exec bash -lc 'command -v git >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1' 2>$null;$wslGitPython=($LASTEXITCODE -eq 0)}}catch{}}
  $git=CmdInfo 'git.exe';if(!$git.ok){$git=CmdInfo 'git'}
  $cmake=CmdInfo 'cmake.exe';if(!$cmake.ok){$cmake=CmdInfo 'cmake'};$ninja=CmdInfo 'ninja.exe';if(!$ninja.ok){$ninja=CmdInfo 'ninja'};$clang=CmdInfo 'clang.exe';if(!$clang.ok){$clang=CmdInfo 'clang'};$make=CmdInfo 'make.exe';if(!$make.ok){$make=CmdInfo 'make'}
  $items=@(
    @{name='Git (clonación y submódulos)';ok=$git.ok;version='';detail=$git.path},
    @{name='.NET SDK 10 (Windows)';ok=$dot10;version=$dotVersion;detail=$dot.path},
    @{name='WSL con distribución Linux';ok=$wslOk;version=$wslDist;detail=$wsl.path},
    @{name='.NET SDK 10 dentro de WSL';ok=$wslDot;version=$(if($wslDot){'10.x detectado'}else{'No detectado'});detail='Necesario para NativeAOT en la ruta de SharpProspero.'},
    @{name='Git y Python 3 dentro de WSL';ok=$wslGitPython;version=$(if($wslGitPython){'Detectados'}else{'No detectados'});detail='Necesarios para los generadores C/C++ que se ejecutan desde WSL.'},
    @{name='CMake ≥ 3.20';ok=$cmake.ok;version='';detail=$cmake.path},
    @{name='Ninja';ok=$ninja.ok;version='';detail=$ninja.path},
    @{name='Clang';ok=$clang.ok;version='';detail=$clang.path},
    @{name='Make';ok=$make.ok;version='';detail=$make.path}
  )
  $sdks=@();foreach($e in $script:Catalog){$p=Join-Path $script:Toolchains $e.folder;$marker=Test-Path (Join-Path $p '.ps5hs-source.json');if($e.method -eq 'git'){$installed=((Test-Path (Join-Path $p '.git')) -and (Test-Path (Join-Path $p 'README.md')))}else{$installed=$marker -or (Test-Path (Join-Path $p 'README.md'))};$category='backend';if($e.category){$category=[string]$e.category};$sdks+=@{id=$e.id;name=$e.name;folder=$e.folder;role=$e.role;license=$e.license;description=$e.description;category=$category;method=$e.method;href=('https://github.com/'+$e.repo);installed=$installed;path=$p}}
  return @{root=$script:Root;workspace=$script:Workspace;wslDistribution=$wslDist;sdks=$sdks;prerequisites=@{git=$git.ok;gitPath=$git.path;dotnet10=$dot10;wsl=$wslOk;wslDotnet10=$wslDot;wslGitPython=$wslGitPython;items=$items}}
}
function Slug([string]$Text) { $s=([string]$Text).Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}','';$s=$s -replace '[^a-zA-Z0-9_-]+','-';$s=$s.Trim('-');if(!$s){$s='MiHomebrew'};if($s.Length -gt 48){$s=$s.Substring(0,48)};return $s }
function WriteProjectFiles($P,[string]$Code,[string]$Dir) {
  New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  $assets=Join-Path $Dir 'assets';New-Item -ItemType Directory -Force -Path $assets|Out-Null
  WriteUtf8 (Join-Path $Dir 'project.json') (ConvertTo-Json -InputObject $P -Depth 100)
  if($Code){
    if([string]$P.backend -in @('opengl-ui','vulkan-ui')){WriteUtf8 (Join-Path $Dir 'GeneratedScreen.cpp') $Code}
    else{WriteUtf8 (Join-Path $Dir 'Program.cs') $Code}
  }
  foreach($a in @($P.assets)){
    if(!$a -or !$a.dataUrl){continue}
    $name=[IO.Path]::GetFileName([string]$a.fileName);if(!$name){continue}
    if($a.dataUrl -match '^data:[^;]+;base64,(.*)$'){
      try{[IO.File]::WriteAllBytes((Join-Path $assets $name),[Convert]::FromBase64String($Matches[1]))}
      catch{Write-Host ('[WARN] Recurso omitido por base64 inválido: '+$name) -ForegroundColor Yellow}
    }
  }
}
function InstallRepo($Entry) {
  $dest=Join-Path $script:Toolchains $Entry.folder
  $marker=Test-Path (Join-Path $dest '.ps5hs-source.json')
  if($Entry.method -eq 'git'){
    $gitDir = Join-Path $dest '.git'
    $readmePath = Join-Path $dest 'README.md'
    if ((Test-Path -LiteralPath $gitDir -PathType Container) -and (Test-Path -LiteralPath $readmePath -PathType Leaf)) {
      $gitCmd = CmdInfo 'git.exe'; if (!$gitCmd.ok) { $gitCmd = CmdInfo 'git' }
      $commit = ''
      if ($gitCmd.ok) { try { $commit = ((& $gitCmd.path -C $dest rev-parse HEAD 2>$null) | Out-String).Trim() } catch { } }
      if (!$marker) {
        WriteUtf8 (Join-Path $dest '.ps5hs-source.json') (ConvertTo-Json -InputObject @{repository=$Entry.repo;branch=$Entry.branch;commit=$commit;method='existing git checkout; adopted without overwriting';installedAt=(Get-Date).ToString('o')} -Depth 5)
      }
      return @{ok=$true;name=$Entry.name;message=$(if($marker){'Ya estaba clonado; no se ha sobrescrito.'}else{'Checkout Git existente reconocido y registrado sin sobrescribir archivos.'});path=$dest;commit=$commit}
    }
    if(Test-Path $dest){throw "Existe una carpeta en $dest que no parece un checkout Git válido. No se ha sobrescrito para proteger sus archivos; renómbrala o revisa la carpeta manualmente."}
  } elseif($marker -or (Test-Path (Join-Path $dest 'README.md'))){
    if($Entry.id -ne 'ps5-ultrapack') { return @{ok=$true;name=$Entry.name;message='Ya estaba instalado; no se ha sobrescrito.';path=$dest} }
  }
  # Repair an existing UltraPack checkout in place. Never delete a user's checkout or
  # custom native helper merely because its virtual environment is missing.
  if ($Entry.id -eq 'ps5-ultrapack' -and (Test-Path -LiteralPath $dest -PathType Container)) {
    $existingCli = Join-Path $dest 'backend\cli.py'
    if (!(Test-Path -LiteralPath $existingCli -PathType Leaf)) {
      throw "Existe una carpeta UltraPack incompleta en '$dest' sin backend\cli.py. No se ha sobrescrito para proteger archivos locales; renómbrala manualmente si deseas volver a descargar el repositorio."
    }
    $venvPath = Join-Path $dest '.venv'
    $venvPython = Join-Path $venvPath 'Scripts\python.exe'
    if (!(Test-Path -LiteralPath $venvPython -PathType Leaf)) {
      $pythonCmd = CmdInfo 'python.exe'; if (!$pythonCmd.ok) { $pythonCmd = CmdInfo 'python' }
      if (!$pythonCmd.ok -or !$pythonCmd.path) { throw "La copia de UltraPack ya existe en '$dest'. Instala Python 3.10+ para reparar su entorno virtual sin reemplazar la carpeta." }
      $venvOut = @(& $pythonCmd.path -m venv $venvPath 2>&1); $venvExit = $LASTEXITCODE
      if ($venvExit -ne 0 -or !(Test-Path -LiteralPath $venvPython -PathType Leaf)) {
        $detail = ($venvOut | ForEach-Object { $_.ToString() }) -join "`r`n"
        throw "No se pudo crear el entorno virtual de UltraPack en '$venvPath'. $detail"
      }
    }
    $pipOut = @(& $venvPython -m pip install --disable-pip-version-check py7zr rarfile psutil cryptography 2>&1); $pipExit = $LASTEXITCODE
    if ($pipExit -ne 0) {
      $detail = ($pipOut | ForEach-Object { $_.ToString() }) -join "`r`n"
      throw "No se pudieron instalar las dependencias CLI en '$venvPath'. La carpeta de fuentes se ha conservado. $detail"
    }
    WriteUtf8 (Join-Path $dest '.ps5hs-ultrapack-python.json') (ConvertTo-Json -InputObject @{pythonExe=$venvPython;cli=$existingCli;installedAt=(Get-Date).ToString('o')} -Depth 4)
    return @{ok=$true;name=$Entry.name;message="Entorno Python de UltraPack reparado sin reemplazar fuentes ni helpers locales: $venvPath";path=$dest;pythonExe=$venvPython;cli=$existingCli}
  }
  $temp=Join-Path $script:Runtime ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Force -Path $temp|Out-Null
  try {
    if($Entry.method -eq 'git'){
      $git=CmdInfo 'git.exe';if(!$git.ok){$git=CmdInfo 'git'}
      if(!$git.ok){throw 'Git no está instalado. Usa Configurar entorno para instalar Git y vuelve a intentarlo.'}
      $stage=Join-Path $temp 'checkout'
      $cloneArgs=@('-c','core.longpaths=true','-c','core.autocrlf=false','clone','--recurse-submodules');if(!$Entry.fullHistory){$cloneArgs+=@('--depth','1','--shallow-submodules')};$cloneArgs+=@('--branch',[string]$Entry.branch,('https://github.com/'+$Entry.repo+'.git'),$stage)
      $cloneOut=@(& $git.path @cloneArgs 2>&1);$cloneExit=$LASTEXITCODE
      if($cloneExit -ne 0 -or !(Test-Path (Join-Path $stage 'README.md'))){$detail=($cloneOut|ForEach-Object{$_.ToString()}) -join "`r`n";throw "git clone falló para $($Entry.repo) (código $cloneExit).`r`n$detail"}
      $commit=((& $git.path -C $stage rev-parse HEAD 2>$null)|Out-String).Trim()
      if(Test-Path $dest){Remove-Item $dest -Recurse -Force}
      Move-Item -LiteralPath $stage -Destination $dest
      WriteUtf8 (Join-Path $dest '.ps5hs-source.json') (ConvertTo-Json -InputObject @{repository=$Entry.repo;branch=$Entry.branch;commit=$commit;method='git clone --recurse-submodules';installedAt=(Get-Date).ToString('o')} -Depth 5)
      return @{ok=$true;name=$Entry.name;message="Repositorio clonado con submódulos. Commit: $commit";path=$dest;commit=$commit}
    }
    $zip=Join-Path $temp 'repo.zip';$unpack=Join-Path $temp 'unpack';New-Item -ItemType Directory -Force -Path $unpack|Out-Null;$ok=$false;$why=''
    foreach($branch in (@($Entry.branch,'main','master') | Select-Object -Unique)) { try {Invoke-WebRequest -Uri ('https://codeload.github.com/'+$Entry.repo+'/zip/refs/heads/'+$branch) -OutFile $zip -UseBasicParsing -TimeoutSec 240;if((Get-Item $zip).Length -lt 100){throw 'ZIP vacío'};$ok=$true;break}catch{$why=$_.Exception.Message;Remove-Item $zip -Force -ErrorAction SilentlyContinue } }
    if(!$ok){throw "Descarga fallida de $($Entry.repo): $why"}
    Expand-Archive -LiteralPath $zip -DestinationPath $unpack -Force;$top=Get-ChildItem $unpack -Directory|Select-Object -First 1;if(!$top){throw 'El ZIP no tiene raíz de proyecto.'};if(Test-Path $dest){Remove-Item $dest -Recurse -Force};Move-Item -LiteralPath $top.FullName -Destination $dest;WriteUtf8 (Join-Path $dest '.ps5hs-source.json') (ConvertTo-Json -InputObject @{repository=$Entry.repo;branch=$branch;installedAt=(Get-Date).ToString('o');method='source ZIP'} -Depth 5)
    if($Entry.id -eq 'etahen'){$nid=$script:Catalog|Where-Object id -eq 'nid'|Select-Object -First 1;$nidDir=Join-Path $script:Toolchains $nid.folder;if(!(Test-Path (Join-Path $nidDir 'README.md'))){InstallRepo $nid|Out-Null};$sub=Join-Path $dest 'libNidResolver';if(Test-Path $sub){Remove-Item $sub -Recurse -Force};if(Test-Path $nidDir){Copy-Item -LiteralPath $nidDir -Destination $sub -Recurse}}
    if($Entry.id -eq 'ps5-ultrapack') {
      $pythonCmd = CmdInfo 'python.exe'; if(!$pythonCmd.ok){$pythonCmd=CmdInfo 'python'}
      if($pythonCmd.ok -and $pythonCmd.path) {
        $venvPath = Join-Path $dest '.venv'
        $venvPython = Join-Path $venvPath 'Scripts\python.exe'
        if(!(Test-Path -LiteralPath $venvPython -PathType Leaf)) {
          $venvOut = @(& $pythonCmd.path -m venv $venvPath 2>&1); $venvExit = $LASTEXITCODE
          if($venvExit -ne 0 -or !(Test-Path -LiteralPath $venvPython -PathType Leaf)) {
            $detail = ($venvOut | ForEach-Object { $_.ToString() }) -join "`r`n"
            throw "UltraPack se descargó en '$dest', pero no se pudo crear su entorno Python. Instala Python 3.10+ y vuelve a intentarlo. $detail"
          }
        }
        $pipOut = @(& $venvPython -m pip install --disable-pip-version-check py7zr rarfile psutil cryptography 2>&1); $pipExit = $LASTEXITCODE
        if($pipExit -ne 0) {
          $detail = ($pipOut | ForEach-Object { $_.ToString() }) -join "`r`n"
          throw "UltraPack se descargó en '$dest', pero falló la instalación de dependencias Python en '$venvPath'. Revisa la conexión y el registro de pip. $detail"
        }
        WriteUtf8 (Join-Path $dest '.ps5hs-ultrapack-python.json') (ConvertTo-Json -InputObject @{pythonExe=$venvPython;cli=(Join-Path $dest 'backend\cli.py');installedAt=(Get-Date).ToString('o')} -Depth 4)
        return @{ok=$true;name=$Entry.name;message="Código fuente descargado y dependencias CLI instaladas en el entorno aislado: $venvPath";path=$dest;pythonExe=$venvPython;cli=(Join-Path $dest 'backend\cli.py')}
      }
      return @{ok=$true;name=$Entry.name;message="Código fuente descargado en '$dest'. No se detectó Python; instala Python 3.10+ y configura su ruta en Herramientas. El CLI está en backend\cli.py.";path=$dest;cli=(Join-Path $dest 'backend\cli.py')}
    }
    return @{ok=$true;name=$Entry.name;message="Descargado de GitHub: $dest";path=$dest}
  } finally {Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue}
}
function BashQuote([string]$Text) { return "'" + $Text.Replace("'", "'\''") + "'" }
function ConvertToWslPath([string]$Path) {
  $full=[IO.Path]::GetFullPath($Path)
  if($full -notmatch '^([A-Za-z]):\\(.*)$'){throw "La ruta no puede traducirse a WSL: $full. Usa una carpeta dentro de una unidad local."}
  $drive=$Matches[1].ToLowerInvariant();$rest=$Matches[2] -replace '\\','/'
  return "/mnt/$drive/$rest"
}
function GetWslDrvFsMetadataState([string]$Distribution,[string]$WindowsPath) {
  # DrvFS without metadata cannot perform the chmod Git uses while creating .git/config.lock.
  try {
    $wslTarget = ConvertToWslPath $WindowsPath
    $wsl = CmdInfo 'wsl.exe'
    if (!$wsl.ok) { return @{ applicable = $false; metadata = $true; detail = 'wsl.exe unavailable' } }
    $probeCommand = 'target=' + (BashQuote $wslTarget) + '; if command -v findmnt >/dev/null 2>&1; then findmnt -n -o FSTYPE,OPTIONS -T "$target" 2>/dev/null | head -n1; else echo unknown; fi'
    $probe = @(& $wsl.path -d $Distribution --exec bash -lc $probeCommand 2>$null)
    if ($LASTEXITCODE -ne 0 -or !$probe.Count) { return @{ applicable = $false; metadata = $true; detail = 'Mount probe unavailable' } }
    $line = ([string]$probe[-1]).Trim()
    $parts = $line -split '\s+', 2
    if ($parts.Count -lt 2) { return @{ applicable = $false; metadata = $true; detail = $line } }
    $fsType = [string]$parts[0]
    $options = [string]$parts[1]
    $windowsMount = ($wslTarget -match '^/mnt/[a-z]/') -and (($fsType -match '^(drvfs|9p)') -or ($options -match 'aname=drvfs'))
    $hasMetadata = ($options -split ',') -contains 'metadata'
    return @{ applicable = $windowsMount; metadata = (!$windowsMount -or $hasMetadata); target = $wslTarget; fileSystem = $fsType; options = $options }
  } catch { return @{ applicable = $false; metadata = $true; detail = $_.Exception.Message } }
}
function GetWslPermissionRepairInstructions([string]$Distribution,[string]$WindowsPath) {
  $target = $WindowsPath
  $helper = Join-Path $script:Root 'runtime\fix-wsl-permissions.sh'
  try { $target = ConvertToWslPath $WindowsPath } catch { }
  try { $helper = ConvertToWslPath $helper } catch { $helper = '' }
  $lines = @(
    'WSL no puede cambiar los permisos POSIX de Git en una unidad Windows montada sin la opción DrvFS metadata.',
    ('Ruta que falla: ' + $target),
    '',
    'Reparación segura:',
    ('1. Abre la distribución con: wsl.exe -d "' + $Distribution + '"'),
    $(if ($helper) { '2. En la terminal Linux ejecuta: sudo bash ' + (BashQuote $helper) } else { '2. Ejecuta runtime/fix-wsl-permissions.sh desde la terminal Linux mediante sudo bash.' }),
    '3. Cierra WSL y desde PowerShell de Windows ejecuta: wsl --shutdown',
    '4. Inicia WSL de nuevo y vuelve a compilar desde el IDE.',
    '',
    'El script conserva la configuración existente y crea una copia de seguridad de /etc/wsl.conf. No ejecutes Git ni el IDE como root.',
    'Si metadata ya está habilitado, comprueba los permisos de modificación NTFS de tu usuario de Windows sobre el IDE y sus toolchains.'
  )
  return ($lines -join [Environment]::NewLine)
}
function CopyProjectTree([string]$Source,[string]$Destination,[bool]$IsRoot=$true) {
  $alwaysExclude=@('.git','.deps','.cache','node_modules','__pycache__','.venv','.ps5hs-source.json')
  $rootExclude=@('build','dist','out','obj','.runtime')
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  foreach($item in (Get-ChildItem -LiteralPath $Source -Force -ErrorAction Stop)) {
    if($alwaysExclude -contains $item.Name -or ($IsRoot -and $rootExclude -contains $item.Name)) { continue }
    $childDestination=Join-Path $Destination $item.Name
    if($item.PSIsContainer) {
      CopyProjectTree $item.FullName $childDestination $false
    } else {
      Copy-Item -LiteralPath $item.FullName -Destination $childDestination -Force
    }
  }
}
function NewNativeTitle([string]$Name,[string]$TitleId,[string]$Category,[string]$TemplateId) {
  if($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._-]{0,39}$') { return @{ok=$false;message='Nombre inválido. Usa 1–40 caracteres ASCII: letras, números, espacios, punto, guion o guion bajo.';output=''} }
  if($TitleId -notmatch '^PPSA\d{5}$') { return @{ok=$false;message='TITLE_ID inválido. Formato PPSA12345.';output=''} }
  if($Category -notin @('game','media')) { return @{ok=$false;message='Categoría inválida.';output=''} }
  if($TemplateId -notin @('nativecpp','hui-gl')) { return @{ok=$false;message='La plantilla no dispone de un generador C++ aquí.';output=''} }
  $entry=$script:Catalog | Where-Object id -eq $TemplateId | Select-Object -First 1
  if(!$entry) { return @{ok=$false;message='No se encontró la plantilla en el catálogo.';output=$TemplateId} }
  try { $cloneResult = InstallRepo $entry; if(!$cloneResult.ok) { return @{ok=$false;message=$cloneResult.message;output=$cloneResult.path} } }
  catch { return @{ok=$false;message='No se pudo descargar la plantilla upstream.';output=$_.Exception.Message} }
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
    CopyProjectTree $src $target
    $normalizedLineEndings = NormalizeNativeBuildFiles $target

    # Upstream build.ps1 used to call tools/build.sh directly, bypassing Makefile
    # defaults (src/ include paths, OpenGL SDK includes, archives and import stubs).
    # Route the generated Windows entry point through the canonical Makefile target.
    $buildEntrypoint = Join-Path $target 'build.ps1'
    if (Test-Path -LiteralPath $buildEntrypoint -PathType Leaf) {
      $buildText = [IO.File]::ReadAllText($buildEntrypoint)
      $buildChanged = $false
      $newLine = [Environment]::NewLine
      $oldEnvBlock = '        "APP_STATIC_ARCHIVES",' + $newLine + '        "APP_RUNTIME_MODULES",'
      $newEnvBlock = '        "APP_STATIC_ARCHIVES",' + $newLine + '        "APP_IMPORT_STUBS",' + $newLine + '        "APP_RUNTIME_MODULES",' + $newLine + '        "PS5_OPENGL_PREFIX",' + $newLine + '        "BUILD_JOBS",' + $newLine + '        "USE_CCACHE",'
      if ($buildText.Contains($oldEnvBlock)) {
        $buildText = $buildText.Replace($oldEnvBlock, $newEnvBlock)
        $buildChanged = $true
      }
      $legacyBuildCall = '$arguments += @("bash", (Convert-ToWslPath $build))'
      $makeBuildCall = '$arguments += @("make", "-C", (Convert-ToWslPath (Split-Path -Parent $MyInvocation.MyCommand.Path)), "app")'
      if ($buildText.Contains($legacyBuildCall)) {
        $buildText = $buildText.Replace($legacyBuildCall, $makeBuildCall)
        $buildChanged = $true
      }
      if ($buildChanged) { WriteUtf8 $buildEntrypoint $buildText }
    } elseif (!(Test-Path -LiteralPath (Join-Path $target 'Makefile') -PathType Leaf)) {
      throw 'La plantilla no contiene build.ps1 ni Makefile; no se puede asignar un perfil de compilación seguro.'
    }
    $initializer=Join-Path $target 'tools/init-project.sh'
    $paramPath=Join-Path $target 'sce_sys/param.json'
    $targetWsl=ConvertToWslPath $target
    $wsl=CmdInfo 'wsl.exe'
    if(!$wsl.ok) { throw 'wsl.exe no está disponible.' }
    if ((Test-Path -LiteralPath $initializer -PathType Leaf) -and (Test-Path -LiteralPath $paramPath -PathType Leaf)) {
      $initWsl=ConvertToWslPath $initializer
      $paramWsl=ConvertToWslPath $paramPath
      $cmd='cd '+(BashQuote $targetWsl)+' && TITLE_ID='+(BashQuote $TitleId)+' APP_NAME='+(BashQuote $Name)+' APP_CATEGORY='+(BashQuote $Category)+' CONTENT_SUFFIX='+(BashQuote $suffix)+' bash '+(BashQuote $initWsl)+' '+(BashQuote $paramWsl)
    } else {
      $cmd='cd '+(BashQuote $targetWsl)+' && make init TITLE_ID='+(BashQuote $TitleId)+' APP_NAME='+(BashQuote $Name)+' APP_CATEGORY='+(BashQuote $Category)
    }
    $output=@(& $wsl.path -d $dist --exec bash -lc $cmd 2>&1)
    $exit=$LASTEXITCODE
    $log=($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    $valid=($exit -eq 0 -and (Test-Path $paramPath) -and (Test-Path (Join-Path $target 'src/main.cpp')) -and (Test-Path (Join-Path $target 'Makefile')))
    if($valid) {
      $summary=@{schema='ps5hs-native-project';template=$TemplateId;repository=$entry.repo;titleId=$TitleId;name=$Name;category=$Category;initializedAt=(Get-Date).ToString('o')}
      WriteUtf8 (Join-Path $target '.ps5hs-project.json') (ConvertTo-Json -InputObject $summary -Depth 5)
      return @{ok=$true;message=$(if($TemplateId -eq 'hui-gl'){'Proyecto de interfaz OpenGL creado desde ps5-homebrew-ui upstream.'}else{'Proyecto C++20 nativo creado desde ps5-native-app-boilerplate upstream.'});output=$log;path=$target;titleId=$TitleId;templateId=$TemplateId;build='not-run'}
    }
    return @{ok=$false;message="El inicializador upstream finalizó con código $exit o no dejó la estructura esperada.";output=$log;path=$target;titleId=$TitleId}
  } catch {
    return @{ok=$false;message=$_.Exception.Message;output='Fallo al copiar la plantilla o ejecutar tools/init-project.sh mediante WSL.';path=$target;titleId=$TitleId}
  }
}

function NewVulkanTitle([string]$Name,[string]$TitleId,[string]$Design) {
  if($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._-]{0,39}$'){return @{ok=$false;message='Nombre inválido. Usa 1–40 caracteres ASCII: letras, números, espacios, punto, guion o guion bajo.';output=''}}
  if($TitleId -notmatch '^PPSA\d{5}$'){return @{ok=$false;message='TITLE_ID inválido. Formato exigido por el generador: PPSA12345.';output=''}}
  if($Design -notin @('starter','aurora','settings','store','hud')){return @{ok=$false;message='Diseño no admitido por este asistente.';output=''}}
  $entry=$script:Catalog|Where-Object id -eq 'vulkan-template'|Select-Object -First 1
  if(!$entry) { return @{ok=$false;message='No está registrada la plantilla Vulkan.';output='vulkan-template'} }
  try { $cloneResult = InstallRepo $entry; if(!$cloneResult.ok) { return @{ok=$false;message=$cloneResult.message;output=$cloneResult.path} } }
  catch { return @{ok=$false;message='No se pudo descargar PS5 Vulkan Template.';output=$_.Exception.Message} }
  $repo=Join-Path $script:Toolchains $entry.folder;$generator=Join-Path $repo 'ps5/tools/new-title.py'
  if(!(Test-Path $generator)){return @{ok=$false;message='El checkout de PS5 Vulkan Template no contiene ps5/tools/new-title.py.';output=$repo}}
  $st=GetStatus;if(!$st.prerequisites.wsl){return @{ok=$false;message='No hay distribución WSL inicializada.';output='Configura WSL + Debian desde Configurar entorno y realiza su primer arranque.'}}
  if(!$st.prerequisites.wslGitPython){return @{ok=$false;message='Faltan Git o Python 3 dentro de WSL.';output='Abre la distribución WSL y ejecuta la instalación de git y python3 conforme a BUILD.md/README upstream.'}}
  $dist=[string]$st.wslDistribution
  $slug=Slug $Name;$target=Join-Path $script:Workspace ($slug+'-Vulkan')
  if(Test-Path $target){return @{ok=$false;message='Ya existe la carpeta de destino. Cambia el nombre del proyecto para no sobrescribirlo.';output=$target;path=$target}}
  try {
    $repoWsl=ConvertToWslPath $repo;$targetWsl=ConvertToWslPath $target;$generatorWsl=ConvertToWslPath $generator
    $cmd='python3 '+(BashQuote $generatorWsl)+' '+(BashQuote $targetWsl)+' --title-id '+(BashQuote $TitleId)+' --name '+(BashQuote $Name)
    if($Design -ne 'starter'){$cmd+=' --ui '+(BashQuote $Design)}
    $wsl=CmdInfo 'wsl.exe';if(!$wsl.ok){throw 'wsl.exe no está disponible.'};$output=@(& $wsl.path -d $dist --exec bash -lc $cmd 2>&1);$exit=$LASTEXITCODE;$log=($output|ForEach-Object{$_.ToString()}) -join "`r`n"
    $valid=($exit -eq 0 -and (Test-Path (Join-Path $target 'README.md')) -and (Test-Path (Join-Path $target 'ps5')))
    if($valid){$summary=@{schema='ps5hs-native-project';template='vulkan-template';repository=$entry.repo;titleId=$TitleId;name=$Name;category='game';design=$Design;initializedAt=(Get-Date).ToString('o')};WriteUtf8 (Join-Path $target '.ps5hs-project.json') (ConvertTo-Json -InputObject $summary -Depth 5);return @{ok=$true;message='Proyecto C++ nativo generado por el generador upstream PS5 Vulkan Template. Todavía no se ha compilado.';output=$log;path=$target;titleId=$TitleId;design=$Design;templateId='vulkan-template';build='not-run'}}
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
      if ($match.Success) { return $match.Value.ToUpperInvariant() }
    } catch { }
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
  $hasMainCpp = Test-Path -LiteralPath (Join-Path $ProjectRoot 'src/main.cpp') -PathType Leaf
  $hasLegacyInit = Test-Path -LiteralPath (Join-Path $ProjectRoot 'tools/init-project.sh') -PathType Leaf
  $makeText = ''
  if ($hasMakefile) { try { $makeText = Get-Content -LiteralPath (Join-Path $ProjectRoot 'Makefile') -Raw } catch { $makeText = '' } }
  $hasMakeInit = [bool]($makeText -match '(?m)^\s*init\s*:')

  $hasVulkanGenerator = Test-Path -LiteralPath (Join-Path $ProjectRoot 'ps5/tools/new-title.py') -PathType Leaf
  $hasVulkanBuild = Test-Path -LiteralPath (Join-Path $ProjectRoot 'ps5/tools/build.sh') -PathType Leaf
  $hasUiFontTool = Test-Path -LiteralPath (Join-Path $ProjectRoot 'tools/bake-fonts.sh') -PathType Leaf
  $template = ''
  if ($meta -and $meta.schema -eq 'ps5hs-native-project' -and [string]$meta.template -in @('nativecpp','hui-gl','vulkan-template')) {
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
  if ($meta -and [string]$meta.titleId -match '^PPSA\d{5}$') { $titleId = [string]$meta.titleId }
  if (!$titleId) { $titleId = GetProjectTitleId $ProjectRoot }
  $initialized = ($hasParam -and $titleId -match '^PPSA\d{5}$' -and $titleId -ne 'PPSA00000')
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
    try { $supportsClean = [bool]((Get-Content -LiteralPath (Join-Path $ProjectRoot 'Makefile') -Raw) -match '(?m)^\s*clean\s*:') } catch { }
  }
  $isRelevant = ((Test-Path -LiteralPath $markerPath -PathType Leaf) -or $remote -or $hasMakefile -or (Test-Path -LiteralPath (Join-Path $ProjectRoot 'CMakeLists.txt') -PathType Leaf) -or $hasVulkanGenerator -or (Test-Path -LiteralPath (Join-Path $ProjectRoot 'build.ps1') -PathType Leaf))
  return @{
    name = $(if ($meta -and $meta.name) { [string]$meta.name } else { $name })
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
    recognized = [bool]($template -in @('nativecpp','hui-gl','vulkan-template'))
    relevant = [bool]$isRelevant
  }
}
function GetMissingProjectDependencies($Profile) {
  $missing = @()
  foreach ($dependencyId in @($Profile.dependencies)) {
    $entry = $script:Catalog | Where-Object id -eq ([string]$dependencyId) | Select-Object -First 1
    if (!$entry) { $missing += [string]$dependencyId; continue }
    $dependencyPath = Join-Path $script:Toolchains $entry.folder
    $hasSource = ((Test-Path -LiteralPath (Join-Path $dependencyPath '.git') -PathType Container) -and (Test-Path -LiteralPath (Join-Path $dependencyPath 'README.md') -PathType Leaf))
    if (!$hasSource) { $missing += [string]$entry.name; continue }
    if ($dependencyId -eq 'opengl' -and !(Test-Path -LiteralPath (Join-Path $dependencyPath 'build/sdk/ps5-opengl-gl46') -PathType Container)) {
      $missing += 'PS5 OpenGL SDK (necesita compilarse)'
    }
  }
  return ,@($missing)
}
function GetGeneratedProjects {
  $items = @()
  foreach ($dir in (Get-ChildItem -LiteralPath $script:Workspace -Directory -ErrorAction SilentlyContinue)) {
    $profile = GetProjectProfile $dir.FullName
    if (!$profile.relevant) { continue }
    $artifact = ''
    $built = $false
    $eboots = @(GetProjectEbootFolders $dir.FullName)
    foreach ($eboot in $eboots) {
      $ebootFolder = Split-Path -Parent $eboot.FullName
      $paramPath = Join-Path $ebootFolder 'sce_sys\param.json'
      if (!(Test-Path -LiteralPath $paramPath -PathType Leaf)) { $paramPath = Join-Path $dir.FullName 'sce_sys\param.json' }
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

function GetNativePresentationState([string]$ProjectRoot) {
  $sceSys = Join-Path $ProjectRoot 'sce_sys'
  $paramPath = Join-Path $sceSys 'param.json'
  $assetScript = Join-Path $ProjectRoot 'tools\prepare-assets.ps1'
  if (!(Test-Path -LiteralPath $assetScript -PathType Leaf)) {
    $assetScript = Join-Path $script:Toolchains 'ps5-native-app-boilerplate\tools\prepare-assets.ps1'
  }
  $texconv = CmdInfo 'texconv.exe'
  if (!$texconv.ok) { $texconv = CmdInfo 'texconv' }
  $ffmpeg = CmdInfo 'ffmpeg.exe'
  if (!$ffmpeg.ok) { $ffmpeg = CmdInfo 'ffmpeg' }
  $at9 = CmdInfo 'ps4_at9tool.exe'
  return @{
    editable = [bool](Test-Path -LiteralPath $paramPath -PathType Leaf)
    icon = [bool](Test-Path -LiteralPath (Join-Path $sceSys 'icon0.png') -PathType Leaf)
    selectionBackground = [bool](Test-Path -LiteralPath (Join-Path $sceSys 'pic0.dds') -PathType Leaf)
    launchBackground = [bool](Test-Path -LiteralPath (Join-Path $sceSys 'pic1.dds') -PathType Leaf)
    music = [bool](Test-Path -LiteralPath (Join-Path $sceSys 'snd0.at9') -PathType Leaf)
    conversionScript = [bool](Test-Path -LiteralPath $assetScript -PathType Leaf)
    texconv = [bool]$texconv.ok
    ffmpeg = [bool]$ffmpeg.ok
    at9Encoder = [bool]$at9.ok
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
  $sceSys = Join-Path $full 'sce_sys'
  if (!(Test-Path -LiteralPath $sceSys -PathType Container)) { throw 'Este proyecto no contiene sce_sys/ en la raíz.' }
  $sceItem = Get-Item -LiteralPath $sceSys -Force
  if (($sceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'No se permite editar recursos a través de un enlace sce_sys.'
  }
  $paramPath = Join-Path $sceSys 'param.json'
  if (!(Test-Path -LiteralPath $paramPath -PathType Leaf)) {
    throw 'Falta sce_sys/param.json. Inicializa primero el título PS5 antes de personalizar su presentación.'
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
  $hasIcon = $null -ne $Body.icon
  $hasSelectionBackground = $null -ne $Body.selectionBackground
  $hasLaunchBackground = $null -ne $Body.launchBackground
  $hasAudio = $null -ne $Body.audio
  if (!$hasIcon -and !$hasSelectionBackground -and !$hasLaunchBackground -and !$hasAudio) { throw 'Selecciona al menos un recurso para sustituir.' }
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
    $audioExtensions = @('.at9','.mp3','.wav','.ogg','.m4a','.aac','.flac')
    $iconPath = ''
    $selectionBackgroundPath = ''
    $launchBackgroundPath = ''
    $audioPath = ''
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
    }

    $helper = Join-Path $project.path 'tools\prepare-assets.ps1'
    if (!(Test-Path -LiteralPath $helper -PathType Leaf)) {
      $helper = Join-Path $script:Toolchains 'ps5-native-app-boilerplate\tools\prepare-assets.ps1'
    }
    $arguments = @{ OutputDirectory = $stageDir }
    if ($iconPath) { $arguments['Icon'] = $iconPath }
    if ($selectionBackgroundPath) { $arguments['SelectionBackground'] = $selectionBackgroundPath }
    if ($launchBackgroundPath) { $arguments['LaunchBackground'] = $launchBackgroundPath }
    if ($audioPath) { $arguments['Audio'] = $audioPath }
    $toolOutput = @()
    try {
      $toolOutput = @(& $helper @arguments 2>&1 | ForEach-Object { [string]$_ })
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
    return @{
      ok = $true
      message = 'Presentación actualizada: ' + ($summary -join ', ') + '.'
      output = (@($toolOutput) -join "`n")
      path = $project.path
      presentation = $finalState
    }
  }
  catch {
    for ($index = $changedFiles.Count - 1; $index -ge 0; $index--) {
      $filename = [string]$changedFiles[$index]
      $destination = Join-Path $project.sceSys $filename
      $backup = Join-Path $backupDir $filename
      try {
        if (Test-Path -LiteralPath $backup -PathType Leaf) { [IO.File]::Copy($backup, $destination, $true) }
        elseif (Test-Path -LiteralPath $destination -PathType Leaf) { Remove-Item -LiteralPath $destination -Force }
      } catch { }
    }
    throw
  }
  finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
      try { Remove-Item -LiteralPath $tempRoot -Recurse -Force } catch { }
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
  $markerPath = Join-Path $projectRoot '.ps5hs-project.json'
  if (!(Test-Path -LiteralPath $markerPath -PathType Leaf)) { throw 'No se encontró .ps5hs-project.json. Abre un proyecto nativo creado por Homebrew Studio.' }
  try { $meta = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json } catch { throw 'El manifiesto del proyecto no se puede leer.' }
  if ($meta.schema -ne 'ps5hs-native-project' -or [string]$meta.template -notin @('nativecpp','hui-gl','vulkan-template')) {
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
  if ($RequireParamJson -and (Test-Path -LiteralPath (Join-Path $ProjectRoot 'sce_sys\param.json') -PathType Leaf)) {
    $selected = $eboots | Select-Object -First 1
    $sourceFolder = Split-Path -Parent $selected.FullName
    $stageRoot = Join-Path (Join-Path $script:Runtime 'ultrapack-staging') ([IO.Path]::GetFileName($ProjectRoot))
    if (Test-Path -LiteralPath $stageRoot -PathType Container) { Remove-Item -LiteralPath $stageRoot -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
    foreach ($child in (Get-ChildItem -LiteralPath $sourceFolder -Force -ErrorAction SilentlyContinue)) {
      Copy-Item -LiteralPath $child.FullName -Destination $stageRoot -Recurse -Force
    }
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'sce_sys') -Destination $stageRoot -Recurse -Force
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
  $verifyEnabled = [bool]$Body.verify
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
  try { [IO.File]::AppendAllText($Path, ([string]$Message + [Environment]::NewLine), $script:Utf8) } catch { }
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
  WriteBuildJobLog (Join-Path $dir 'build.log') 'Preparando la generación C++20 y la compilación upstream…'
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
  if ($TitleId -notmatch '^PPSA\d{5}$' -or $TitleId -eq 'PPSA00000') { return @{ok=$false;message='TITLE_ID debe tener el formato PPSA12345.';output=''} }
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

function BuildNativeProject([string]$ProjectPath,[bool]$CleanBeforeBuild=$false,[string]$RequestedTitleId='',[string]$RequestedName='') {
  $workspaceRoot = [IO.Path]::GetFullPath($script:Workspace)
  $separator = [string]([IO.Path]::DirectorySeparatorChar)
  if (!$workspaceRoot.EndsWith($separator)) { $workspaceRoot += $separator }
  try { $projectRoot = [IO.Path]::GetFullPath($ProjectPath) }
  catch { return @{ok=$false;message='La ruta del proyecto no es válida.';output=$_.Exception.Message} }
  if (!$projectRoot.StartsWith($workspaceRoot, [StringComparison]::OrdinalIgnoreCase)) {
    return @{ok=$false;message='Solo se permite compilar proyectos creados dentro del workspace de Homebrew Studio.';output=$projectRoot}
  }
  $markerPath = Join-Path $projectRoot '.ps5hs-project.json'
  $profile = GetProjectProfile $projectRoot
  $template = [string]$profile.template
  if ($template -notin @('nativecpp','hui-gl','vulkan-template')) {
    return @{ok=$false;message=('No hay un perfil de compilación de título compatible: ' + [string]$profile.typeLabel);output=[string]$profile.buildReason;path=$projectRoot;profile=$profile.typeLabel}
  }
  $st = GetStatus
  if (!$st.prerequisites.wsl) { return @{ok=$false;message='No hay una distribución WSL inicializada.';output='Configura WSL + Debian y completa su primer arranque.';templateId=$template} }
  if (!$st.prerequisites.wslGitPython) { return @{ok=$false;message='Faltan Git o Python 3 dentro de WSL.';output='Instala git y python3 en la distribución Linux indicada por la documentación upstream.';templateId=$template} }
  $dist = [string]$st.wslDistribution
  if ($profile.needsInit) {
    $titleId = ([string]$RequestedTitleId).Trim().ToUpperInvariant()
    $projectName = ([string]$RequestedName).Trim()
    if ($titleId -notmatch '^PPSA\d{5}$' -or $titleId -eq 'PPSA00000' -or !$projectName) {
      return @{ok=$false;message='El proyecto se reconoce, pero requiere inicialización. Introduce un nombre y un TITLE_ID válido (PPSA12345).';output=[string]$profile.typeLabel;path=$projectRoot;templateId=$template;needsInit=$true;titleId=$profile.titleId}
    }
    $initResult = InitializeNativeProjectFolder $projectRoot $template $titleId $projectName 'game' $dist
    if (!$initResult.ok) { return @{ok=$false;message=$initResult.message;output=$initResult.output;path=$projectRoot;templateId=$template;needsInit=$true} }
    WriteBuildJobLog $script:ActiveBuildLogPath ([string]$initResult.message)
    if ($initResult.output) { WriteBuildJobLog $script:ActiveBuildLogPath ([string]$initResult.output) }
    $profile = GetProjectProfile $projectRoot
  }
  if (!(Test-Path -LiteralPath $markerPath -PathType Leaf)) {
    if (!$profile.initialized) { return @{ok=$false;message='El proyecto todavía no tiene metadatos de título válidos.';output=$projectRoot;templateId=$template;needsInit=$true} }
    $entry = $script:Catalog | Where-Object id -eq $template | Select-Object -First 1
    $meta = @{schema='ps5hs-native-project';template=$template;repository=$(if($entry){[string]$entry.repo}else{[string]$profile.repository});titleId=[string]$profile.titleId;name=[string]$profile.name;category='game';initializedAt=(Get-Date).ToString('o')}
    WriteUtf8 $markerPath (ConvertTo-Json -InputObject $meta -Depth 5)
  }
  try { $meta = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json }
  catch { return @{ok=$false;message='El manifiesto del proyecto no se puede leer.';output=$_.Exception.Message} }
  if ($template -eq 'hui-gl') { try { EnableEuropeanFontAtlas $projectRoot } catch { return @{ok=$false;message=$_.Exception.Message;output=$_.Exception.Message;path=$projectRoot;templateId=$template} } }
  try { $normalizedLineEndings = NormalizeNativeBuildFiles $projectRoot }
  catch { return @{ok=$false;message='No se pudieron normalizar los finales de línea de los archivos nativos.';output=$_.Exception.Message;templateId=$template} }
  $scriptPath = ''
  if ($template -in @('nativecpp','hui-gl')) {
    if (!(Test-Path -LiteralPath (Join-Path $projectRoot 'Makefile') -PathType Leaf)) {
      return @{ok=$false;message='La carpeta no contiene un Makefile upstream.';output=$projectRoot;templateId=$template}
    }
  } else {
    $scriptPath = Join-Path $projectRoot 'ps5/tools/build.sh'
    if (!(Test-Path $scriptPath)) { return @{ok=$false;message='Falta ps5/tools/build.sh en el título Vulkan generado.';output=$projectRoot;templateId=$template} }
  }
  $st = GetStatus
  if (!$st.prerequisites.wsl) { return @{ok=$false;message='No hay una distribución WSL inicializada.';output='Configura WSL + Debian y completa su primer arranque.';templateId=$template} }
  if (!$st.prerequisites.wslGitPython) { return @{ok=$false;message='Faltan Git o Python 3 dentro de WSL.';output='Instala git y python3 en la distribución Linux indicada por la documentación upstream.';templateId=$template} }
  $dist = [string]$st.wslDistribution
  # A Homebrew Studio OpenGL project has its own supported Windows entry point.
  # Prefer it over preparing a second shared SDK under toolchains/ on a different
  # drive. build.ps1 resolves the project-local pinned SDK/dependencies and is the
  # same command users can run manually from the project directory.
  $studioBuildScript = Join-Path $projectRoot 'build.ps1'
  if ($template -eq 'hui-gl' -and [bool]$meta.generatedFromStudio -and (Test-Path -LiteralPath $studioBuildScript -PathType Leaf)) {
    $shell = CmdInfo 'pwsh.exe'
    if (!$shell.ok) { $shell = CmdInfo 'pwsh' }
    if (!$shell.ok) { $shell = CmdInfo 'powershell.exe' }
    if (!$shell.ok) { throw 'No se encontró PowerShell para ejecutar el build.ps1 del proyecto.' }
    WriteBuildJobLog $script:ActiveBuildLogPath 'Proyecto visual de Homebrew Studio detectado: se usa el build.ps1 del propio proyecto y su SDK local. Se omite la compilación redundante del SDK compartido en toolchains/.'
    if ($CleanBeforeBuild) {
      $cleanWslPath = ConvertToWslPath $projectRoot
      $cleanWsl = CmdInfo 'wsl.exe'
      if (!$cleanWsl.ok) { throw 'No se pudo localizar wsl.exe para ejecutar la limpieza previa solicitada.' }
      $cleanCommand = 'cd ' + (BashQuote $cleanWslPath) + ' && if make -qp 2>/dev/null | grep -qE ' + (BashQuote '^[[:space:]]*clean[[:space:]]*:') + '; then echo "[CLEAN] Ejecutando make clean en el proyecto"; make clean; else echo "[CLEAN] El Makefile no declara clean; se conserva la salida anterior"; fi'
      $cleanOutput = @(& $cleanWsl.path -d $dist --exec bash -lc $cleanCommand 2>&1 | ForEach-Object { $line=$_.ToString(); WriteBuildJobLog $script:ActiveBuildLogPath $line; $line })
      $cleanExit = $LASTEXITCODE
      if ($cleanExit -ne 0) { throw ('Falló make clean antes de build.ps1 (código ' + $cleanExit + '): ' + (($cleanOutput | ForEach-Object { [string]$_ }) -join "`r`n")) }
    }
    $studioOutput = @()
    $studioExit = 1
    Push-Location -LiteralPath $projectRoot
    try {
      $studioOutput = @(& $shell.path -NoLogo -NoProfile -ExecutionPolicy Bypass -File $studioBuildScript 2>&1 | ForEach-Object {
        $line = $_.ToString()
        WriteBuildJobLog $script:ActiveBuildLogPath $line
        $line
      })
      $studioExit = $LASTEXITCODE
    } catch {
      $studioOutput += [string]$_.Exception.Message
      $studioExit = 1
    } finally { Pop-Location }
    $studioLog = ($studioOutput | ForEach-Object { [string]$_ }) -join "`r`n"
    $artifact = ''
    $eboots = @(GetProjectEbootFolders $projectRoot)
    foreach ($candidate in $eboots) {
      $titleFolder = Split-Path -Parent $candidate.FullName
      $paramPath = Join-Path $titleFolder 'sce_sys\param.json'
      if (!(Test-Path -LiteralPath $paramPath -PathType Leaf)) { $paramPath = Join-Path $projectRoot 'sce_sys\param.json' }
      if (Test-Path -LiteralPath $paramPath -PathType Leaf) { $artifact = $candidate.FullName; break }
    }
    if ($studioExit -eq 0 -and $artifact) {
      return @{ok=$true;message='El build.ps1 del proyecto terminó correctamente; eboot.bin y sce_sys/param.json verificados.';output=$studioLog;path=$projectRoot;artifact=$artifact;templateId=$template;titleId=[string]$meta.titleId;exitCode=0;buildEntryPoint=$studioBuildScript}
    }
    return @{ok=$false;message="El build.ps1 del proyecto terminó con código $studioExit o no produjo un título actual verificable (eboot.bin + sce_sys/param.json).";output=$studioLog;path=$projectRoot;artifact=$artifact;templateId=$template;titleId=[string]$meta.titleId;exitCode=$studioExit;buildEntryPoint=$studioBuildScript;diagnostics=@(@{severity='error';title='Falló build.ps1';message='Se ejecutó el pipeline del propio proyecto. Revisa su salida para ver el error real; no se intentó reconstruir otra copia del SDK compartido.';location=$studioBuildScript})}
  }
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
      if (!(Test-Path (Join-Path $vulkanDir '.git')) -or !(Test-Path (Join-Path $payloadSdkDir '.git')) -or !(Test-Path (Join-Path $mesaDir '.git'))) {
        throw 'No están disponibles los checkouts Git completos de PS5_Vulkan, PS5_PayloadSDK y PS5_Mesa.'
      }
      $restored = EnsureVulkanBuildSupport $vulkanDir
      if ($restored.Count -gt 0) { $dependencyLog += 'Se restauraron helpers upstream ausentes en PS5_Vulkan; detalle en .ps5hs-compatibility.json.' }
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
      $openglSdkDir = Join-Path $openglDir 'build/sdk/ps5-opengl-gl46'
      if (!(Test-Path -LiteralPath $openglSdkDir -PathType Container)) {
        $mountState = GetWslDrvFsMetadataState $dist $openglDir
        if ($mountState.applicable -and !$mountState.metadata) {
          throw (GetWslPermissionRepairInstructions $dist $openglDir)
        }
        $openglWsl = ConvertToWslPath $openglDir
        $nativeWsl = ConvertToWslPath $nativeDir
        $sdkGlPattern = BashQuote '^[[:space:]]*sdk-gl46[[:space:]]*:'
        $sdkPattern = BashQuote '^[[:space:]]*sdk[[:space:]]*:'
        $sdkCmd = 'cd ' + (BashQuote $openglWsl) + ' && export PS5_NATIVE_APP_TEMPLATE=' + (BashQuote $nativeWsl) + ' && make source-fetch && if make -qp 2>/dev/null | grep -qE ' + $sdkGlPattern + '; then make sdk-gl46; elif make -qp 2>/dev/null | grep -qE ' + $sdkPattern + '; then make sdk; else echo "No hay target SDK compatible (sdk-gl46/sdk)."; exit 72; fi'
        WriteBuildJobLog $script:ActiveBuildLogPath 'Preparando las dependencias del backend OpenGL y compilando su SDK upstream si falta.'
        $sdkOutput = @(& $wsl.path -d $dist --exec bash -lc $sdkCmd 2>&1 | ForEach-Object { $line=$_.ToString(); WriteBuildJobLog $script:ActiveBuildLogPath $line; $line })
        $sdkExit = $LASTEXITCODE
        if ($sdkExit -ne 0 -or !(Test-Path -LiteralPath $openglSdkDir -PathType Container)) {
          $sdkLogText = ($sdkOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
          if ($sdkLogText -match 'chmod on .+\.git/config\.lock failed: Operation not permitted|could not set .core\.filemode.') {
            throw (GetWslPermissionRepairInstructions $dist $openglDir)
          }
          throw "No se pudo generar PS5 OpenGL SDK (código $sdkExit). Revisa el log anterior."
        }
      }
      $openglPrefix = ConvertToWslPath $openglSdkDir
      $nativeWsl = ConvertToWslPath $nativeDir
      $cmd = 'cd ' + (BashQuote $projectWsl) + ' && export PS5_NATIVE_APP_TEMPLATE=' + (BashQuote $nativeWsl) + ' PS5_OPENGL_PREFIX=' + (BashQuote $openglPrefix) + ' USE_CCACHE=' + $ccacheValue + ' && make deps && '
      if (Test-Path -LiteralPath (Join-Path $projectRoot 'tools/bake-fonts.sh') -PathType Leaf) { $cmd += 'bash tools/bake-fonts.sh && ' }
      $cmd += $cleanCommand + 'USE_CCACHE=' + $ccacheValue + ' make'
    } elseif ($template -eq 'nativecpp') {
      $cmd = 'cd ' + (BashQuote $projectWsl) + ' && ' + $cleanCommand + 'USE_CCACHE=' + $ccacheValue + ' make'
    } else {
      $vulkanWsl = ConvertToWslPath $vulkanDir
      $payloadSdkWsl = ConvertToWslPath $payloadSdkDir
      $mesaWsl = ConvertToWslPath $mesaDir
      $buildScriptWsl = ConvertToWslPath $scriptPath
      # The title build consumes the already-built RADV archive, host ELF/FSELF tool,
      # runtime and SDK caches produced by PS5_Vulkan's own scripts. Keep its SDK
      # cache separate from the title's later pin (they intentionally use distinct revisions).
      $refreshNotices = 'python3 ps5/tools/build-assets.py --notices'
      $bootstrap = 'cd ' + (BashQuote $projectWsl) + ' && ' + $refreshNotices + ' && cd ' + (BashQuote $vulkanWsl) +
        ' && USE_CCACHE=' + $ccacheValue + ' PS5_PAYLOAD_SDK_FORK=' + (BashQuote $payloadSdkWsl) + ' bash tools/setup-native-dependencies.sh' +
        ' && USE_CCACHE=' + $ccacheValue + ' bash tools/build-host-tools.sh' +
        ' && PS5_PAYLOAD_SDK_FORK=' + (BashQuote $payloadSdkWsl) + ' bash tools/rebuild-libc.sh' +
        ' && PS5_PAYLOAD_SDK_FORK=' + (BashQuote $payloadSdkWsl) + ' PS5_MESA_FORK=' + (BashQuote $mesaWsl) + ' bash tools/build-radv.sh release'
      $cmd = $bootstrap + ' && cd ' + (BashQuote $projectWsl) + ' && USE_CCACHE=' + $ccacheValue + ' PS5_VULKAN_DIR=' + (BashQuote $vulkanWsl) + ' PS5_PAYLOAD_SDK_FORK=' + (BashQuote $payloadSdkWsl) + ' bash ' + (BashQuote $buildScriptWsl)
    }
    # Preserve the last usable title if a rebuild fails. A successful build is accepted only
    # when the pipeline exits zero and an eboot.bin plus title metadata can be verified.
    WriteBuildJobLog $script:ActiveBuildLogPath 'Ejecutando el pipeline real de WSL/Make/CMake/Ninja. La salida se transmite al registro mientras avanza.'
    $output = @(& $wsl.path -d $dist --exec bash -lc $cmd 2>&1 | ForEach-Object {
      $line = $_.ToString()
      WriteBuildJobLog $script:ActiveBuildLogPath $line
      $line
    })
    $exit = $LASTEXITCODE
    $buildLog = ($output | ForEach-Object { $_.ToString() }) -join "`r`n"
    if ($dependencyLog.Count) { $buildLog = (($dependencyLog -join "`r`n") + "`r`n" + $buildLog) }
    $artifact = ''
    $eboots = @(GetProjectEbootFolders $projectRoot)
    if ($eboots.Count -gt 0) {
      $candidate = $eboots[0]
      $titleFolder = Split-Path -Parent $candidate.FullName
      $paramPath = Join-Path $titleFolder 'sce_sys\\param.json'
      if (!(Test-Path -LiteralPath $paramPath -PathType Leaf)) { $paramPath = Join-Path $projectRoot 'sce_sys\\param.json' }
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
    [IO.File]::WriteAllBytes($temporary,$bytes)
    Move-Item -LiteralPath $temporary -Destination $destination -Force | Out-Null
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
  $source = Get-Content -LiteralPath $programPath -Raw
  if (!$source.Contains('ps5hs_load_textures(kit.renderer)')) {
    if (!$source.Contains('#include "kit.hpp"')) { throw 'No se puede inyectar el runtime de texturas: falta include kit.hpp.' }
    $assetPaths = @($incoming | ForEach-Object { 'ps5hs/' + ([string]$_.id) + '.rgba' } | Sort-Object -Unique)
    if ($assetPaths.Count -gt 0) { $pathLiterals = ($assetPaths | ForEach-Object { '        ' + (ConvertTo-Json -InputObject $_ -Compress) }) -join ",`r`n" }
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
    $source = $source.Replace('#include "kit.hpp"', '#include "kit.hpp"' + "`r`n" + $helper)
    if (!$source.Contains('ps5hs_load_textures(kit.renderer)')) {
      if (!$source.Contains('prepareKit();')) { throw 'No se encontró prepareKit() para cargar las texturas Vulkan.' }
      $source = $source.Replace('prepareKit();', "prepareKit();`r`n        ps5ui::ps5hs_load_textures(kit.renderer);")
    }
    WriteUtf8 $programPath $source
  }
  return @{ok=$true;count=$incoming.Count;source=$programPath}
}


function PrepareNativeUnicodeFonts($Body,[string]$ProjectRoot,[string]$Backend) {
  $font = $Body.nativeFont
  if (!$font -or [string]::IsNullOrWhiteSpace([string]$font.base64)) { return @{enabled=$false;glyphCount=0} }
  $fileName = [IO.Path]::GetFileName([string]$font.fileName)
  if ($fileName -notmatch '\.ttf
  WriteBuildJobLog $script:ActiveBuildLogPath 'Validando el modelo visual, el backend y los metadatos del título…'
  $backend = [string]$Body.backend
  if ($backend -notin @('opengl-ui','vulkan-ui')) {
    return @{ok=$false;message='Backend nativo visual desconocido.';output=$backend}
  }
  $name = [string]$Body.project.name
  $titleId = ([string]$Body.titleId).Trim().ToUpperInvariant()
  $code = [string]$Body.programCode
  if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._-]{0,39}$') {
    return @{ok=$false;message='Nombre inválido. Usa entre 1 y 40 caracteres ASCII.';output=$name}
  }
  if ($titleId -notmatch '^PPSA\d{5}$') {
    return @{ok=$false;message='TITLE_ID inválido. Usa PPSA seguido de cinco dígitos.';output=$titleId}
  }
  $requiredFactory = if ($backend -eq 'vulkan-ui') { 'make_screen' } else { 'make_ps5hs_generated' }
  if ($code.Length -lt 2000 -or !$code.Contains($requiredFactory) -or !$code.Contains('GeneratedScreen')) {
    return @{ok=$false;message='El código no corresponde al generador C++20 del backend seleccionado. No se ha creado un título.';output='Regenera el fuente desde la pestaña Código.'}
  }

  $created = $null
  $projectRoot = ''
  $expectedTemplate = if ($backend -eq 'opengl-ui') { 'hui-gl' } else { 'vulkan-template' }
  $slugForTarget = Slug $name
  if ($backend -eq 'opengl-ui') {
    $suffixForTarget = $slugForTarget.ToUpperInvariant() -replace '[^A-Z0-9]',''
    $suffixForTarget = ($suffixForTarget + '0000000000000000').Substring(0,16)
    $targetCandidate = Join-Path $script:Workspace ($suffixForTarget + '-OpenGL-UI')
  } else { $targetCandidate = Join-Path $script:Workspace ($slugForTarget + '-Vulkan') }
  if (Test-Path -LiteralPath $targetCandidate -PathType Container) {
    if (!$Body.overwriteExisting) {
      return @{ok=$false;message='La carpeta de destino ya existe. Cambia el nombre del título o marca «Sobrescribir» para reemplazar únicamente un proyecto de Homebrew Studio de la misma plantilla.';output=[string]$targetCandidate;path=[string]$targetCandidate;exitCode=2}
    }
    $existingMarker = Join-Path $targetCandidate '.ps5hs-project.json'
    if (!(Test-Path -LiteralPath $existingMarker -PathType Leaf)) {
      return @{ok=$false;message='No se puede sobrescribir: la carpeta existente no contiene el manifiesto de Homebrew Studio.';output=[string]$targetCandidate;path=[string]$targetCandidate;exitCode=2}
    }
    try { $existingMeta = Get-Content -LiteralPath $existingMarker -Raw | ConvertFrom-Json } catch {
      return @{ok=$false;message='No se puede sobrescribir: el manifiesto existente no se puede leer.';output=$_.Exception.Message;path=[string]$targetCandidate;exitCode=2}
    }
    if ($existingMeta.schema -ne 'ps5hs-native-project' -or [string]$existingMeta.template -ne $expectedTemplate) {
      return @{ok=$false;message='No se puede sobrescribir: el destino no es un proyecto de Homebrew Studio de la misma plantilla.';output=[string]$targetCandidate;path=[string]$targetCandidate;exitCode=2}
    }
    try { Remove-Item -LiteralPath $targetCandidate -Recurse -Force -ErrorAction Stop } catch {
      return @{ok=$false;message='No se pudo sustituir la carpeta existente; puede estar bloqueada o no tener permisos suficientes.';output=$_.Exception.Message;path=[string]$targetCandidate;exitCode=2}
    }
    WriteBuildJobLog $script:ActiveBuildLogPath ('Se ha autorizado la sustitución del proyecto existente: ' + $targetCandidate)
  }
  try {
    if ($backend -eq 'opengl-ui') {
      $created = NewNativeTitle $name $titleId 'game' 'hui-gl'
    } else {
      # A UI title is required: GeneratedScreen implements the upstream Concept contract.
      $created = NewVulkanTitle $name $titleId 'aurora'
    }
    if (!$created -or !$created.ok) {
      return @{ok=$false;message=[string]$created.message;output=[string]$created.output;path=[string]$created.path;titleId=$titleId;backend=$backend}
    }

    $projectRoot = [IO.Path]::GetFullPath([string]$created.path)
    $workspaceRoot = [IO.Path]::GetFullPath($script:Workspace) + [IO.Path]::DirectorySeparatorChar
    if (!$projectRoot.StartsWith($workspaceRoot,[StringComparison]::OrdinalIgnoreCase)) {
      throw 'El generador produjo una ruta fuera del workspace autorizado.'
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
      $header = Get-Content -LiteralPath $headerPath -Raw
      if ($header -notmatch 'make_ps5hs_generated') {
        $needle = '} // namespace hui::concepts'
        if (!$header.Contains($needle)) { throw 'No se pudo localizar el límite del namespace en concepts.hpp.' }
        $header = $header.Replace($needle,"std::unique_ptr<app::Concept> make_ps5hs_generated(app::Context &context);`r`n`r`n$needle")
        WriteUtf8 $headerPath $header
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
      WriteUtf8 $registryPath $registry
    } else {
      $samplesPath = Join-Path $projectRoot 'ps5/src/samples.cpp'
      if (!(Test-Path $samplesPath -PathType Leaf)) { throw 'El título Vulkan generado no contiene ps5/src/samples.cpp.' }
      $samplesText = Get-Content -LiteralPath $samplesPath -Raw
      $programMatch = [regex]::Match($samplesText,'(?s)#define PS5_SAMPLES\s*\\\s*SAMPLE\(([A-Za-z0-9_]+),')
      if (!$programMatch.Success) { throw 'No se pudo resolver la ruta del programa Vulkan desde src/samples.cpp.' }
      $programId = $programMatch.Groups[1].Value
      $sourcePath = Join-Path $projectRoot ('examples/' + $programId + '/kit/screen.cpp')
      if (!(Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "El generador Vulkan no dejó la pantalla del programa esperado: $sourcePath"
      }
    }

    WriteUtf8 $sourcePath $code
    $assetResult = WriteNativeVisualAssets $Body $projectRoot
    $fontResult = PrepareNativeUnicodeFonts $Body $projectRoot $backend
    if ($backend -eq 'vulkan-ui') {
      $samplesPath = Join-Path $projectRoot 'ps5/src/samples.cpp'
      if (!(Test-Path $samplesPath -PathType Leaf)) { throw 'La plantilla Vulkan no contiene ps5/src/samples.cpp para resolver el programa de texturas.' }
      $samplesText = Get-Content -LiteralPath $samplesPath -Raw
      $programMatch = [regex]::Match($samplesText,'(?s)#define PS5_SAMPLES\s*\\\s*SAMPLE\(([A-Za-z0-9_]+),')
      if (!$programMatch.Success) { throw 'No se pudo resolver el identificador de programa Vulkan para el runtime de texturas.' }
      $programId = $programMatch.Groups[1].Value
      if ($assetResult.count -gt 0) {
        $vulkanAssetResult = RegisterVulkanNativeAssets $Body $projectRoot
        $programId = [string]$vulkanAssetResult.programId
        $assetResult.manifest = [string]$vulkanAssetResult.manifest
      }
      $runtimeResult = InstallVulkanTextureRuntime $Body $projectRoot $programId
      $assetResult.runtimeSource = [string]$runtimeResult.source
    }
    WriteUtf8 (Join-Path $projectRoot 'ps5hs-model.json') (ConvertTo-Json -InputObject $Body.project -Depth 100)
    $markerPath = Join-Path $projectRoot '.ps5hs-project.json'
    $meta = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
    $meta | Add-Member -NotePropertyName visualBackend -NotePropertyValue $backend -Force
    $meta | Add-Member -NotePropertyName generatedFromStudio -NotePropertyValue $true -Force
    $meta | Add-Member -NotePropertyName generatedSource -NotePropertyValue ([string]$sourcePath) -Force
    $meta | Add-Member -NotePropertyName visualModel -NotePropertyValue 'ps5hs-model.json' -Force
    WriteUtf8 $markerPath (ConvertTo-Json -InputObject $meta -Depth 20)

    $presentationBody = @{ path = $projectRoot }
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
    if ($fontResult -and $fontResult.enabled) { $parts += "Fuentes Unicode: $($fontResult.fileName), $($fontResult.glyphCount) glifos; atlas SDF personalizados OpenGL/Vulkan." }
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
    $build = BuildNativeProject $projectRoot
    if ($build.output) { $parts += [string]$build.output }
    $combined = $parts -join "`r`n"
    if ($build.ok) {
      return @{ok=$true;message='La pantalla visual se generó como C++20, se compiló con el pipeline upstream y se encontró un artefacto verificable.';output=$combined;path=$projectRoot;artifact=$build.artifact;titleId=$titleId;backend=$backend;templateId=$meta.template;exitCode=0}
    }
    return @{ok=$false;message='La pantalla C++ se ha generado, pero el pipeline upstream no produjo un artefacto verificable. El proyecto queda guardado para corregirlo y recompilarlo.';output=$combined;path=$projectRoot;titleId=$titleId;backend=$backend;templateId=$meta.template;artifact=$build.artifact;exitCode=$build.exitCode;diagnostics=$build.diagnostics}
  } catch {
    return @{ok=$false;message='No se pudo generar o compilar el proyecto visual nativo.';output=($_.Exception.Message + "`r`n" + [string]$created.output);path=$projectRoot;titleId=$titleId;backend=$backend}
  }
}

function SaveProject($P,[string]$Code) {
  $name=Slug $P.name;$dir=Join-Path $script:Workspace $name;New-Item -ItemType Directory -Force -Path $dir|Out-Null;WriteProjectFiles $P $Code $dir
  if([string]$P.backend -in @('opengl-ui','vulkan-ui')){$sourceName='GeneratedScreen.cpp';$description='C++20 generado contra el contrato hui::app::Concept. Usa Compilar para inyectarlo en la plantilla upstream y construir un título.'}
  else{$sourceName='Program.cs';$description='Código C# generado/actual.'}
  $readme="# $($P.name)`r`n`r`nProyecto PS5 Homebrew Studio. Backend: $($P.backend).`r`n`r`n- project.json: modelo del editor.`r`n- ${sourceName}: $description`r`n- assets/: recursos importados.`r`n"
  WriteUtf8 (Join-Path $dir 'README.md') $readme;return @{ok=$true;path=$dir;name=$name}
}
function ExportProject($P,[string]$Code) {
  $name=Slug $P.name;$id=[guid]::NewGuid().ToString('N').Substring(0,8);$dir=Join-Path $script:Exports ($name+'-'+$id);New-Item -ItemType Directory -Force -Path $dir|Out-Null;WriteProjectFiles $P $Code $dir
  if([string]$P.backend -in @('opengl-ui','vulkan-ui')){$backendNote='GeneratedScreen.cpp implementa la pantalla nativa. El ZIP contiene el modelo y el fuente generado, no un eboot.bin compilado; pulsa Compilar para usar el generador y pipeline upstream.'}
  else{$backendNote='El código fuente generado se encuentra en Program.cs.'}
  WriteUtf8 (Join-Path $dir 'README.md') ("# $($P.name)`r`n`r`nProyecto exportado desde PS5 Homebrew Studio.`r`nBackend: $($P.backend).`r`n$backendNote`r`nEl modelo editable está en project.json; los recursos importados están en assets/. Consulta las licencias y dependencias de cada SDK en su repositorio original. No se incluyen binarios propietarios de Sony.`r`n")
  $file=$name+'-'+$id+'.zip';$path=Join-Path $script:Exports $file;Compress-Archive -Path (Join-Path $dir '*') -DestinationPath $path -CompressionLevel Optimal -Force;return @{ok=$true;url='/downloads/'+$file;fileName=$file;path=$path}
}
function BuildSharp($P,[string]$Code,[string]$Backend,[string]$RequestedOutput='Package') {
  if($Backend -eq 'sharp-payload'){return @{ok=$false;message='El formato Payload de SharpProspero es un ELF ejecutable dentro de un proceso ya cargado, no una app con pantalla propia. Este proyecto contiene componentes de interfaz y no se transformará incorrectamente en payload.';output='Crea un proyecto de payload específico o cambia el destino a SharpProspero · Aplicación.';diagnostics=@(@{severity='error';title='Tipo de producto incompatible';message='La interfaz visual necesita un módulo de aplicación nativa.';location='Backend'})}}
  $sdk=Join-Path $script:Toolchains 'SharpProspero';if(!(Test-Path (Join-Path $sdk 'build/build-app.ps1'))){return @{ok=$false;message='SharpProspero no está instalado. Descarga el repositorio desde el panel SDKs.';output='';diagnostics=@(@{severity='error';title='SDK ausente';message='Descarga SharpProspero desde GitHub.';location='Backend'})}}
  $st=GetStatus;if(!$st.prerequisites.dotnet10){return @{ok=$false;message='.NET SDK 10 no está disponible en Windows.';output='Instala .NET SDK 10 con Configurar entorno.';diagnostics=@(@{severity='error';title='.NET 10 ausente';message='El toolchain SharpProspero requiere .NET 10.';location='Entorno'})}}
  if(!$st.prerequisites.wsl){return @{ok=$false;message='WSL no tiene una distribución inicializada.';output='Configurar entorno → Instalar WSL + Debian. Termina el primer inicio de la distribución y vuelve a comprobar.';diagnostics=@(@{severity='error';title='WSL ausente';message='En Windows SharpProspero usa WSL para compilar NativeAOT.';location='Entorno'})}}
  if(!$st.prerequisites.wslDotnet10){return @{ok=$false;message='.NET SDK 10 no está instalado dentro de WSL.';output='Dentro de la distribución Linux, instala .NET SDK 10 siguiendo docs/setup.md de SharpProspero.';diagnostics=@(@{severity='error';title='.NET en WSL ausente';message='NativeAOT necesita el SDK .NET dentro de Linux.';location='Entorno'})}}
  $slug=Slug $P.name;$home=Join-Path $script:Workspace $slug;New-Item -ItemType Directory -Force -Path $home|Out-Null;$native=Join-Path $home 'native'
  if(!(Test-Path (Join-Path $native 'SampleApp.csproj'))){New-Item -ItemType Directory -Force -Path $native|Out-Null;Copy-Item -Path (Join-Path $sdk 'samples/prospero-ui/*') -Destination $native -Recurse -Force}
  WriteProjectFiles $P $Code $native
  $csproj=Join-Path $native 'SampleApp.csproj';if(!(Test-Path $csproj)){return @{ok=$false;message='La distribución descargada de SharpProspero no contiene la plantilla prospectada samples/prospero-ui/SampleApp.csproj.';output=$sdk}}
  $raw=Get-Content -LiteralPath $csproj -Raw;$raw=$raw.Replace('<AssemblyName>SampleApp</AssemblyName>',('<AssemblyName>'+$slug+'</AssemblyName>'))
  if(-not $raw.Contains('assets\**\*')){ $addition = "  <ItemGroup>`r`n    <None Update=`"assets\**\*`" CopyToOutputDirectory=`"PreserveNewest`" />`r`n  </ItemGroup>`r`n</Project>"; $raw=$raw.Replace('</Project>',$addition) }
  WriteUtf8 $csproj $raw
  $metaPath=Join-Path $native 'sce_sys/param.json';if(Test-Path $metaPath){$meta=Get-Content $metaPath -Raw|ConvertFrom-Json;$tid=[string]$P.settings.titleId;if($tid -notmatch '^[A-Z]{4}[0-9]{5}$'){$tid='PPSA'+(Get-Random -Minimum 10000 -Maximum 99999)};$meta.titleId=$tid;$meta.contentId=('UP9000-'+$tid+'_00-0000000000000001');$meta.conceptId=$tid.Substring(4);if($meta.localizedParameters.'en-US'){$meta.localizedParameters.'en-US'.titleName=[string]$P.name};WriteUtf8 $metaPath (ConvertTo-Json -InputObject $meta -Depth 50)}
  $outputDir=Join-Path $native 'out';if(Test-Path $outputDir){Remove-Item $outputDir -Recurse -Force};New-Item -ItemType Directory -Force -Path $outputDir|Out-Null;if($RequestedOutput -notin @('Package','Folder')){$RequestedOutput='Package'};$buildArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $sdk 'build/build-app.ps1'),'-ProjectPath',$csproj,'-SdkRoot',$sdk,'-Output',$RequestedOutput,'-OutputFolder',$outputDir)
  $out=& powershell.exe @buildArgs 2>&1|ForEach-Object{$_.ToString()};$exit=$LASTEXITCODE;$log=$out -join "`r`n";$art=$null;if(Test-Path $outputDir){$cand=Get-ChildItem $outputDir -Recurse -File -Include '*.pkg','*.elf','eboot.bin'|Sort-Object LastWriteTime -Descending|Select-Object -First 1;if($cand){$art=$cand.FullName}}
  if($exit -eq 0 -and $art){return @{ok=$true;message='El proceso de compilación terminó correctamente.';output=$log;artifact=$art;diagnostics=@()}}
  return @{ok=$false;message='La compilación no ha producido un artefacto final verificable.';output=$log;artifact=$art;diagnostics=@(@{severity='error';title='Compilación fallida';message='Revisa la salida real del SDK/compilador mostrada en el panel Salida.';location='Pipeline de compilación'})}
}
function InvokeSetup([string]$Action) {
  if($Action -eq 'diagnose'){return @{ok=$true;message='Diagnóstico completado.';output=(ConvertTo-Json (GetStatus) -Depth 10)}}
  $messages=@();$ok=$true
  if($Action -in @('git','all')){if(!(Get-Command winget.exe -ErrorAction SilentlyContinue)){$messages+='winget no está disponible. Instala Git for Windows manualmente desde git-scm.com.';$ok=$false}else{$o=& winget install --id Git.Git --exact --accept-package-agreements --accept-source-agreements 2>&1;$ec=$LASTEXITCODE;$messages+=($o|ForEach-Object{$_.ToString()});if($ec -ne 0){$ok=$false}}}
  if($Action -in @('dotnet','all')){if(!(Get-Command winget.exe -ErrorAction SilentlyContinue)){$messages+='winget no está disponible. Instala App Installer desde Microsoft Store.';$ok=$false}else{$o=& winget install --id Microsoft.DotNet.SDK.10 --exact --accept-package-agreements --accept-source-agreements 2>&1;$ec=$LASTEXITCODE;$messages+=($o|ForEach-Object{$_.ToString()});if($ec -ne 0){$ok=$false}}}
  if($Action -in @('wsl','all')){if(!(Get-Command wsl.exe -ErrorAction SilentlyContinue)){$messages+='wsl.exe no está disponible en esta versión/instalación de Windows.';$ok=$false}else{$o=& wsl.exe --install -d Debian 2>&1;$ec=$LASTEXITCODE;$messages+=($o|ForEach-Object{$_.ToString()});if($ec -ne 0){$ok=$false}}}
  return @{ok=$ok;message=$(if($ok){'Acción de configuración terminada; vuelve a comprobar el entorno.'}else{'La configuración necesita intervención. Consulta la salida.'});output=($messages -join "`r`n")}
}
function ServeStatic($C,[string]$UrlPath) {
  $relative=[Uri]::UnescapeDataString($UrlPath.TrimStart('/'));if(!$relative){$relative='index.html'}
  if($relative.StartsWith('downloads/')){$file=[IO.Path]::GetFileName($relative.Substring(10));$p=Join-Path $script:Exports $file;if(!(Test-Path $p)){SendJson $C @{error='ZIP no encontrado'} 404;return};SendBytes $C ([IO.File]::ReadAllBytes($p)) 'application/zip';return}
  $relative=$relative.Replace('\','/').TrimStart('/')
  $allowed=@('index.html','styles.css','app.js','runtime/native-generator.js','docs/SDK_MATRIX.md','docs/PROJECT_ECOSYSTEM.md')
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
    WriteBuildJobLog $script:ActiveBuildLogPath 'Trabajador de compilación iniciado.'
    $requestPath = Join-Path $jobDir 'request.json'
    $jobRequest = Get-Content -LiteralPath $requestPath -Raw | ConvertFrom-Json
    if ([string]$jobRequest.action -eq 'native') { $result = BuildNativeProject ([string]$jobRequest.body.path) ([bool]$jobRequest.body.cleanBeforeBuild) ([string]$jobRequest.body.titleId) ([string]$jobRequest.body.name) }
    elseif ([string]$jobRequest.action -eq 'package') { $result = PackageNativeProjectWithUltraPack $jobRequest.body }
    else { $result = BuildNativeVisualProject $jobRequest.body }
    if ($result.ok) { WriteBuildJobLog $script:ActiveBuildLogPath ('COMPLETADO: ' + [string]$result.message) }
    else { WriteBuildJobLog $script:ActiveBuildLogPath ('ERROR: ' + [string]$result.message) }
    if ($result.output) { WriteBuildJobLog $script:ActiveBuildLogPath ([string]$result.output) }
    WriteUtf8 (Join-Path $jobDir 'result.json') (ConvertTo-Json -InputObject $result -Depth 100)
    exit 0
  } catch {
    $failed = @{ok=$false;message='El trabajador de compilación ha fallado.';output=$_.Exception.Message;exitCode=1}
    try {
      WriteBuildJobLog (Join-Path (GetBuildJobDirectory $jobId) 'build.log') ('ERROR FATAL: ' + $_.Exception.Message)
      WriteUtf8 (Join-Path (GetBuildJobDirectory $jobId) 'result.json') (ConvertTo-Json -InputObject $failed -Depth 20)
    } catch { }
    exit 1
  }
}

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse('127.0.0.1'),47813)
try { $listener.Start() } catch { Write-Host "No se pudo iniciar el servicio en $script:Url. Cierra otra instancia. $($_.Exception.Message)" -ForegroundColor Red; Read-Host 'Pulsa Intro'; exit 2 }
Write-Host 'PS5 Homebrew Studio' -ForegroundColor Cyan
Write-Host "Servicio local: $script:Url"
Write-Host 'Solo loopback. Cierra esta ventana para detenerlo.' -ForegroundColor DarkGray
Start-Process $script:Url
while ($listener.Server.IsBound) {
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
                                        SendJson $ctx @{ project = (Get-Content $projectPath -Raw | ConvertFrom-Json) }
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
                                        $result = NewVulkanTitle ([string]$body.name) ([string]$body.titleId) ([string]$body.design)
                                    }
                                    elseif($templateId -in @('nativecpp','hui-gl')) {
                                        $category=[string]$body.category;if(!$category){$category='game'}
                                        $result = NewNativeTitle ([string]$body.name) ([string]$body.titleId) $category $templateId
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
                                    $result = BuildNativeProject ([string]$body.path)
                                    SendJson $ctx $result
                                }
                                '/api/build-native/start' {
                                    SendJson $ctx (StartNativeBuildJob $body 'native')
                                }
                                '/api/build-visual-native/start' {
                                    SendJson $ctx (StartNativeBuildJob $body 'visual')
                                }
                                '/api/build-visual-native' {
                                    $result = BuildNativeVisualProject $body
                                    SendJson $ctx $result
                                }
                                '/api/build' {
                                    $backend = [string]$body.backend
                                    if ($backend -in @('sharp', 'sharp-payload')) {
                                        $result = BuildSharp $body.project ([string]$body.programCode) $backend ([string]$body.output)
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
$listener.Stop()
) { throw 'La fuente personalizada debe ser TrueType (.ttf). OTF/CFF no es compatible con el horneador incluido.' }
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
  $builtIn = 'Listo cruceta para navegar X para activar Teclado de pantalla Escribe con la cruceta y confirma las teclas Espacio Borrar Limpiar Aceptar Cancelar Confirmar seleccionar Atrás para guardar Edición cancelada valor actualizado Opción · ¿¡áéíóúÁÉÍÓÚñÑüÜ€…'
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
  $lines = @($points | ForEach-Object { $_.ToString('X') })
  WriteUtf8 $codepointPath (($lines -join [Environment]::NewLine) + [Environment]::NewLine)

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
    if ($setupExit -ne 0) { throw ('No se pudo exportar el horneador de fuentes del kit Vulkan: ' + (($setupOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)) }
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
  $kitRootWsl = ConvertToWslPath $kitRoot
  $fontWsl = ConvertToWslPath $kitFont
  $codepointsWsl = ConvertToWslPath $kitCodepoints
  $outputFontsWsl = ConvertToWslPath (Join-Path $kitRoot 'assets/fonts')
  $buildCommand = 'cd ' + (BashQuote $kitRootWsl) + ' || exit 1; mkdir -p build/host assets/fonts; cxx=clang++; command -v "$cxx" >/dev/null 2>&1 || cxx=c++; command -v "$cxx" >/dev/null 2>&1 || exit 127; "$cxx" -std=c++20 -O2 -w tools/font-baker/bake_font.cpp -o build/host/ps5hs-bake-font || exit $?; for face in inter-regular inter-semibold montserrat-medium dejavu-sans-mono press-start-2p patrick-hand; do build/host/ps5hs-bake-font ' + (BashQuote $fontWsl) + ' ' + (BashQuote $outputFontsWsl) + '/"$face".huifont 56 8 4096 custom ' + (BashQuote $codepointsWsl) + ' || exit $?; done'
  $wsl = CmdInfo 'wsl.exe'
  if (!$wsl.ok) { throw 'wsl.exe no está disponible para compilar el atlas Unicode.' }
  $output = @(& $wsl.path -d $distribution --exec bash -lc $buildCommand 2>&1)
  $exit = $LASTEXITCODE
  $log = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
  if ($exit -ne 0) { throw ('Falló el horneado de la fuente Unicode. Comprueba que la TTF contiene los glifos requeridos. ' + $log) }

  $notice = @"
Fuente TTF personalizada: $fileName
Glifos Unicode solicitados: $($points.Count)
Backend: $Backend

El archivo TTF y la lista de codepoints se conservan en .ps5hs-font-source/ para reconstrucción local. El IDE no concede derechos sobre la fuente; verifica su licencia antes de distribuir el título.
"@
  WriteUtf8 (Join-Path $ProjectRoot 'PS5HS-UNICODE-FONTS.txt') $notice
  WriteBuildJobLog $script:ActiveBuildLogPath ("Fuente Unicode personalizada horneada: " + $fileName + "; " + $points.Count + " codepoints; seis atlas SDF generados.")
  return @{enabled=$true;glyphCount=$points.Count;fileName=$fileName;notice='PS5HS-UNICODE-FONTS.txt'}
}

function BuildNativeVisualProject($Body) {
  WriteBuildJobLog $script:ActiveBuildLogPath 'Validando el modelo visual, el backend y los metadatos del título…'
  $backend = [string]$Body.backend
  if ($backend -notin @('opengl-ui','vulkan-ui')) {
    return @{ok=$false;message='Backend nativo visual desconocido.';output=$backend}
  }
  $name = [string]$Body.project.name
  $titleId = ([string]$Body.titleId).Trim().ToUpperInvariant()
  $code = [string]$Body.programCode
  if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._-]{0,39}$') {
    return @{ok=$false;message='Nombre inválido. Usa entre 1 y 40 caracteres ASCII.';output=$name}
  }
  if ($titleId -notmatch '^PPSA\d{5}$') {
    return @{ok=$false;message='TITLE_ID inválido. Usa PPSA seguido de cinco dígitos.';output=$titleId}
  }
  $requiredFactory = if ($backend -eq 'vulkan-ui') { 'make_screen' } else { 'make_ps5hs_generated' }
  if ($code.Length -lt 2000 -or !$code.Contains($requiredFactory) -or !$code.Contains('GeneratedScreen')) {
    return @{ok=$false;message='El código no corresponde al generador C++20 del backend seleccionado. No se ha creado un título.';output='Regenera el fuente desde la pestaña Código.'}
  }

  $created = $null
  $projectRoot = ''
  $expectedTemplate = if ($backend -eq 'opengl-ui') { 'hui-gl' } else { 'vulkan-template' }
  $slugForTarget = Slug $name
  if ($backend -eq 'opengl-ui') {
    $suffixForTarget = $slugForTarget.ToUpperInvariant() -replace '[^A-Z0-9]',''
    $suffixForTarget = ($suffixForTarget + '0000000000000000').Substring(0,16)
    $targetCandidate = Join-Path $script:Workspace ($suffixForTarget + '-OpenGL-UI')
  } else { $targetCandidate = Join-Path $script:Workspace ($slugForTarget + '-Vulkan') }
  if (Test-Path -LiteralPath $targetCandidate -PathType Container) {
    if (!$Body.overwriteExisting) {
      return @{ok=$false;message='La carpeta de destino ya existe. Cambia el nombre del título o marca «Sobrescribir» para reemplazar únicamente un proyecto de Homebrew Studio de la misma plantilla.';output=[string]$targetCandidate;path=[string]$targetCandidate;exitCode=2}
    }
    $existingMarker = Join-Path $targetCandidate '.ps5hs-project.json'
    if (!(Test-Path -LiteralPath $existingMarker -PathType Leaf)) {
      return @{ok=$false;message='No se puede sobrescribir: la carpeta existente no contiene el manifiesto de Homebrew Studio.';output=[string]$targetCandidate;path=[string]$targetCandidate;exitCode=2}
    }
    try { $existingMeta = Get-Content -LiteralPath $existingMarker -Raw | ConvertFrom-Json } catch {
      return @{ok=$false;message='No se puede sobrescribir: el manifiesto existente no se puede leer.';output=$_.Exception.Message;path=[string]$targetCandidate;exitCode=2}
    }
    if ($existingMeta.schema -ne 'ps5hs-native-project' -or [string]$existingMeta.template -ne $expectedTemplate) {
      return @{ok=$false;message='No se puede sobrescribir: el destino no es un proyecto de Homebrew Studio de la misma plantilla.';output=[string]$targetCandidate;path=[string]$targetCandidate;exitCode=2}
    }
    try { Remove-Item -LiteralPath $targetCandidate -Recurse -Force -ErrorAction Stop } catch {
      return @{ok=$false;message='No se pudo sustituir la carpeta existente; puede estar bloqueada o no tener permisos suficientes.';output=$_.Exception.Message;path=[string]$targetCandidate;exitCode=2}
    }
    WriteBuildJobLog $script:ActiveBuildLogPath ('Se ha autorizado la sustitución del proyecto existente: ' + $targetCandidate)
  }
  try {
    if ($backend -eq 'opengl-ui') {
      $created = NewNativeTitle $name $titleId 'game' 'hui-gl'
    } else {
      # A UI title is required: GeneratedScreen implements the upstream Concept contract.
      $created = NewVulkanTitle $name $titleId 'aurora'
    }
    if (!$created -or !$created.ok) {
      return @{ok=$false;message=[string]$created.message;output=[string]$created.output;path=[string]$created.path;titleId=$titleId;backend=$backend}
    }

    $projectRoot = [IO.Path]::GetFullPath([string]$created.path)
    $workspaceRoot = [IO.Path]::GetFullPath($script:Workspace) + [IO.Path]::DirectorySeparatorChar
    if (!$projectRoot.StartsWith($workspaceRoot,[StringComparison]::OrdinalIgnoreCase)) {
      throw 'El generador produjo una ruta fuera del workspace autorizado.'
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
      $header = Get-Content -LiteralPath $headerPath -Raw
      if ($header -notmatch 'make_ps5hs_generated') {
        $needle = '} // namespace hui::concepts'
        if (!$header.Contains($needle)) { throw 'No se pudo localizar el límite del namespace en concepts.hpp.' }
        $header = $header.Replace($needle,"std::unique_ptr<app::Concept> make_ps5hs_generated(app::Context &context);`r`n`r`n$needle")
        WriteUtf8 $headerPath $header
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
      WriteUtf8 $registryPath $registry
    } else {
      $samplesPath = Join-Path $projectRoot 'ps5/src/samples.cpp'
      if (!(Test-Path $samplesPath -PathType Leaf)) { throw 'El título Vulkan generado no contiene ps5/src/samples.cpp.' }
      $samplesText = Get-Content -LiteralPath $samplesPath -Raw
      $programMatch = [regex]::Match($samplesText,'(?s)#define PS5_SAMPLES\s*\\\s*SAMPLE\(([A-Za-z0-9_]+),')
      if (!$programMatch.Success) { throw 'No se pudo resolver la ruta del programa Vulkan desde src/samples.cpp.' }
      $programId = $programMatch.Groups[1].Value
      $sourcePath = Join-Path $projectRoot ('examples/' + $programId + '/kit/screen.cpp')
      if (!(Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "El generador Vulkan no dejó la pantalla del programa esperado: $sourcePath"
      }
    }

    WriteUtf8 $sourcePath $code
    $assetResult = WriteNativeVisualAssets $Body $projectRoot
    if ($backend -eq 'vulkan-ui') {
      $samplesPath = Join-Path $projectRoot 'ps5/src/samples.cpp'
      if (!(Test-Path $samplesPath -PathType Leaf)) { throw 'La plantilla Vulkan no contiene ps5/src/samples.cpp para resolver el programa de texturas.' }
      $samplesText = Get-Content -LiteralPath $samplesPath -Raw
      $programMatch = [regex]::Match($samplesText,'(?s)#define PS5_SAMPLES\s*\\\s*SAMPLE\(([A-Za-z0-9_]+),')
      if (!$programMatch.Success) { throw 'No se pudo resolver el identificador de programa Vulkan para el runtime de texturas.' }
      $programId = $programMatch.Groups[1].Value
      if ($assetResult.count -gt 0) {
        $vulkanAssetResult = RegisterVulkanNativeAssets $Body $projectRoot
        $programId = [string]$vulkanAssetResult.programId
        $assetResult.manifest = [string]$vulkanAssetResult.manifest
      }
      $runtimeResult = InstallVulkanTextureRuntime $Body $projectRoot $programId
      $assetResult.runtimeSource = [string]$runtimeResult.source
    }
    WriteUtf8 (Join-Path $projectRoot 'ps5hs-model.json') (ConvertTo-Json -InputObject $Body.project -Depth 100)
    $markerPath = Join-Path $projectRoot '.ps5hs-project.json'
    $meta = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
    $meta | Add-Member -NotePropertyName visualBackend -NotePropertyValue $backend -Force
    $meta | Add-Member -NotePropertyName generatedFromStudio -NotePropertyValue $true -Force
    $meta | Add-Member -NotePropertyName generatedSource -NotePropertyValue ([string]$sourcePath) -Force
    $meta | Add-Member -NotePropertyName visualModel -NotePropertyValue 'ps5hs-model.json' -Force
    WriteUtf8 $markerPath (ConvertTo-Json -InputObject $meta -Depth 20)

    $presentationBody = @{ path = $projectRoot }
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
    $build = BuildNativeProject $projectRoot
    if ($build.output) { $parts += [string]$build.output }
    $combined = $parts -join "`r`n"
    if ($build.ok) {
      return @{ok=$true;message='La pantalla visual se generó como C++20, se compiló con el pipeline upstream y se encontró un artefacto verificable.';output=$combined;path=$projectRoot;artifact=$build.artifact;titleId=$titleId;backend=$backend;templateId=$meta.template;exitCode=0}
    }
    return @{ok=$false;message='La pantalla C++ se ha generado, pero el pipeline upstream no produjo un artefacto verificable. El proyecto queda guardado para corregirlo y recompilarlo.';output=$combined;path=$projectRoot;titleId=$titleId;backend=$backend;templateId=$meta.template;artifact=$build.artifact;exitCode=$build.exitCode;diagnostics=$build.diagnostics}
  } catch {
    return @{ok=$false;message='No se pudo generar o compilar el proyecto visual nativo.';output=($_.Exception.Message + "`r`n" + [string]$created.output);path=$projectRoot;titleId=$titleId;backend=$backend}
  }
}

function SaveProject($P,[string]$Code) {
  $name=Slug $P.name;$dir=Join-Path $script:Workspace $name;New-Item -ItemType Directory -Force -Path $dir|Out-Null;WriteProjectFiles $P $Code $dir
  if([string]$P.backend -in @('opengl-ui','vulkan-ui')){$sourceName='GeneratedScreen.cpp';$description='C++20 generado contra el contrato hui::app::Concept. Usa Compilar para inyectarlo en la plantilla upstream y construir un título.'}
  else{$sourceName='Program.cs';$description='Código C# generado/actual.'}
  $readme="# $($P.name)`r`n`r`nProyecto PS5 Homebrew Studio. Backend: $($P.backend).`r`n`r`n- project.json: modelo del editor.`r`n- ${sourceName}: $description`r`n- assets/: recursos importados.`r`n"
  WriteUtf8 (Join-Path $dir 'README.md') $readme;return @{ok=$true;path=$dir;name=$name}
}
function ExportProject($P,[string]$Code) {
  $name=Slug $P.name;$id=[guid]::NewGuid().ToString('N').Substring(0,8);$dir=Join-Path $script:Exports ($name+'-'+$id);New-Item -ItemType Directory -Force -Path $dir|Out-Null;WriteProjectFiles $P $Code $dir
  if([string]$P.backend -in @('opengl-ui','vulkan-ui')){$backendNote='GeneratedScreen.cpp implementa la pantalla nativa. El ZIP contiene el modelo y el fuente generado, no un eboot.bin compilado; pulsa Compilar para usar el generador y pipeline upstream.'}
  else{$backendNote='El código fuente generado se encuentra en Program.cs.'}
  WriteUtf8 (Join-Path $dir 'README.md') ("# $($P.name)`r`n`r`nProyecto exportado desde PS5 Homebrew Studio.`r`nBackend: $($P.backend).`r`n$backendNote`r`nEl modelo editable está en project.json; los recursos importados están en assets/. Consulta las licencias y dependencias de cada SDK en su repositorio original. No se incluyen binarios propietarios de Sony.`r`n")
  $file=$name+'-'+$id+'.zip';$path=Join-Path $script:Exports $file;Compress-Archive -Path (Join-Path $dir '*') -DestinationPath $path -CompressionLevel Optimal -Force;return @{ok=$true;url='/downloads/'+$file;fileName=$file;path=$path}
}
function BuildSharp($P,[string]$Code,[string]$Backend,[string]$RequestedOutput='Package') {
  if($Backend -eq 'sharp-payload'){return @{ok=$false;message='El formato Payload de SharpProspero es un ELF ejecutable dentro de un proceso ya cargado, no una app con pantalla propia. Este proyecto contiene componentes de interfaz y no se transformará incorrectamente en payload.';output='Crea un proyecto de payload específico o cambia el destino a SharpProspero · Aplicación.';diagnostics=@(@{severity='error';title='Tipo de producto incompatible';message='La interfaz visual necesita un módulo de aplicación nativa.';location='Backend'})}}
  $sdk=Join-Path $script:Toolchains 'SharpProspero';if(!(Test-Path (Join-Path $sdk 'build/build-app.ps1'))){return @{ok=$false;message='SharpProspero no está instalado. Descarga el repositorio desde el panel SDKs.';output='';diagnostics=@(@{severity='error';title='SDK ausente';message='Descarga SharpProspero desde GitHub.';location='Backend'})}}
  $st=GetStatus;if(!$st.prerequisites.dotnet10){return @{ok=$false;message='.NET SDK 10 no está disponible en Windows.';output='Instala .NET SDK 10 con Configurar entorno.';diagnostics=@(@{severity='error';title='.NET 10 ausente';message='El toolchain SharpProspero requiere .NET 10.';location='Entorno'})}}
  if(!$st.prerequisites.wsl){return @{ok=$false;message='WSL no tiene una distribución inicializada.';output='Configurar entorno → Instalar WSL + Debian. Termina el primer inicio de la distribución y vuelve a comprobar.';diagnostics=@(@{severity='error';title='WSL ausente';message='En Windows SharpProspero usa WSL para compilar NativeAOT.';location='Entorno'})}}
  if(!$st.prerequisites.wslDotnet10){return @{ok=$false;message='.NET SDK 10 no está instalado dentro de WSL.';output='Dentro de la distribución Linux, instala .NET SDK 10 siguiendo docs/setup.md de SharpProspero.';diagnostics=@(@{severity='error';title='.NET en WSL ausente';message='NativeAOT necesita el SDK .NET dentro de Linux.';location='Entorno'})}}
  $slug=Slug $P.name;$home=Join-Path $script:Workspace $slug;New-Item -ItemType Directory -Force -Path $home|Out-Null;$native=Join-Path $home 'native'
  if(!(Test-Path (Join-Path $native 'SampleApp.csproj'))){New-Item -ItemType Directory -Force -Path $native|Out-Null;Copy-Item -Path (Join-Path $sdk 'samples/prospero-ui/*') -Destination $native -Recurse -Force}
  WriteProjectFiles $P $Code $native
  $csproj=Join-Path $native 'SampleApp.csproj';if(!(Test-Path $csproj)){return @{ok=$false;message='La distribución descargada de SharpProspero no contiene la plantilla prospectada samples/prospero-ui/SampleApp.csproj.';output=$sdk}}
  $raw=Get-Content -LiteralPath $csproj -Raw;$raw=$raw.Replace('<AssemblyName>SampleApp</AssemblyName>',('<AssemblyName>'+$slug+'</AssemblyName>'))
  if(-not $raw.Contains('assets\**\*')){ $addition = "  <ItemGroup>`r`n    <None Update=`"assets\**\*`" CopyToOutputDirectory=`"PreserveNewest`" />`r`n  </ItemGroup>`r`n</Project>"; $raw=$raw.Replace('</Project>',$addition) }
  WriteUtf8 $csproj $raw
  $metaPath=Join-Path $native 'sce_sys/param.json';if(Test-Path $metaPath){$meta=Get-Content $metaPath -Raw|ConvertFrom-Json;$tid=[string]$P.settings.titleId;if($tid -notmatch '^[A-Z]{4}[0-9]{5}$'){$tid='PPSA'+(Get-Random -Minimum 10000 -Maximum 99999)};$meta.titleId=$tid;$meta.contentId=('UP9000-'+$tid+'_00-0000000000000001');$meta.conceptId=$tid.Substring(4);if($meta.localizedParameters.'en-US'){$meta.localizedParameters.'en-US'.titleName=[string]$P.name};WriteUtf8 $metaPath (ConvertTo-Json -InputObject $meta -Depth 50)}
  $outputDir=Join-Path $native 'out';if(Test-Path $outputDir){Remove-Item $outputDir -Recurse -Force};New-Item -ItemType Directory -Force -Path $outputDir|Out-Null;if($RequestedOutput -notin @('Package','Folder')){$RequestedOutput='Package'};$buildArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $sdk 'build/build-app.ps1'),'-ProjectPath',$csproj,'-SdkRoot',$sdk,'-Output',$RequestedOutput,'-OutputFolder',$outputDir)
  $out=& powershell.exe @buildArgs 2>&1|ForEach-Object{$_.ToString()};$exit=$LASTEXITCODE;$log=$out -join "`r`n";$art=$null;if(Test-Path $outputDir){$cand=Get-ChildItem $outputDir -Recurse -File -Include '*.pkg','*.elf','eboot.bin'|Sort-Object LastWriteTime -Descending|Select-Object -First 1;if($cand){$art=$cand.FullName}}
  if($exit -eq 0 -and $art){return @{ok=$true;message='El proceso de compilación terminó correctamente.';output=$log;artifact=$art;diagnostics=@()}}
  return @{ok=$false;message='La compilación no ha producido un artefacto final verificable.';output=$log;artifact=$art;diagnostics=@(@{severity='error';title='Compilación fallida';message='Revisa la salida real del SDK/compilador mostrada en el panel Salida.';location='Pipeline de compilación'})}
}
function InvokeSetup([string]$Action) {
  if($Action -eq 'diagnose'){return @{ok=$true;message='Diagnóstico completado.';output=(ConvertTo-Json (GetStatus) -Depth 10)}}
  $messages=@();$ok=$true
  if($Action -in @('git','all')){if(!(Get-Command winget.exe -ErrorAction SilentlyContinue)){$messages+='winget no está disponible. Instala Git for Windows manualmente desde git-scm.com.';$ok=$false}else{$o=& winget install --id Git.Git --exact --accept-package-agreements --accept-source-agreements 2>&1;$ec=$LASTEXITCODE;$messages+=($o|ForEach-Object{$_.ToString()});if($ec -ne 0){$ok=$false}}}
  if($Action -in @('dotnet','all')){if(!(Get-Command winget.exe -ErrorAction SilentlyContinue)){$messages+='winget no está disponible. Instala App Installer desde Microsoft Store.';$ok=$false}else{$o=& winget install --id Microsoft.DotNet.SDK.10 --exact --accept-package-agreements --accept-source-agreements 2>&1;$ec=$LASTEXITCODE;$messages+=($o|ForEach-Object{$_.ToString()});if($ec -ne 0){$ok=$false}}}
  if($Action -in @('wsl','all')){if(!(Get-Command wsl.exe -ErrorAction SilentlyContinue)){$messages+='wsl.exe no está disponible en esta versión/instalación de Windows.';$ok=$false}else{$o=& wsl.exe --install -d Debian 2>&1;$ec=$LASTEXITCODE;$messages+=($o|ForEach-Object{$_.ToString()});if($ec -ne 0){$ok=$false}}}
  return @{ok=$ok;message=$(if($ok){'Acción de configuración terminada; vuelve a comprobar el entorno.'}else{'La configuración necesita intervención. Consulta la salida.'});output=($messages -join "`r`n")}
}
function ServeStatic($C,[string]$UrlPath) {
  $relative=[Uri]::UnescapeDataString($UrlPath.TrimStart('/'));if(!$relative){$relative='index.html'}
  if($relative.StartsWith('downloads/')){$file=[IO.Path]::GetFileName($relative.Substring(10));$p=Join-Path $script:Exports $file;if(!(Test-Path $p)){SendJson $C @{error='ZIP no encontrado'} 404;return};SendBytes $C ([IO.File]::ReadAllBytes($p)) 'application/zip';return}
  $relative=$relative.Replace('\','/').TrimStart('/')
  $allowed=@('index.html','styles.css','app.js','runtime/native-generator.js','docs/SDK_MATRIX.md','docs/PROJECT_ECOSYSTEM.md')
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
    WriteBuildJobLog $script:ActiveBuildLogPath 'Trabajador de compilación iniciado.'
    $requestPath = Join-Path $jobDir 'request.json'
    $jobRequest = Get-Content -LiteralPath $requestPath -Raw | ConvertFrom-Json
    if ([string]$jobRequest.action -eq 'native') { $result = BuildNativeProject ([string]$jobRequest.body.path) ([bool]$jobRequest.body.cleanBeforeBuild) ([string]$jobRequest.body.titleId) ([string]$jobRequest.body.name) }
    elseif ([string]$jobRequest.action -eq 'package') { $result = PackageNativeProjectWithUltraPack $jobRequest.body }
    else { $result = BuildNativeVisualProject $jobRequest.body }
    if ($result.ok) { WriteBuildJobLog $script:ActiveBuildLogPath ('COMPLETADO: ' + [string]$result.message) }
    else { WriteBuildJobLog $script:ActiveBuildLogPath ('ERROR: ' + [string]$result.message) }
    if ($result.output) { WriteBuildJobLog $script:ActiveBuildLogPath ([string]$result.output) }
    WriteUtf8 (Join-Path $jobDir 'result.json') (ConvertTo-Json -InputObject $result -Depth 100)
    exit 0
  } catch {
    $failed = @{ok=$false;message='El trabajador de compilación ha fallado.';output=$_.Exception.Message;exitCode=1}
    try {
      WriteBuildJobLog (Join-Path (GetBuildJobDirectory $jobId) 'build.log') ('ERROR FATAL: ' + $_.Exception.Message)
      WriteUtf8 (Join-Path (GetBuildJobDirectory $jobId) 'result.json') (ConvertTo-Json -InputObject $failed -Depth 20)
    } catch { }
    exit 1
  }
}

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse('127.0.0.1'),47813)
try { $listener.Start() } catch { Write-Host "No se pudo iniciar el servicio en $script:Url. Cierra otra instancia. $($_.Exception.Message)" -ForegroundColor Red; Read-Host 'Pulsa Intro'; exit 2 }
Write-Host 'PS5 Homebrew Studio' -ForegroundColor Cyan
Write-Host "Servicio local: $script:Url"
Write-Host 'Solo loopback. Cierra esta ventana para detenerlo.' -ForegroundColor DarkGray
Start-Process $script:Url
while ($listener.Server.IsBound) {
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
                                        SendJson $ctx @{ project = (Get-Content $projectPath -Raw | ConvertFrom-Json) }
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
                                        $result = NewVulkanTitle ([string]$body.name) ([string]$body.titleId) ([string]$body.design)
                                    }
                                    elseif($templateId -in @('nativecpp','hui-gl')) {
                                        $category=[string]$body.category;if(!$category){$category='game'}
                                        $result = NewNativeTitle ([string]$body.name) ([string]$body.titleId) $category $templateId
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
                                    $result = BuildNativeProject ([string]$body.path)
                                    SendJson $ctx $result
                                }
                                '/api/build-native/start' {
                                    SendJson $ctx (StartNativeBuildJob $body 'native')
                                }
                                '/api/build-visual-native/start' {
                                    SendJson $ctx (StartNativeBuildJob $body 'visual')
                                }
                                '/api/build-visual-native' {
                                    $result = BuildNativeVisualProject $body
                                    SendJson $ctx $result
                                }
                                '/api/build' {
                                    $backend = [string]$body.backend
                                    if ($backend -in @('sharp', 'sharp-payload')) {
                                        $result = BuildSharp $body.project ([string]$body.programCode) $backend ([string]$body.output)
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
$listener.Stop()

# runtime/server-status.ps1 — estado del entorno. Extraído de server.ps1 en 1.1.59 (dot-sourced: comparte el ámbito $script:).
#requires -Version 5.1

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
  return @{root=$script:Root;workspace=$script:Workspace;wslDistribution=$wslDist;sdks=$sdks;toolchainHealth=$toolchainHealth;offlineEnvironment=$offlineEnvironment;backendCapabilities=GetPS5HSBackendCapabilities;prerequisites=@{git=$git.ok;gitPath=$git.path;dotnet10=$dot10;wsl=$wslOk;wslDotnet10=$wslDot;wslGitPython=$wslGitPython;items=$items}}
}


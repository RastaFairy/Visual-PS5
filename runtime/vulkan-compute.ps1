# PS5 Homebrew Studio: local Vulkan Compute shader workspace generation.
# This compiles GLSL to SPIR-V only. It does not run shaders or claim GPU validation.
function GetVulkanComputeSourceHash([string]$Source) {
  $bytes=[System.Text.UTF8Encoding]::new($false).GetBytes($Source)
  $algorithm=[System.Security.Cryptography.SHA256]::Create()
  try { return [BitConverter]::ToString($algorithm.ComputeHash($bytes)).Replace('-','').ToLowerInvariant() }
  finally { $algorithm.Dispose() }
}

function GetVulkanComputeGraphErrors($Graph) {
  $errors = [System.Collections.Generic.List[string]]::new()
  if ($null -eq $Graph -or [string]$Graph.schema -ne 'ps5hs-vulkan-compute-graph' -or [int]$Graph.version -ne 1) { $errors.Add('El grafo debe usar ps5hs-vulkan-compute-graph versión 1.'); return @($errors) }
  if ([string]$Graph.revisionId -notmatch '^[A-Za-z0-9_-]{1,64}$') { $errors.Add('El grafo no declara un revisionId seguro para asociar las mediciones GPU.') }
  if ([string]$Graph.target.api -ne 'Vulkan' -or [string]$Graph.target.shaderTarget -ne 'vulkan1.2') { $errors.Add('El destino debe ser Vulkan 1.2.') }
  foreach ($axis in @('width','height')) { $value=0L; if (![long]::TryParse([string]$Graph.target.$axis,[ref]$value) -or $value -lt 1 -or $value -gt 16384) { $errors.Add("La dimensión de destino $axis debe estar entre 1 y 16384.") } }
  $resources = @($Graph.resources); $passes = @($Graph.passes)
  if ($resources.Count -gt 128) { $errors.Add('El límite es 128 imágenes por grafo.') }
  if ($passes.Count -lt 1 -or $passes.Count -gt 64) { $errors.Add('El grafo debe contener entre 1 y 64 pases.') }
  $resourceIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($resource in $resources) {
    $id=[string]$resource.id
    if ($id -notmatch '^[A-Za-z_][A-Za-z0-9_-]{0,63}$' -or !$resourceIds.Add($id)) { $errors.Add("Identificador de recurso vacío, inseguro o duplicado: $id"); continue }
    if ([string]$resource.kind -ne 'storage-image') { $errors.Add("Tipo de recurso no compatible en $id; solo se admiten storage-image.") }
    if ([string]$resource.format -notin @('rgba8','rgba16f','r32f','rg16f')) { $errors.Add("Formato no admitido en $id.") }
    foreach ($axis in @('width','height')) { $value=0L; if (![long]::TryParse([string]$resource.$axis,[ref]$value) -or $value -lt 1 -or $value -gt 16384) { $errors.Add("Dimensión $axis inválida en $id.") } }
    if ($resource.externalInput -isnot [bool]) { $errors.Add("El recurso $id debe declarar externalInput como booleano.") }
  }
  $passIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $writers = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($pass in $passes) {
    $id=[string]$pass.id; $where=if($id){$id}else{'(sin ID)'}
    if ($id -notmatch '^[A-Za-z_][A-Za-z0-9_-]{0,63}$' -or !$passIds.Add($id)) { $errors.Add("Identificador de pase vacío, inseguro o duplicado: $id"); continue }
    $localProduct=1L
    foreach ($axis in @('x','y','z')) {
      $local=0L; $dispatch=0L
      if (![long]::TryParse([string]$pass.localSize.$axis,[ref]$local) -or $local -lt 1 -or $local -gt 1024) { $errors.Add("Tamaño local $axis inválido en $where.") } else { $localProduct *= $local }
      if (![long]::TryParse([string]$pass.dispatch.$axis,[ref]$dispatch) -or $dispatch -lt 1 -or $dispatch -gt 4194240) { $errors.Add("Dimensión dispatch $axis inválida en $where.") }
      elseif ($local -gt 0 -and [Math]::Ceiling($dispatch / [double]$local) -gt 65535) { $errors.Add("El dispatch $axis supera 65535 grupos Vulkan en $where.") }
    }
    if ($localProduct -gt 1024) { $errors.Add("El grupo local supera 1024 invocaciones en $where.") }
    $source=[string]$pass.source
    if ([string]::IsNullOrWhiteSpace($source) -or $source.Length -gt 524288) { $errors.Add("El shader de $where está vacío o supera 512 KiB."); continue }
    if ($source -notmatch '(?m)^\s*#version\s+450\b' -or $source -notmatch '\bvoid\s+main\s*\(') { $errors.Add("El shader de $where debe declarar #version 450 y void main().") }
    foreach ($axis in @('x','y','z')) { $local=0L; if([long]::TryParse([string]$pass.localSize.$axis,[ref]$local) -and $source -notmatch ("\blocal_size_"+$axis+"\s*=\s*"+$local+"\b")) { $errors.Add("El local_size_$axis GLSL no coincide con el modelo en $where.") } }
    $bindings=@($pass.bindings);$seenBindings=[System.Collections.Generic.HashSet[int]]::new()
    foreach ($binding in $bindings) {
      $resourceId=[string]$binding.resourceId;$bindingIndex=-1
      if (!$resourceIds.Contains($resourceId)) { $errors.Add("$where referencia el recurso inexistente $resourceId.") }
      if (![int]::TryParse([string]$binding.binding,[ref]$bindingIndex) -or $bindingIndex -lt 0 -or $bindingIndex -gt 31 -or !$seenBindings.Add($bindingIndex)) { $errors.Add("Binding inválido o duplicado en $where.") }
      else {
        $layoutPattern='(?s)layout\s*\((?<layout>[^)]*\bbinding\s*=\s*'+$bindingIndex+'\b[^)]*)\)\s*(?<declaration>[^;]*\buniform\s+[^;]*);'
        $layoutDeclaration=[regex]::Match($source,$layoutPattern)
        if(!$layoutDeclaration.Success -or $layoutDeclaration.Groups['declaration'].Value -notmatch '\bimage2D\b') { $errors.Add("El shader de $where no declara una imagen image2D en binding=$bindingIndex.") }
        else {
          $layoutQualifiers=$layoutDeclaration.Groups['layout'].Value;$declarationText=$layoutDeclaration.Groups['declaration'].Value
          $setMatch=[regex]::Match($layoutQualifiers,'\bset\s*=\s*(\d+)\b');if($setMatch.Success -and [int]$setMatch.Groups[1].Value -ne 0){$errors.Add("El binding $bindingIndex de $where debe usar set = 0.")}
          $resource=$resources|Where-Object { [string]$_.id -ceq $resourceId }|Select-Object -First 1
          $formatMatch=[regex]::Match($layoutQualifiers,'\b(rgba8|rgba16f|rg16f|r32f)\b');if($resource -and (!$formatMatch.Success -or $formatMatch.Groups[1].Value -cne [string]$resource.format)){$errors.Add("El formato GLSL del binding $bindingIndex no coincide con el recurso $resourceId.")}
          if([string]$binding.access -eq 'read' -and $declarationText -notmatch '\breadonly\b'){$errors.Add("El binding $bindingIndex de $where debe declararse readonly en GLSL.")}
          if([string]$binding.access -eq 'write' -and $declarationText -notmatch '\bwriteonly\b'){$errors.Add("El binding $bindingIndex de $where debe declararse writeonly en GLSL.")}
          if([string]$binding.access -eq 'readwrite' -and $declarationText -match '\b(readonly|writeonly)\b'){$errors.Add("El binding $bindingIndex de $where debe permitir lectura y escritura en GLSL.")}
        }
      }
      if ([string]$binding.access -notin @('read','write','readwrite')) { $errors.Add("Acceso de binding no válido en $where.") }
      if ([string]$binding.access -in @('read','readwrite')) { $resource=$resources|Where-Object { [string]$_.id -ceq $resourceId }|Select-Object -First 1; if($resource -and !$resource.externalInput -and !$writers.Contains($resourceId)){$errors.Add("$where lee $resourceId antes de que un pase anterior lo escriba.")} }
    }
    $declaredImageBindings=[System.Collections.Generic.HashSet[int]]::new()
    foreach($descriptor in [regex]::Matches($source,'(?s)layout\s*\((?<layout>[^)]*)\)\s*(?<declaration>[^;]*\buniform\s+[^;]*\bimage2D\b[^;]*);')){
      $declaredBinding=[regex]::Match($descriptor.Groups['layout'].Value,'\bbinding\s*=\s*(\d+)\b')
      if(!$declaredBinding.Success){$errors.Add("Una imagen GLSL de $where no declara binding.");continue}
      $declaredIndex=[int]$declaredBinding.Groups[1].Value
      if(!$declaredImageBindings.Add($declaredIndex)){$errors.Add("La imagen GLSL de $where repite binding=$declaredIndex.")}
      if(!$seenBindings.Contains($declaredIndex)){$errors.Add("El shader de $where declara binding=$declaredIndex sin un recurso enlazado.")}
    }
    foreach ($binding in $bindings | Where-Object { [string]$_.access -in @('write','readwrite') }) { [void]$writers.Add([string]$binding.resourceId) }
  }
  return @($errors)
}

function BuildVulkanComputeProject($Body) {
  $name=[string]$Body.projectName
  if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._-]{0,39}$') { return @{ok=$false;message='Nombre inválido. Usa entre 1 y 40 caracteres ASCII.';output=$name} }
  $graph=$Body.graph;$errors=@(GetVulkanComputeGraphErrors $graph)
  if ($errors.Count) { return @{ok=$false;message='El grafo Vulkan Compute no ha superado la validación del servidor.';output=($errors -join [Environment]::NewLine);exitCode=2} }
  try { $policy=AssertPS5HSNativeModificationConsent -Backend 'vulkan-compute' -Policy $Body.nativeModifications -RequirePermissionKeys @('allowVulkanComputeShaderBuild') }
  catch { return @{ok=$false;message='Operación detenida: falta autorización para generar el workspace y compilar los shaders locales.';output=$_.Exception.Message;buildStoppedBeforeMutation=$true} }
  $status=GetStatus
  if (!$status.prerequisites.wsl) { return @{ok=$false;message='No hay una distribución WSL inicializada.';output='Configura WSL y completa el primer arranque antes de compilar shaders.'} }
  $wsl=CmdInfo 'wsl.exe';if(!$wsl.ok){return @{ok=$false;message='wsl.exe no está disponible.';output='La compilación GLSL requiere la distribución WSL configurada.'} }
  $distribution=[string]$status.wslDistribution
  $compilerProbe=@(& $wsl.path -d $distribution --exec bash -lc 'command -v glslangValidator' 2>&1);$compilerExit=$LASTEXITCODE
  $compiler=([string](@($compilerProbe|Select-Object -Last 1)[0])).Trim()
  if($compilerExit -ne 0 -or $compiler -notmatch '^/[A-Za-z0-9_./+-]+$'){return @{ok=$false;message='No se encontró glslangValidator dentro de WSL.';output='Instala o incorpora glslangValidator a la imagen local de Ubuntu; este flujo no descarga dependencias.'} }
  $target='';$outputLines=[System.Collections.Generic.List[string]]::new();$artifactRecords=[System.Collections.Generic.List[object]]::new()
  try {
    if (!(Test-Path -LiteralPath $script:Workspace -PathType Container)) { New-Item -ItemType Directory -Force -Path $script:Workspace | Out-Null }
    $null=AssertPS5HSNativePathNoReparsePoints -Path $script:Workspace
    $slug=Slug $name;$target=Join-Path $script:Workspace ($slug+'-Vulkan-Compute')
    if(Test-Path -LiteralPath $target){$target=Join-Path $script:Workspace ($slug+'-Vulkan-Compute-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))}
    if(!(TestPS5HSNativeProjectDestinationAvailable -Path $target)){return @{ok=$false;message='El destino del workspace no está vacío o no es una ruta segura.';output=$target;path=$target} }
    $null=AssertPS5HSNativePathNoReparsePoints -Path $target
    $graphJson=ConvertTo-Json -InputObject $graph -Depth 40
    $manifestPasses=@(foreach($pass in @($graph.passes)){ $groups=@([Math]::Ceiling([double]$pass.dispatch.x/[double]$pass.localSize.x),[Math]::Ceiling([double]$pass.dispatch.y/[double]$pass.localSize.y),[Math]::Ceiling([double]$pass.dispatch.z/[double]$pass.localSize.z));$sourceSha=GetVulkanComputeSourceHash ([string]$pass.source);[ordered]@{id=[string]$pass.id;name=[string]$pass.name;shader=('shaders/'+[string]$pass.id+'.comp');shaderSha256=$sourceSha;spirv=('build/spirv/'+[string]$pass.id+'.spv');localSize=$pass.localSize;dispatch=$pass.dispatch;workgroups=$groups;bindings=@($pass.bindings)} })
    $manifest=[ordered]@{schema='ps5hs-vulkan-compute-graph';version=1;revisionId=[string]$graph.revisionId;projectName=$name;target=$graph.target;resources=@($graph.resources);passes=$manifestPasses;hardwareValidation=[ordered]@{status='not-run';reportSchema='ps5hs-vulkan-compute-report';note='SPIR-V compilado; no se ha ejecutado en GPU.'}}
    $manifestJson=(ConvertTo-Json -InputObject $manifest -Depth 40)+[Environment]::NewLine
    $readme="# $name`r`n`r`nWorkspace PS5 Homebrew Studio para Vulkan Compute.`r`n`r`n- compute-graph.json: grafo editable y dimensiones del destino.`r`n- shaders/*.comp: fuentes GLSL 450 por pase.`r`n- build/spirv/*.spv: módulos SPIR-V compilados y verificados.`r`n- gpu-report.json: formato opcional para registrar una ejecución real; no se genera hasta importar una medición.`r`n`r`nLa compilación con glslangValidator no ejecuta el shader. Se requiere integrar y ejecutar estos pases desde una aplicación Vulkan en el runtime de destino para obtener tiempos GPU o validar píxeles.`r`n"
    $null=InvokePS5HSNativeTreeModificationWithAudit -ProjectRoot $target -Backend 'vulkan-compute' -Operation 'compile-vulkan-compute-shaders' -PermissionKey 'allowVulkanComputeShaderBuild' -Policy $policy -Action {
      New-Item -ItemType Directory -Force -Path (Join-Path $target 'shaders'),(Join-Path $target 'build/spirv') | Out-Null
      WriteUtf8 (Join-Path $target 'compute-graph.json') $graphJson
      WriteUtf8 (Join-Path $target 'compute-manifest.json') $manifestJson
      WriteUtf8 (Join-Path $target 'README.md') $readme
      foreach($pass in @($graph.passes)){
        $sourcePath=Join-Path $target ('shaders/'+[string]$pass.id+'.comp');$outputPath=Join-Path $target ('build/spirv/'+[string]$pass.id+'.spv')
        WriteUtf8 $sourcePath ([string]$pass.source)
        $sourceWsl=ConvertToWslPath $sourcePath;$outputWsl=ConvertToWslPath $outputPath
        $compilerOutput=@(& $wsl.path -d $distribution --exec $compiler -V --target-env vulkan1.2 $sourceWsl -o $outputWsl 2>&1);$exit=$LASTEXITCODE
        foreach($line in $compilerOutput){$lineText=[string]$line;$outputLines.Add($lineText);if($script:ActiveBuildLogPath){WriteBuildJobLog $script:ActiveBuildLogPath $lineText}}
        if($exit -ne 0){throw "glslangValidator falló para $($pass.id) con código $exit."}
        if(!(Test-Path -LiteralPath $outputPath -PathType Leaf)){throw "glslangValidator terminó sin crear el archivo SPIR-V de $($pass.id)."}
        $bytes=[IO.File]::ReadAllBytes($outputPath)
        if($bytes.Length -lt 20 -or $bytes[0] -ne 3 -or $bytes[1] -ne 2 -or $bytes[2] -ne 35 -or $bytes[3] -ne 7){throw "La salida de $($pass.id) no contiene la cabecera mágica SPIR-V esperada."}
        $hash=(Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $artifactRecords.Add([ordered]@{file=('build/spirv/'+[string]$pass.id+'.spv');bytes=$bytes.Length;sha256=$hash})
        $verificationLine="SPIR-V verificado: $($pass.id) · $($bytes.Length) bytes · SHA-256 $hash"; $outputLines.Add($verificationLine); if($script:ActiveBuildLogPath){WriteBuildJobLog $script:ActiveBuildLogPath $verificationLine}
      }
    }
    return @{ok=$true;message='Los shaders GLSL se compilaron y cada archivo SPIR-V pasó la verificación de cabecera. El grafo todavía no se ha ejecutado en GPU.';output=($outputLines -join [Environment]::NewLine);path=$target;artifacts=@($artifactRecords);hardwareValidation='not-run';exitCode=0}
  } catch { return @{ok=$false;message='La generación o compilación del workspace Vulkan Compute falló. Las fuentes y salidas parciales se conservan para diagnóstico.';output=$_.Exception.Message;path=$(if($target){$target}else{$null});artifacts=@($artifactRecords);exitCode=1} }
}

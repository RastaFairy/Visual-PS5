# Plan reducido: instalacion offline de Visual-PS5

> **Para los agentes de implementacion:** seguir una tarea cada vez y marcar las casillas al terminarlas. La implementacion se ejecuta en este hilo, manteniendo coordinadas las interfaces entre empaquetador, instalador e IDE.

**Objetivo:** En un Windows limpio, instalar Visual-PS5 y su Ubuntu WSL2 ya preparada sin descargas, sin pedir al desarrollador que instale o configure dependencias manualmente.

**Enfoque:** Usar como semilla la Ubuntu 26.04.1 amd64 que ya existe en la maquina del usuario. Exportarla a una copia de trabajo, inventariar licencias y dependencias, retirar solo salidas temporales de compilacion, validar builds sin red y empaquetar esa imagen. No modificar ni borrar la distro original. No construir una Ubuntu vacia salvo que la imagen actual no supere las comprobaciones.

**Requisitos del host:** Windows PowerShell 5.1 para el bootstrap (ya viene en Windows); MSI offline de WSL2 en `toolchains/WSL2/`; Ubuntu WSL2 preconfigurada; IDE y toolchains. El MSI de PowerShell 7 se conserva como opcion, pero no es requisito mientras la aplicacion siga funcionando en Windows PowerShell 5.1.

**Diseno aprobado:** `docs/superpowers/specs/2026-10-22-offline-self-sufficient-design.md`

## Restricciones

- El host Windows, la importacion de Ubuntu y las compilaciones cubiertas deben funcionar con la red desconectada.
- El instalador valida hashes y firmas disponibles antes de instalar. No consulta Microsoft Store, `winget`, GitHub, apt ni otras fuentes remotas.
- El bootstrap funciona en Windows PowerShell 5.1 y nunca eleva el servidor de la IDE.
- No cambia BIOS/UEFI, no fuerza reinicios, no desregistra distros existentes y puede reanudarse al volver a ejecutarlo.
- La limpieza se aplica unicamente a una imagen de staging. No borra la Ubuntu original ni los proyectos fuente del usuario.
- `build/` contiene salidas generadas; `.deps/` contiene dependencias reales. No eliminar `.deps/` hasta confirmar cada entrada, su licencia y si forma parte del cierre offline.
- Un backend solo se anuncia como listo para compilar sin red cuando todas sus dependencias y licencias estan verificadas. Los demas quedan como fuente/referencia o requisito externo, con motivo visible.
- La primera prueba fisica es el Windows 11 22H2 del usuario; se registra su edicion/build. Una version compatible y actualmente soportada de Windows 11 sigue siendo la puerta de lanzamiento.
- `C:\Visual-PS5` no tiene metadatos Git. Mantener un inventario de archivos modificados y no afirmar que hay commits hasta sincronizar con un checkout Git.

## Puntos de revision

- La exportacion no modifica ni sustituye la distro Ubuntu original.
- La copia no incluye claves, credenciales, tokens, proyectos personales ni archivos temporales.
- Las salidas de compilacion no se confunden con SDKs, fuentes o archivos necesarios para builds offline.
- Ubuntu importada inicia con un usuario normal definido, no queda operativa solo como `root`.
- Un MSI, imagen o artefacto ausente, truncado o con hash incorrecto detiene el proceso antes de modificar Windows.
- Virtualizacion BIOS desactivada, funciones de Windows sin payload local, falta de espacio y reinicio pendiente producen instrucciones especificas, sin descargas silenciosas.
- Repetir o reanudar la instalacion conserva las distros existentes y no duplica ni sobrescribe la distro de Visual-PS5.

---

### Tarea 1: Preparar y sanear una copia de Ubuntu

**Archivos:**
- Crear `runtime/Prepare-OfflineImage.ps1`
- Crear `runtime/offline/prepare-image.sh`
- Crear `runtime/offline/image-lock.json`
- Crear `runtime/test-offline-image.ps1`
- Documentar la imagen en `docs/OFFLINE_INSTALLATION.es-ES.md`

**Interfaz:** `Prepare-OfflineImage.ps1 -SourceDistro Ubuntu -OutputRoot <ruta>` exporta la distro a un staging temporal, la importa con un nombre aislado, aplica una lista permitida de limpieza y genera `image-manifest.json` con release, arquitectura, paquetes/versiones, dependencias incluidas, licencias, tamanos y SHA-256.

- [x] Escribir pruebas para exportacion no destructiva, deteccion de `build/`, preservacion de `.deps/`, rechazo de credenciales y comprobacion de identidad Ubuntu.
- [x] Ejecutar `powershell.exe -NoProfile -File runtime/test-offline-image.ps1`; pasa.
- [ ] Inventariar paquetes, comandos, tamanos, fuentes de paquetes y licencias de `/opt`, `.deps`, caches y toolchains. Resolver que partes de `.deps` se necesitan y se pueden redistribuir.
- [x] Implementar exportacion y limpieza solo en staging. Configurar usuario normal predeterminado para WSL. La copia actual retira el home completo del usuario de origen; el inventario previo no encontro dependencias unicas necesarias dentro de ese home. La limpieza selectiva de caches `build/` queda pendiente si se decide preservar algun dato del home.
- [x] Generar la primera imagen saneada `toolchains/WSL2/visual-ps5-ubuntu-26.04.1-amd64.tar` (5,417,789,440 bytes; SHA-256 `bcfc29378ce1bef6e4bfad0fdd25f300dc4fc0e3c94d8e435d657ba8092267fa`) y su manifiesto.
- [x] Importar la imagen con otro nombre WSL y comprobar Ubuntu 26.04.1, usuario predeterminado `visualps5`, `systemd=true`, herramientas base y `/opt/ps5-payload-sdk/bin/prospero-lld`.
- [ ] Cerrar inventario de licencias/redistribución y escaneo de credenciales; ejecutar builds representativos por backend antes de declarar la imagen lista para distribución. La muestra Payload se compiló sin red; los demás siguen pendientes.
- [x] Reimportar la copia con nombre nuevo, verificar manifiesto e identidad, ejecutar las comprobaciones de dependencias y compilar la muestra Payload con la red desconectada.
- [x] Registrar el hash de la imagen y los archivos de código cambiados. La distro fuente `Ubuntu` sigue registrada e intacta.

### Tarea 2: Empaquetar los componentes offline

**Archivos:**
- Crear `runtime/offline/OfflineBundle.psm1`
- Crear `runtime/Build-OfflineBundle.ps1`
- Crear `runtime/test-offline-bundle.ps1`
- Modificar `.github/workflows/package-self-contained-ide.yml` (pendiente: la imagen Ubuntu local ocupa 5,4 GB y no está en el checkout Git; el bundle actual se genera localmente fuera del árbol de Git.)
- Actualizar `docs/TOOLCHAIN-VENDORING.md`

**Interfaz:** `Build-OfflineBundle.ps1 -InputRoot <ruta> -OutputRoot <ruta>` combina IDE, toolchains, MSI de WSL firmado, imagen validada y manifiestos. `Test-PS5HSOfflineBundle -BundleRoot <ruta>` verifica archivos, versiones, tamanos, hashes, firmas y backends; lo comparten el empaquetador y el instalador.

- [x] Probar paquete completo, MSI ausente, hash incorrecto, imagen ausente, dependencia de backend ausente y preservacion de `toolchains/`.
- [x] Ejecutar `powershell.exe -NoProfile -File runtime/test-offline-bundle.ps1`; pasa.
- [x] Implementar empaquetado desde archivos locales, respetando rutas y rechazando una salida no vacia. Incluir PowerShell 7.6.1 solo como componente opcional.
- [x] Generar `manifest.json` y `SHA256SUMS`; no omitir dependencias si el paquete supera el limite de un workflow, sino dividirlo con manifiesto unico.
- [x] Generar el bundle final con el instalador y la matriz offline: `C:\Visual-PS5-offline-bundle-20261022-final`; 93.225 archivos, 10.213.382.537 bytes. La imagen WSL conserva SHA-256 `bcfc29378ce1bef6e4bfad0fdd25f300dc4fc0e3c94d8e435d657ba8092267fa`; la validación estructural/hash recién generado pasó.
- [x] Ejecutar las pruebas del empaquetador y `runtime/check-syntax.ps1`; ambos pasan.

### Tarea 3: Instalar WSL2 e importar Ubuntu sin red

**Archivos:**
- Crear `runtime/offline/OfflineEnvironment.psm1`
- Crear `runtime/Install-OfflineEnvironment.ps1`
- Crear `INSTALL-OFFLINE.bat`
- Crear `runtime/test-offline-environment.ps1`
- Modificar `runtime/check-syntax.ps1`

**Interfaz:** `Get-PS5HSOfflineHostPreflight -BundleRoot <ruta>` informa Windows, arquitectura, elevacion, virtualizacion, funciones WSL, espacio y estado del bundle. `Install-PS5HSOfflineEnvironment -BundleRoot <ruta> [-Apply]` valida primero y luego ejecuta solo las acciones locales confirmadas.

- [x] Probar host compatible/no compatible, bundle corrupto, virtualizacion desactivada/desconocida, falta de espacio, elevacion, colision con una distro existente y reanudacion tras reiniciar mediante operaciones simuladas.
- [x] Ejecutar `powershell.exe -NoProfile -File runtime/test-offline-environment.ps1`; pasa.
- [x] Implementar preflight de solo lectura y mensajes concretos. Si BIOS/UEFI debe cambiar, pedir al usuario que lo habilite manualmente.
- [x] Instalar WSL desde `toolchains/WSL2/`, activar las funciones de Windows necesarias usando payload local, importar Ubuntu con un nombre de distro propio y verificar el usuario predeterminado.
- [x] Solicitar elevacion solo para los cambios que la necesitan; no usar tareas SYSTEM, no forzar reinicio y permitir continuar por etapas al volver a ejecutar.
- [x] Ejecutar pruebas con operaciones del host simuladas y `runtime/check-syntax.ps1`.
- [ ] Ejecutar el instalador real en Windows 11 22H2 limpio con la red desconectada.

### Tarea 4: Conectar la IDE y aceptar la instalacion offline

**Archivos:**
- Modificar `runtime/server.ps1`, `app.js`, `runtime/test-api-contracts.js`, `runtime/test-build-flow.js`, `runtime/test-toolchain-pins.js`
- Modificar `docs/MANUAL.es-ES.md` y `README_ES.md`
- Crear o completar `docs/OFFLINE_INSTALLATION.es-ES.md`

**Interfaz:** `/api/status` diferencia IDE instalada, WSL listo, Ubuntu verificada y backends listos/fuente/bloqueados. El servidor ofrece diagnostico y apertura del instalador; nunca ejecuta UAC por su cuenta.

- [x] Anadir aserciones para el estado offline, el backend sin dependencias y el instalador; la UI ya no ofrece rutas genéricas de descarga.
- [x] Integrar `/api/status`, mostrar la matriz en el IDE y bloquear builds empaquetados incompletos antes de mutar proyectos, con el motivo de readiness.
- [x] Ejecutar `node --check app.js`, `node runtime/test-api-contracts.js`, `node runtime/test-build-flow.js`, `node runtime/test-toolchain-pins.js` y `powershell.exe -NoProfile -File runtime/check-syntax.ps1`.
- [ ] Copiar el paquete a Windows 11 22H2 limpio, desconectar la red, instalar, reiniciar solo si Windows lo pide y compilar los proyectos de prueba admitidos. Registrar logs, backend, artefacto y hash.
- [ ] Repetir en una version de Windows 11 que siga soportada antes de declarar disponibilidad general.
- [x] Entregar inventario de cambios, resultados y limitaciones; separar prueba de compilacion de validacion en consola PS5.

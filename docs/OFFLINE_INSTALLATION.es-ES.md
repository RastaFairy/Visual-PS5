# Instalación offline de Visual-PS5

## Estado y alcance

Visual-PS5 ya contiene el bootstrap de Windows y la imagen Ubuntu que se usarán en el bundle. Las pruebas del bootstrap usan un host simulado; la instalación todavía no se ha validado en un Windows limpio ni desconectado. La preparación de la imagen también conserva pendiente la auditoría completa de licencias y redistribución.

La imagen WSL generada incorpora las cabeceras y bibliotecas PS5 Payload de PacBrew fijadas por SHA-256. Si se compila ShadowMountPlus desde una distribución WSL existente, el IDE usa el mismo archivo local de `toolchains/artifacts/` para preparar una caché bajo `.runtime/`, sin instalar paquetes ni cambiar esa distribución.

| Componente | Estado comprobado |
| --- | --- |
| WSL offline | `toolchains/WSL2/wsl.2.9.13.0.x64.msi`; firma Authenticode de Microsoft válida |
| Ubuntu WSL2 | Ubuntu 26.04.1 LTS, amd64; usuario predeterminado `visualps5`; `systemd=true` |
| Imagen tar | 5.417.789.440 bytes; SHA-256 `bcfc29378ce1bef6e4bfad0fdd25f300dc4fc0e3c94d8e435d657ba8092267fa` |
| Build offline representativo | La muestra `hello_world` de PS5 Payload SDK compila con la red aislada y produce un ELF para ABI PS5 |
| Bootstrap | `INSTALL-OFFLINE.bat`, `runtime/Install-OfflineEnvironment.ps1` y `runtime/offline/OfflineEnvironment.psm1`; pruebas simuladas pasan |
| Integridad del bundle | `manifest.json` y `SHA256SUMS` cubren archivos, tamaños, hashes, imagen, firma MSI y estado de los backends |

La compilación del ejemplo no demuestra que OpenGL, Vulkan, SharpProspero o una consola PS5 estén validados. La matriz `runtime/offline/backend-readiness.json` es la fuente de verdad: la plantilla nativa, OpenGL, Vulkan y SharpProspero permanecen bloqueados hasta completar una compilación representativa sin red y cerrar sus dependencias/licencias. El IDE en un bundle bloqueará builds de backends que no figuren como `validated`.

## Instalación en un equipo limpio

1. Copia y extrae el bundle offline completo en una unidad con espacio suficiente. No basta con copiar únicamente el directorio del IDE: deben estar presentes `toolchains/`, la imagen WSL, el MSI y los manifiestos.
2. Ejecuta `INSTALL-OFFLINE.bat`. El diagnóstico revisa primero el hash y la firma del bundle, versión y arquitectura de Windows, virtualización, características WSL, espacio disponible y colisiones con distribuciones existentes.
3. Si el diagnóstico solicita autorización, acepta UAC para habilitar las características de Windows o instalar el MSI WSL local. La habilitación usa DISM con `/LimitAccess`; el bootstrap no consulta Windows Update, Microsoft Store, `winget`, GitHub ni apt.
4. Si Windows indica que hace falta reiniciar, reinicia manualmente y vuelve a ejecutar `INSTALL-OFFLINE.bat`. El estado de reanudación se guarda en `%LOCALAPPDATA%\Visual-PS5\offline-install.json`.
5. Cuando termine, la distro `VisualPS5-Ubuntu-26.04` queda registrada en `%LOCALAPPDATA%\Visual-PS5\WSL\Ubuntu-26.04` y se verifica el usuario `visualps5`, Ubuntu 26.04 y las rutas de herramientas requeridas.
6. Inicia Visual-PS5 con `start.bat`. En **Configurar entorno de compilación** puedes consultar el estado de WSL, la verificación de Ubuntu y la matriz de preparación por backend.

La instalación es idempotente para su distro: si ya está registrada en la ruta esperada, valida su contenido y la reutiliza. Si existe el mismo nombre en otra ubicación, el instalador se detiene sin desregistrar ni sobrescribir distros del usuario. El servidor del IDE no solicita UAC; la elevación ocurre únicamente al ejecutar el instalador.

## Requisitos y límites del sistema

- El bootstrap actual admite Windows 11 x64 (compilación 22000 o posterior); el bundle usa una imagen amd64.
- WSL2 necesita virtualización disponible en firmware y las características `Microsoft-Windows-Subsystem-Linux` y `VirtualMachinePlatform`. Si la BIOS/UEFI informa que está deshabilitada, actívala manualmente siguiendo las instrucciones del fabricante. El instalador no modifica firmware.
- Habilitar características puede requerir administrador y reinicio. Si el almacén local de componentes de Windows no tiene el payload necesario, DISM con acceso limitado fallará y el diagnóstico indicará que Windows necesita una fuente local; no descargará una alternativa.
- El preflight reserva como mínimo el mayor de 10 GiB o dos veces el tamaño de la imagen más 8 GiB en la unidad de instalación. El bundle completo ocupa más que el tar de Ubuntu y debe transportarse por separado.
- Windows 11 22H2 es el primer equipo físico de prueba indicado por el usuario. Pasar ese preflight no basta para declarar disponibilidad general ni soporte en versiones de Windows que estén fuera de soporte.
- No se incluyen firmware, claves, licencias ni binarios propietarios de Sony. Algunos pipelines también pueden necesitar recursos del usuario.

## Archivos de implementación

- Instalador de un clic: `INSTALL-OFFLINE.bat`
- Orquestación de Windows: `runtime/Install-OfflineEnvironment.ps1`
- Preflight, instalación local, importación y verificación WSL: `runtime/offline/OfflineEnvironment.psm1`
- Validador de hashes, firma y manifiestos: `runtime/offline/OfflineBundle.psm1`
- Constructor del bundle fuera del árbol Git: `runtime/Build-OfflineBundle.ps1`
- Preparación de la imagen Ubuntu en staging: `runtime/Prepare-OfflineImage.ps1`
- Pruebas simuladas: `runtime/test-offline-environment.ps1` y `runtime/test-offline-bundle.ps1`

La distro Ubuntu fuente sigue intacta. Las distros temporales `PS5HS-ImagePrep-*` y `PS5HS-ImageVerify-*`, y el tar intermedio de exportación, permanecen en el equipo de preparación porque la revisión automática impidió eliminarlos. Ese tar intermedio contiene una copia del home original y no se debe distribuir.

# Diseño: distribución offline y autosuficiente de Visual-PS5

**Estado:** propuesta para revisión del usuario  
**Fecha:** 2026-10-22

## Objetivo

Un desarrollador debe poder recibir Visual-PS5 en un equipo Windows limpio, instalarlo y compilar los backends que el IDE declara compatibles sin conexión a Internet ni herramientas de desarrollo instaladas previamente. El paquete debe incluir una distribución Ubuntu para WSL2 ya preparada con los requisitos Linux y las fuentes/archivos redistribuibles que necesite cada backend.

“Offline” significa que, desde que se entrega el paquete al equipo hasta que termina la compilación, el instalador, el IDE y los scripts no necesitan acceder a Internet. La transferencia del paquete puede hacerse por USB, red local u otro medio.

## Enfoque seleccionado

Se distribuye un paquete autocontenido compuesto por:

1. Los archivos del IDE y sus toolchains, plantillas, fuentes y artefactos locales.
2. Los componentes redistribuibles de WSL necesarios para instalarlo sin conexión, fijados a una versión compatible.
3. Una imagen Ubuntu para WSL2 generada desde un manifiesto reproducible, con los paquetes Linux de compilación instalados.
4. Los runtimes y utilidades de Windows requeridos por las funciones anunciadas como compatibles, incluidos los instaladores offline redistribuibles que no puedan ejecutarse de forma portable.
5. Un manifiesto de contenido con versiones, hashes SHA-256, procedencia, arquitectura, licencias y backends cubiertos.
6. Un instalador de Windows y un bootstrap local que validan e instalan el entorno sin descargar archivos.

La imagen Ubuntu es el entorno de compilación; las fuentes y dependencias propias de los proyectos siguen en los paquetes de toolchains del IDE. Cuando un backend necesite trabajar en el sistema de archivos Linux para preservar enlaces, permisos o semántica POSIX, el IDE preparará una copia de trabajo local dentro de WSL desde los archivos ya incluidos.

## Instalación en el equipo del desarrollador

El instalador debe:

1. Ejecutar un preflight de solo lectura: versión/edición/arquitectura de Windows, elevación, características y versión de WSL, distribuciones existentes, espacio libre, reinicio pendiente, estado del hipervisor y señales de virtualización de CPU/firmware.
2. Verificar hashes y versiones de todos los componentes locales antes de modificar el sistema.
3. Habilitar las características de Windows necesarias para WSL2 usando los componentes del sistema y los paquetes ya incluidos; no invocar Windows Update, Microsoft Store, `winget` ni otros servicios de red.
4. Solicitar elevación y reinicio solo cuando sean necesarios, conservar el estado de instalación y reanudar automáticamente al volver a ejecutar el instalador.
5. Importar la imagen Ubuntu desde el paquete local bajo un nombre de distribución propio del IDE, sin borrar ni registrar de nuevo distribuciones preexistentes.
6. Configurar el usuario y los valores de WSL necesarios para los builds, validar la imagen y registrar la versión del entorno instalada.
7. Mostrar un informe final que identifique qué backends están listos y, si hay un requisito del sistema imposible de satisfacer desde el paquete, qué recurso local del usuario debe aportarse.

La instalación debe ser idempotente: repetirla no duplica distribuciones ni sobrescribe proyectos, toolchains o datos de WSL preexistentes. Una actualización instala una imagen identificada por versión y no elimina la anterior hasta completar su validación.

### Diagnóstico de virtualización y script de bootstrap

El bootstrap se implementará y mantendrá dentro del proyecto como PowerShell auditado, versionado y probado contra el bundle. Para no introducir otro requisito, será compatible con Windows PowerShell 5.1, salvo que el paquete incorpore explícitamente un runtime más nuevo. Se podrán estudiar scripts públicos de instalación offline como referencia de flujo, pero no descargarlos ni ejecutarlos durante la instalación, ni incorporarlos sin revisión de código, licencia, procedencia y hashes.

El preflight combinará señales del sistema y una comprobación funcional de WSL2; no basará la decisión en un único campo de WMI/CIM. Debe diferenciar al menos: listo, falta habilitar una característica de Windows, virtualización de firmware deshabilitada, estado no concluyente y equipo/Windows incompatible. Windows puede detectar e informar el estado, pero no hay una operación genérica segura para activar la virtualización en BIOS/UEFI de fabricantes distintos. Si está deshabilitada o no puede determinarse, el instalador se detendrá antes de cambiar componentes y dará instrucciones concretas para consultar el fabricante o la BIOS/UEFI; no intentará modificar firmware.

El flujo será reanudable y explícito: diagnóstico, resumen de cambios, elevación cuando haga falta, habilitación de componentes, pausa por reinicio y continuación, importación de Ubuntu, verificación de salud. No forzará el reinicio del equipo ni registrará una tarea privilegiada de continuación sin consentimiento claro. Cada etapa emitirá un log local con los resultados y archivos utilizados.

## Alcance de soporte offline

El contrato offline cubre todas las operaciones que el IDE presente como instalables o compilables. Cada backend debe tener un inventario cerrado de compiladores, bibliotecas, paquetes Linux, fuentes, submódulos, historiales Git requeridos, herramientas auxiliares y artefactos. No se declarará un backend “offline listo” si alguno de esos elementos solo se obtiene mediante una descarga durante la instalación, generación o build.

El IDE debe distinguir explícitamente los backends completos de los catálogos que solo contienen fuentes de referencia, backends experimentales o ejemplos que no generan un artefacto independiente. No se anunciarán como compilables offline hasta que tengan una receta local reproducible y pasen la validación definida aquí.

## Restricciones de redistribución y del sistema anfitrión

El paquete incluirá únicamente componentes que se puedan redistribuir legalmente, con sus licencias y avisos. Esto también aplica a los instaladores de runtimes y herramientas de Windows: si no se permite redistribuirlos, no se prometerá que esa función quede lista solo con el bundle. No incluirá datos de juegos, firmware, claves, binarios propietarios de Sony ni otros recursos que el usuario tenga que aportar legítimamente. Si una función necesita alguno, el IDE lo marcará como entrada externa y no lo confundirá con una dependencia descargable.

La aplicación no puede reemplazar Windows ni activar capacidades de hardware ausentes. El equipo debe ejecutar una versión de Windows compatible con WSL2 y disponer de virtualización habilitable. La activación de características de Windows puede necesitar administrador, reinicio o archivos de instalación de Windows en equipos donde el almacén local de componentes no los tenga. Por eso la promesa es “sin Internet ni herramientas de desarrollo previas”, no “sin requisitos del sistema operativo o del equipo”.

## Tamaño y distribución

El inventario consultado de `toolchains/` ocupa actualmente más de 4 GB sin comprimir. La imagen Ubuntu, los componentes WSL, los paquetes de build, las copias de trabajo y el espacio temporal elevarán el espacio necesario. No se publicará una cifra mínima de almacenamiento hasta medir el paquete generado y el pico de instalación/build por backend.

La distribución debe poder transportarse íntegra por un medio offline. Se puede dividir físicamente en volúmenes para el transporte, pero el instalador verificará que todos los volúmenes requeridos estén presentes antes de comenzar. Ninguna dependencia podrá resolverse descargándola como alternativa silenciosa.

## Seguridad y trazabilidad

- Cada archivo empaquetado se verifica contra su hash antes de importarlo o instalarlo.
- El manifiesto registra fuente, versión/commit, licencia, tamaño y backends consumidores.
- La imagen Ubuntu incluye una identidad de bundle y un manifiesto de paquetes instalados, que el IDE compara con su versión esperada.
- Los logs de instalación y build indican qué recurso local se usó y por qué ruta, sin depender de mensajes genéricos de “SDK instalado”.
- Si falta un archivo, un hash no coincide o una dependencia no está declarada, el proceso falla antes de usar la red o producir un artefacto incompleto.

## Criterios de aceptación

1. En una máquina virtual Windows compatible, limpia, sin WSL, Git, Python, .NET o compiladores instalados y con acceso a red desactivado, el paquete instala el IDE y su Ubuntu WSL2 usando exclusivamente sus archivos locales.
2. El flujo tolera el paso de elevación/reinicio requerido y puede reanudarse sin duplicar la distribución ni perder datos.
3. En esa misma máquina y sin red, cada backend declarado compatible genera y verifica su artefacto desde sus fuentes/archivos locales.
4. Una captura de tráfico o un registro equivalente demuestra que instalación, preparación y compilación no intentan acceder a servicios externos.
5. Un archivo ausente, alterado o de versión incorrecta produce un diagnóstico que identifica el archivo/requisito; nunca dispara un fallback de red.
6. Los backends que requieran recursos no redistribuibles aparecen con el requisito concreto y no se presentan como plenamente autónomos.
7. La documentación y el estado del entorno distinguen con claridad: IDE abierto, entorno offline preparado, build realizado y artefacto verificado.

La primera prueba en equipo físico se realizará en el equipo casi limpio del usuario con Windows 11 22H2. Se registrarán edición, arquitectura y número de compilación exactos antes de ejecutarla. Esa prueba aporta compatibilidad con el entorno real indicado; en las ediciones Home y Pro, 22H2 está fuera de su periodo de soporte, así que no se usará por sí sola para fijar la versión mínima soportada ni como único gate de publicación. La aceptación de producto también requerirá una versión Windows soportada y compatible con WSL2.

## Fuera de alcance

- Sustituir Windows o habilitar virtualización por software cuando el firmware del equipo la tenga desactivada.
- Redistribuir componentes propietarios o datos de usuario sin autorización.
- Afirmar compatibilidad offline para todos los repositorios de referencia solo porque sus fuentes estén incluidas.
- Probar ejecución en una consola PS5; la aceptación de este diseño valida instalación y generación de artefactos en el host, no compatibilidad de firmware ni comportamiento en hardware.

## Revisión de consistencia

- La promesa offline empieza al recibir el bundle y no implica que Internet sea necesario para prepararlo en una máquina de empaquetado.
- La imagen WSL resuelve dependencias del sistema Linux; el bundle del IDE sigue siendo responsable de entregar fuentes y artefactos de cada backend.
- Los permisos, reinicio, versión de Windows, virtualización y posibles fuentes locales de componentes de Windows están expuestos como límites, no ocultos bajo “solo hace falta espacio”.
- La validación exige builds con red desactivada, no solo inspección estática de hashes o scripts.
- La automatización puede detectar o acotar problemas de virtualización, pero nunca afirmar que activó la BIOS ni escribir ajustes de firmware.

## Referencias de diseño consultadas

- Microsoft documenta la instalación offline con el paquete de WSL, habilitación de Virtual Machine Platform con elevación y reinicio, y una distribución desde un archivo local; también documenta importar distribuciones personalizadas con `wsl --import`.
- El script comunitario [WSL-Offline-Installer](https://github.com/almogopp/WSL-Offline-Installer) sirve solo como referencia de detección del sistema y continuación tras habilitar características. No es una dependencia del IDE ni una implementación aceptada: usa un paquete genérico de distribución, fuerza el reinicio y registra una tarea como SYSTEM; el bootstrap de Visual-PS5 debe usar la imagen propia, validar integridad y mantener el flujo bajo control del usuario.
- La guía de Microsoft para el error de virtualización de WSL indica que la configuración de BIOS debe consultarse con el fabricante, pues los pasos dependen del equipo. Por ello la autodetección informará el resultado y guiará la corrección, pero no intentará cambiarla.

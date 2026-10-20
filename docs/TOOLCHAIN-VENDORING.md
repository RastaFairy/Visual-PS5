# Toolchains integrados, pins y mirrors — PS5 Homebrew Studio

Este documento describe cómo el IDE integra el material de toolchains local, fija la integridad de los artefactos binarios que los proyectos descargan y sobrevive a la desaparición de repositorios upstream. Aplica desde la versión 1.1.19.

## Motivación

El 2026-10-20 la cuenta de GitHub `blackbearreloaded` desapareció, y con ella los repositorios `ps5-opengl`, `ps5-native-app-boilerplate`, `ps5-homebrew-ui`, `ProsperoLight`, `ps5-fsr4` y `ps5-helixsr`. El síntoma fue un build OpenGL detenido en `curl: (22) The requested URL returned error: 404` al descargar el SDK `ps5-opengl 1.0.2` (226 MB de binarios Mesa/Gallium precompilados que solo existían como asset de release). El IDE no puede asumir que ningún upstream comunitario vivirá para siempre: la respuesta es una arquitectura de capas donde la copia local del usuario siempre gana y la red es solo un acelerador.

## Capas de disponibilidad

El material se resuelve por prioridad; ninguna descarga sustituye a una copia local:

1. **Copia local ya adoptada** (`toolchains/<carpeta>`). `InstallRepo` nunca sobrescribe un checkout existente; si detecta `.git` + `README.md` lo adopta y registra su commit sin tocar la red. Tras la desaparición del upstream, la copia local es la fuente canónica.
2. **Pack local** (`toolchain-pack/ps5-opengl-sdk/`). El IDE verifica el tarball del SDK contra el pin SHA-256 y lo siembra en `.deps/ps5-opengl/` de cada proyecto OpenGL antes de compilar; el build del SDK se vuelve 100% offline. Se construye con `runtime/Build-ToolchainPack.ps1`.
3. **Cadena de mirrors** (`runtime/toolchain-pins.json`). El upstream original se intenta primero; si no responde, se prueban mirrors comunitarios que sirven exactamente el mismo archivo. Cada descarga se verifica con el pin original, así que un mirror que sirva algo distinto queda rechazado automáticamente.
4. **Cache del proyecto** (`.deps/`). El script de fetch upstream ya verifica `archive_sha256` y `manifest_sha256` antes de extraer; el IDE no relaja ninguna de esas comprobaciones.

## El manifiesto `runtime/toolchain-pins.json`

- `mirrors`: repositorios cuyo original está caído, con `alternatives` verificadas. Es un registro de hechos observados (con fecha), no una lista de deseos: solo se declaran mirrors que existen y, en el caso del SDK, que publican el asset comprobado byte a byte.
- `artifacts`: versiones y SHA-256 de binarios precompilados que los proyectos generados descargan. Hoy fija `ps5-opengl-sdk` 1.0.2 (tarball `30d8e51d…`, manifest interno `0d432edc…`, 226 310 155 bytes) y su cadena de 3 URLs.

Actualizar un pin exige: verificar el nuevo artefacto, comprobar que los mirrors lo sirven idéntico, y actualizar el SHA-256, el tamaño y las URLs juntos. Un pin que no verifique no debe enviarse.

## Cambios en el servidor

- `InstallRepo` clona/descarga con cadena de candidatos: upstream primero, mirrors después. La fuente realmente usada queda registrada en `.ps5hs-source.json` (`mirrorRepository`), de modo que cada toolchain conserva su procedencia auditable.
- `GetStatus` expone `toolchainHealth`: pins cargados y estado del pack (presente / verificado / bytes / ruta), más `upstreamUnavailable` y `mirrorAlternatives` por cada entrada del catálogo. El panel SDKs y el dock lo muestran (`LOCAL · UPSTREAM CAÍDO`, `MIRROR DISPONIBLE`, `PACK SDK OK/AUSENTE`).
- En cada build opengl-ui, antes de compilar, el IDE:
  1. aplica (si el desarrollador autoriza `allowUpstreamSdkMirrorPatch`) el parche de cadena de mirrors a `tools/fetch-opengl-sdk.sh` — reescritura mínima, idempotente, con marca `# PS5HS_MIRROR_CHAIN`, registro SHA-256 antes/después en `.ps5hs-modifications.json`, y conservando intactos los pins de integridad del script;
  2. siembra el tarball del SDK desde el pack local en `.deps/ps5-opengl/` (verificación SHA-256 de origen y destino; la caché ya presente no se reescribe).

## Parche de mirrors: qué hace exactamente

`ApplyPS5HSSdkMirrorChainPatch` reescribe dos puntos de `tools/fetch-opengl-sdk.sh`:

- la línea `url="…blackbearreloaded…"` pasa a ser una cadena `urls=( upstream mirror1 mirror2 )`;
- la invocación única de `curl` pasa a ser un bucle que intenta cada URL y aborta con salida 2 si todas fallan.

Los `sha256sum` de verificación del tarball y del manifest interno del SDK no se tocan: cualquier mirror (o un upstream restaurado) que sirva un archivo distinto hace fallar el build con el mismo error que hoy. El parche falla cerrado: si el script upstream cambia de forma irreconocible, aborta sin modificaciones parciales y el build se detiene antes de descargar nada.

## `Build-ToolchainPack.ps1`

Consolida el material local en `toolchain-pack/`:

```
toolchain-pack/
  ps5-opengl-sdk/ps5-opengl-sdk-1.0.2.tar.gz   (verificado contra el pin)
  manifest.json                                  (origen, commit, licencias, tamaños)
```

Uso desde la carpeta del IDE: `powershell -ExecutionPolicy Bypass -File runtime\Build-ToolchainPack.ps1`. Opciones: `-SdkTarball <ruta>` para aportar un tarball ya descargado, `-OutputZip <ruta>` para un respaldo completo (toolchains + pack), `-Include <lista>` para acotar las carpetas. Si no hay tarball local, lo descarga probando la cadena de mirrors del pin y rechaza cualquier archivo que no verifique.

## Licencias

El IDE es MIT; los toolchains vendorizados son GPL-3.0-or-later (u otras). El vendoring es íntegro y no modificado: los árboles conservan sus `LICENSE`, `LICENSES/` y `THIRD_PARTY_NOTICES.md`, los orígenes quedan en `.ps5hs-source.json`, y cualquier ajuste del IDE a fuentes upstream pasa por la maquinaria de consentimiento y auditoría (`.ps5hs-modifications.json`) en lugar de parchear las copias canónicas. No se redistribuyen binarios de Sony ni firmware; componentes como `libc.prx` siguen siendo responsabilidad del usuario.

## Verificación

- `runtime/test-toolchain-pins.js`: contratos estáticos del manifiesto, los hooks del servidor, la política, la UI y el packer.
- `runtime/test-native-modification-policy.ps1`: niega por defecto, parchea con consentimiento, es idempotente, aborta con script irreconocible y audita SHA-256.
- La cadena real se comprobó en vivo contra los mirrors (upstream 404; LedyBacer y darkxex devuelven el mismo asset de 226 310 155 bytes; el tarball de LedyBacer verificado byte a byte contra el pin).

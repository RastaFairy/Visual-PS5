# Alcance y limitaciones — versión 1.1.0

Este documento establece qué funciones proporciona el IDE, qué depende de herramientas externas y qué no se debe asumir.

## Funciones disponibles

| Área | Qué ofrece | Condiciones/límites |
|---|---|---|
| Editor visual | Lienzo 1920×1080, posicionamiento, dimensiones, propiedades, jerarquía, pantallas y vista previa | La vista previa no es un emulador de PS5 |
| Modelo de proyecto | Crear, editar, guardar, abrir, analizar y exportar el modelo | El guardado principal requiere el servicio local; el respaldo en navegador es limitado |
| Flujos | Eventos y acciones visuales | No son un lenguaje de programación general; IDs y acciones deben existir |
| Recursos | Importación y referencia de imágenes | La importación no garantiza decodificación en el código nativo |
| Catálogo | 34 repositorios comunitarios en categorías diferentes | Un proyecto de referencia no siempre es plantilla compilable |
| OpenGL C++20 | Genera pantallas basadas en \`hui::app::Concept\`, flujos y texturas | Hasta 512×512 px por textura y 16 IDs únicos por pantalla |
| Vulkan/RADV C++20 | Integra pantalla y recursos en una plantilla Vulkan concreta | Requiere revisiones compatibles de renderer, Mesa/RADV y PS5_PayloadSDK |
| SharpProspero/C# | Usa pipeline C# upstream | Requiere SDK/.NET adecuados; payloads/plugins no son GUI intercambiables |
| Compilación | Ejecuta el pipeline real upstream y verifica artefactos | Exige toolchain y herramientas del host |

Acciones visuales documentadas: \`notify\`, \`setText\`, \`toggleVisibility\`, \`setValue\`, \`changeColor\` y \`navigate\`. Su disponibilidad depende de componente, evento y backend. El teclado de los controles de entrada es ASCII básico: A–Z, números, puntuación básica, espacio, borrar, limpiar, aceptar y cancelar.

## Lo que no hace

- No es un SDK oficial ni un producto avalado por Sony.
- No desbloquea ni hace jailbreak a una consola, modifica firmware, elude autenticación ni instala automáticamente aplicaciones en PS5.
- No contiene firmware, claves, juegos, BIOS ni archivos propietarios de Sony.
- No compila por sí solo sin las toolchains y dependencias exigidas por cada plantilla.
- No convierte cualquier juego, programa C# o aplicación arbitraria a código nativo portátil.
- No genera un juego completo desde un dibujo: el generador cubre la capa visual/UI que implementa el contrato del kit seleccionado.
- No proporciona emulación exacta, profiling de hardware real ni compatibilidad garantizada con todas las versiones de firmware.
- No incluye un teclado multilingüe del sistema ni IME; el teclado nativo es ASCII básico.
- No garantiza que audio, vídeo, JSON o binarios importados se puedan consumir automáticamente desde la aplicación nativa.
- No garantiza que un repositorio tercero siga disponible, sea compatible o compile en el futuro.
- No proporciona auditoría formal de seguridad, verificación automática de licencias ni asesoramiento jurídico.
- La validación de la CI y una prueba en hardware físico son cosas distintas. El mantenedor confirmó posteriormente una prueba específica de empaquetado .ffpfsc en una PS5 real; no equivale a validar todos los títulos, firmwares, backends o funciones del IDE.

## Qué significa «compilación correcta»

El IDE exige que el proceso upstream termine con código cero y que se encuentre un artefacto verificable (por ejemplo \`eboot.bin\` o un ZIP). Esto solo demuestra que el pipeline produjo un artefacto según esos criterios. No prueba que arranque en hardware, que todas las pantallas funcionen, ni la compatibilidad con cada firmware.

## Estados prácticos

- **Sin SDK:** se puede editar, guardar y analizar el modelo y ejecutar las pruebas del generador con Node.js.
- **Fuentes presentes, toolchain incompleta:** se puede generar código, pero la compilación real fallará hasta completar los requisitos.
- **Build satisfactorio:** hay un artefacto verificable; aún hacen falta pruebas separadas.
- **Prueba en consola:** debe documentarse con firmware, entorno, revisiones, pasos y evidencias reproducibles.

El catálogo apunta a terceros cuyas ramas, dependencias y licencias pueden cambiar. Registra sus commits, revisa licencias/avisos upstream y comprueba la compatibilidad antes de distribuir software.

## Validación comunicada por el mantenedor — 16 de octubre de 2026

Se informó de que un título empaquetado como .ffpfsc funcionó en hardware real. Es una prueba concreta del artefacto y el entorno utilizados; no debe interpretarse como compatibilidad universal ni como prueba de todos los backends o firmwares.

# Generación visual nativa: OpenGL y Vulkan

PS5 Homebrew Studio admite dos rutas para generar una pantalla desde el lienzo. Ambas producen C++20 y mantienen el proyecto nativo como una carpeta independiente en `Documentos/PS5HomebrewStudio/Projects`.

## Runtime autónomo y propiedad de la entrada · 1.1.10

En los títulos OpenGL generados desde el lienzo, runtime/native-runtime.ps1 aplica el perfil standalone-native-ui-v1 antes de compilar:

- elimina del shell las acciones de galería reservadas para L1/R1 y Touchpad;
- pasa el InputFrame completo a la pantalla generada, sin enmascarar pressed, released ni held;
- desactiva la composición del banner, HUD y panel informativo del shell;
- registra la política en .ps5hs-native-runtime.json para auditoría.

El perfil se aplica al generar títulos nuevos y al compilar proyectos visuales OpenGL anteriores reconocidos por el IDE. Si los puntos de integración no coinciden con el código upstream, el IDE falla de forma cerrada y no lanza el build. No aplica el parche a proyectos de galería genéricos importados.

Esta integración controla la política de la aplicación y el enrutamiento de entrada; renderer y componentes gráficos siguen siendo dependencias de código fuente upstream. La ruta Vulkan usa el programa UI directo de PS5_VulkanTemplate; su salida al mantener OPTIONS permanece como comportamiento de la plantilla.

## Flujo de uso

1. Añade componentes en el lienzo configurable (inicia en 1920×1080) y configura sus propiedades.
2. Define los flujos que responderán a `start`, `activate` y `change`.
3. En **Destino**, elige `Native UI · OpenGL 4.6 / C++20` o `Native UI · Vulkan / RADV / C++20`.
4. Pulsa **Compilar**, especifica el nombre y el `TITLE_ID` y confirma.
5. El servidor crea un título desde el repositorio upstream, inserta la pantalla, ejecuta el pipeline real y muestra el log. Si falla, el proyecto creado se conserva y la salida identifica el paso que falló.

El nombre debe usar entre 1 y 40 caracteres ASCII; el `TITLE_ID` debe seguir el formato `PPSA12345`. El generador upstream rechaza IDs reservados o directorios que ya existan: no se sobrescriben proyectos anteriores.

## Contrato generado

La pantalla generada implementa `hui::app::Concept`: `info()`, `enter()`, `update()` y `draw()`. El generador mapea las posiciones y dimensiones del proyecto al espacio virtual de UI de 1920×1080 que usa el toolkit. Después, los renderers OpenGL y Vulkan ajustan ese espacio a las dimensiones reales de la superficie activa, manteniendo la proporción; 1920×1080 es el sistema lógico de coordenadas, no un límite físico de salida. El backend Vulkan obtiene el tamaño del swapchain y OpenGL consulta la superficie EGL de VideoOut, por lo que pueden presentar a 1080p, 1440p o 4K cuando el modo de pantalla está disponible.

Los flujos soportados se traducen así:

- `notify`: muestra el mensaje en la barra de estado.
- `setText`: actualiza la etiqueta del componente de destino.
- `toggleVisibility`: alterna la visibilidad.
- `setValue`: cambia el valor numérico, el estado booleano o la selección dentro de sus límites.
- `changeColor`: cambia el fondo de la pantalla.
- `navigate`: cambia la pantalla activa y reconstruye el foco.

La navegación por cruceta recorre los controles interactivos visibles de la pantalla activa. Izquierda/derecha ajustan sliders, steppers y listas/selectores; confirmar activa el componente; atrás actualiza el estado del control de interfaz. El cierre de la aplicación se conserva en el shell upstream.

## Imágenes y campos de texto

### OpenGL

Las imágenes que se encuentran vinculadas a un widget se decodifican con Canvas 2D en el navegador antes de enviarse al servicio. El navegador las convierte a RGBA8, preserva el canal alfa y limita sus dimensiones a un máximo de 512×512. El paquete guarda los píxeles y dimensiones en `assets/ps5hs/<id>.rgba`; el manifiesto contiene dimensiones y SHA-256. El título sube esos bytes a una textura OpenGL mediante `glTexImage2D`. Se permiten hasta 16 recursos de textura únicos; los widgets que comparten el mismo ID comparten la textura.

La reducción a 512×512 es intencionada para mantener un límite de memoria predecible. Si la imagen no se decodifica, el archivo no existe o supera las comprobaciones, el widget muestra un marcador en lugar de una textura ficticia.

### Vulkan / RADV

Las imágenes se guardan como RGBA8 con cabecera de dimensiones. En la preparación del título Vulkan, el IDE registra los recursos locales en `ps5/assets.json`, añade un aviso de licencias para recursos aportados por el usuario, los empaqueta bajo `/app0/assets/ps5hs/` y carga sus píxeles a través de `VkRenderer::create_texture`. La pantalla consulta un registro de handles Vulkan y dibuja la misma UV rectangular que la ruta OpenGL. No se usa `glTexImage2D` dentro del backend Vulkan.

### Campos de texto

El widget `input` abre un teclado en pantalla propio, navegable con la cruceta. Permite A–Z en mayúsculas, dígitos, puntuación básica, espacio, borrar, limpiar, aceptar y cancelar. Al aceptar actualiza el valor del campo y dispara el evento `change`. Es ASCII básico, no un IME multilingüe ni una integración con el servicio de texto del sistema.

## Toolchains y licencias

La ruta OpenGL se crea desde [ps5-homebrew-ui](https://github.com/blackbearreloaded/ps5-homebrew-ui), que depende de [ps5-opengl](https://github.com/blackbearreloaded/ps5-opengl). La ruta Vulkan se crea con [PS5_VulkanTemplate](https://github.com/mihawk-99/PS5_VulkanTemplate), que integra [PS5_Vulkan](https://github.com/mihawk-99/PS5_Vulkan), su fork PS5_Mesa y la revisión específica de PS5_PayloadSDK. Las dependencias se obtienen mediante los scripts upstream; no se construye un renderer alternativo dentro de SharpProspero.

El código de los kits UI está bajo GPL-3.0-or-later y mantiene los avisos y licencias de sus recursos. Revisa las licencias y `THIRD_PARTY_NOTICES.md` del checkout utilizado antes de distribuir un título.

## Pruebas

Con Node.js disponible:

```powershell
node --check app.js
node --check runtime/native-generator.js
node runtime/test-native-generator.js
```

Las pruebas cubren la generación de ambos backends, widgets, múltiples pantallas, literales escapados, teclado nativo, imágenes RGBA tanto OpenGL como Vulkan, normalización de progresos/gauges y flujos. En el entorno de preparación el fuente generado también se verificó sintácticamente con Clang contra interfaces de prueba que modelan el contrato `Concept/DrawList`. Esto no equivale a compilar con los SDK completos ni a probar una consola real.

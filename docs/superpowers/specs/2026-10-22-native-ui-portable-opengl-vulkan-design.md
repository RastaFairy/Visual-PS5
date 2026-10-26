# UI nativa portable entre OpenGL y Vulkan

**Estado:** propuesta para revisión del usuario  
**Fecha:** 2026-10-22  
**Proyecto canónico:** `C:\Visual-PS5`

## Objetivo

Permitir que un desarrollador escriba una pantalla nativa C++20 propia y pueda compilar esa misma fuente, en ejecuciones de compilación separadas, para los destinos OpenGL o Vulkan. El desarrollador debe poder cambiar el backend sin perder su fuente ni duplicar la lógica de interfaz.

El modo visual existente seguirá disponible. La UI personalizada será una modalidad independiente del código visual generado, de modo que el modelo de componentes se conserve aunque el proyecto compile temporalmente la fuente personalizada.

## Estado actual observado

- Los dos kits de UI ofrecen `hui::app::Concept`, `hui::app::Context`, `hui::app::Frame`, `hui::InputFrame` y `hui::gfx::DrawList` con una forma común suficiente para servir de base al contrato.
- El generador nativo ya implementa la pantalla visual sobre `Concept` y `DrawList`, pero añade ramas específicas de backend para cargar imágenes y registrar la fábrica. Véase `runtime/native-generator.js`.
- El selector de backend desactiva el modo de código manual y vacía `customCode`; por tanto, cambiar de OpenGL a Vulkan puede descartar código editado. Véase `app.js`.
- El servidor exige nombres de fábrica diferentes en cada destino. Véase `runtime/server.ps1`.
- La guía de generación visual describe actualmente el contrato compartido y sus diferencias en `docs/NATIVE_VISUAL_BACKENDS.md`.

Estos hechos permiten reaprovechar la base actual, pero no demuestran por sí solos que todos los detalles de los dos kits vayan a permanecer sincronizados. La nueva capa debe verificar su contrato y fallar de forma explícita si un kit deja de cumplirlo.

## Decisión de arquitectura

El IDE ofrecerá una fuente C++ de pantalla independiente del modelo visual y una fachada pública del IDE para las capacidades portables. El código del desarrollador se compilará sin depender de cabeceras ni identificadores de OpenGL o Vulkan.

Cada destino tendrá un adaptador generado por el IDE que:

1. conecta la pantalla con el contrato `Concept` de la plantilla correspondiente;
2. registra la fábrica de pantalla que espera esa plantilla;
3. resuelve los recursos portables, incluidas las imágenes, sin exponer handles gráficos nativos;
4. conserva el pipeline upstream de compilación y empaquetado.

El desarrollador seleccionará OpenGL o Vulkan en cada compilación. La misma fuente portable se usará para ambas. El objetivo no es producir un único binario que cambie de renderer durante la ejecución.

La fachada v1 cubrirá ciclo de vida de pantalla, entrada lógica de DualSense, dibujo 2D común, texto, tema y acceso a recursos del proyecto. No incluirá el renderer, los handles GPU ni las APIs nativas de cada backend. La fachada podrá apoyarse internamente en `hui::app::Concept` y `hui::gfx::DrawList`, pero esos detalles upstream no serán la interfaz que el IDE prometa a los proyectos.

## Modelo de proyecto y edición

El formato de proyecto pasará de v2 a v3 e incorporará una sección independiente de `customCode` y `manualCode`:

```json
"nativeUi": {
  "mode": "visual",
  "source": "",
  "scope": "portable",
  "backend": null,
  "contractVersion": 1
}
```

`mode` será `visual` o `custom`; `scope` será `portable` o `backend-specific`. En alcance portable, `backend` debe ser `null`; en alcance específico debe ser `opengl-ui` o `vulkan-ui`. El analizador rechazará combinaciones incoherentes y el servidor repetirá la comprobación antes de crear un título. `customCode` y `manualCode` conservarán su uso actual para los otros destinos.

La pestaña Código permitirá elegir entre la pantalla visual generada y la pantalla personalizada. Editar una no sobrescribirá la otra. Cambiar entre OpenGL y Vulkan conservará ambas. En modo visual se compila el modelo de componentes y sus flujos; en modo personalizado se compila el fuente propio y su comportamiento pertenece al desarrollador. Los componentes y flujos visuales permanecerán guardados, pero no se ejecutarán en modo personalizado. La interfaz identificará claramente cuál modo se está compilando.

Una fuente personalizada portable podrá compilarse en cualquiera de los dos destinos. Una fuente marcada como específica solo podrá compilarse con el backend asociado. Si el destino no coincide, el IDE conservará la fuente y mostrará un diagnóstico bloqueante claro.

### Contrato C++ portable v1

El paquete de proyecto incluirá el encabezado público `ps5hs/ui.hpp`, proporcionado por el IDE. La fuente del desarrollador implementará `ps5hs::ui::Screen` y definirá el punto de entrada único:

```cpp
std::unique_ptr<ps5hs::ui::Screen>
ps5hs_create_screen(ps5hs::ui::Context& context);
```

La fachada declarará `ps5hs::ui::Screen` con destructor virtual, `on_enter()` opcional y `update(const InputFrame&, float dt)` y `draw(Canvas&) const` requeridos. El punto de entrada devolverá una instancia de esa clase mediante el tipo exacto mostrado arriba. `Context` expondrá el tema, las fuentes, el catálogo de recursos y las métricas del proyecto. `Canvas` ofrecerá entrada lógica de DualSense (acciones, dirección, sticks, triggers y estado de conexión), dimensiones del lienzo y operaciones comunes de dibujo: rectángulos, gradientes, bordes, líneas, círculos/arcos, texto, imágenes identificadas por recurso del proyecto, recorte, transformaciones y opacidad. El tamaño lógico se consultará desde `Canvas`; y procederá de la resolución configurable del proyecto, con 1920×1080 como valor inicial. El contrato no expondrá bits físicos del mando, nombres de fábrica upstream, identificadores de textura, handles GPU ni APIs de OpenGL/Vulkan.

El IDE generará un adaptador por destino que envuelve esa pantalla en `hui::app::Concept`, traduce el lienzo a `hui::gfx::DrawList`, resuelve los recursos y proporciona la fábrica que espera la plantilla. El código del desarrollador no incluirá ni definirá fábricas por backend. El contrato v1 aceptará un fuente principal; la inclusión de archivos adicionales y un gestor de proyecto multiarchivo quedan fuera de esta etapa.

La compilación personalizada usará el fuente del usuario y el adaptador generado. No requerirá que el texto contenga un nombre concreto de clase, fábrica upstream o un tamaño mínimo arbitrario. El compilador y el pipeline del backend serán quienes informen de errores de C++ e integración.

## Migración sin pérdida

Al importar proyectos antiguos:

- Los proyectos visuales sin código manual se migrarán al modo visual.
- En un proyecto OpenGL/Vulkan v1/v2 con `manualCode=true`, el contenido de `customCode` se conservará como fuente personalizada específica del backend actual. No se etiquetará automáticamente como portable porque podría incluir APIs o fábricas específicas.
- En otros backends se mantendrá el significado existente de `customCode` y `manualCode`.
- La migración no borrará ni regenerará fuente personalizada. Si un dato es ambiguo o inválido, se conservará y se informará del problema en vez de sustituirlo silenciosamente.

## Flujo de compilación y exportación

1. El usuario elige el modo visual o personalizado.
2. En modo personalizado, edita una única fuente C++ que implementa la fachada del IDE.
3. Selecciona OpenGL o Vulkan al guardar el destino de compilación.
4. El IDE valida el modo, el alcance y la disponibilidad de recursos; genera el adaptador para ese destino; e inyecta ambos en la plantilla upstream existente.
5. El pipeline upstream compila y el IDE verifica el artefacto con las comprobaciones que ya exige ese pipeline.
6. Guardar y exportar conservan el modelo visual, la fuente personalizada, los recursos y los metadatos del destino.

Si la compilación falla, el proyecto y ambas fuentes permanecen disponibles para corrección. El IDE no afirmará que una fuente es portable basándose solo en que se haya guardado o generado correctamente: la afirmación depende de compilarla con cada backend objetivo.

## Compatibilidad y límites de v1

Incluido:

- UI personalizada C++20 para OpenGL y Vulkan con una fuente portable común.
- Adaptadores de integración por backend dentro del IDE.
- Persistencia, importación, exportación y diagnóstico del modo personalizado.
- Compatibilidad de carga con proyectos anteriores, conservando código manual.

Fuera de alcance:

- Cambiar de renderer en ejecución dentro de un mismo binario.
- Añadir backends personalizados de SharpProspero, PS5SDK, payload, PS5Link o etaHEN.
- Implementar un sistema general de plugins visuales o una extensión multiarchivo arbitraria.
- Modificar o reemplazar el código fuente upstream de las toolchains.
- Rediseñar el lienzo, permitir dimensiones lógicas configurables o añadir nuevas familias de controles visuales. La capa portable deberá evitar depender de nombres de fábrica por backend, pero el tamaño actual del lienzo no cambia en esta etapa.
- Garantizar que cualquier fuente C++ arbitraria compile en ambos destinos. Solo se considerará portable la fuente que use la fachada común y no dependa de APIs específicas.

## Criterios de aceptación

1. El proyecto v3 guarda por separado el modelo visual, los flujos y la fuente personalizada; la interfaz deja claro cuál modo compila.
2. Cambiar de OpenGL a Vulkan o volver no borra ni modifica la fuente personalizada.
3. Una pantalla mínima escrita una vez contra la fachada puede compilarse para ambos destinos sin cambios en su fuente.
4. Cada build incluye el adaptador correcto de fábrica y de recursos sin exigir al usuario ramas `#ifdef` de OpenGL/Vulkan.
5. Una fuente marcada como específica de backend bloquea el destino incorrecto con un diagnóstico y sigue intacta.
6. La importación de proyectos antiguos conserva el código manual existente y no lo declara portable sin intervención explícita.
7. Los errores de compilación mantienen el proyecto recuperable y no se presentan como compilación satisfactoria.
8. Los cambios se limitan a la aplicación, su fachada, el formato del proyecto, el generador/adaptadores y la integración del servidor; no alteran los repositorios upstream de toolchain.

## Riesgos y respuesta

- **Deriva entre kits:** el contrato compartido puede cambiar en una plantilla. El adaptador tendrá una versión definida y la comprobación de compatibilidad fallará de forma explícita antes de presentar una compilación como válida.
- **Código manual antiguo ligado a un backend:** se conservará como específico del backend actual y no se prometerá que compila en el otro.
- **Confusión entre modo visual y personalizado:** la UI indicará cuál de las dos fuentes se compila y mantendrá la otra guardada.
- **Recursos con representación distinta:** la fachada expondrá identificadores y operaciones portables; los adaptadores mantendrán oculto el registro de textura de cada renderer.

## Validación prevista

Antes de considerar la implementación terminada se deberá comprobar la migración y persistencia del proyecto, que la misma fuente llegue sin alteraciones a ambos pipelines, que cada adaptador registre la fábrica esperada, y que los diagnósticos de incompatibilidad y de compilación fallida preserven el trabajo del usuario. La compilación con cada toolchain y la validación en consola son evidencias distintas; una no sustituye a la otra.



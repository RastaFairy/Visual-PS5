# Flujo Vulkan Compute

El IDE tiene un espacio de trabajo independiente para editar un grafo ordenado de pases Vulkan Compute. Cada pase contiene una fuente GLSL 450, dimensiones lógicas, tamaño de grupo local y bindings de imágenes `storage-image`. El destino permite cambiar ancho y alto; los recursos y despachos que todavía seguían el tamaño anterior se ajustan al nuevo.

## Qué hace Compilar SPIR-V

1. Valida en el navegador y de nuevo en el servicio local los IDs, tamaños, referencias, lecturas sin productor, bindings y límites de despacho.
2. Solicita consentimiento para escribir un workspace nuevo y ejecutar el `glslangValidator` que ya exista en la distribución WSL configurada.
3. Conserva el modelo en `compute-graph.json`, el grafo de ejecución en `compute-manifest.json` y una fuente `shaders/<passId>.comp` por pase.
4. Compila cada GLSL a `build/spirv/<passId>.spv` para Vulkan 1.2. Solo devuelve éxito si cada salida existe y contiene la cabecera SPIR-V válida; también registra su tamaño y SHA-256.

No descarga herramientas, modifica una plantilla upstream, crea un título instalable ni ejecuta shaders en una GPU. El resultado es una base reproducible para integrar los pases en la aplicación Vulkan del desarrollador. Para un título PS5 todavía hay que conectarla a una aplicación/runtime Vulkan compatible y compilar ese título por su flujo correspondiente.

## Informe de ejecución GPU

El panel importa JSON que siga [vulkan-compute-report.schema.json](vulkan-compute-report.schema.json). El informe debe identificar el grafo con `graphRevisionId`, cada fuente realmente ejecutada con su `shaderSha256`, el dispositivo, driver, runtime y una duración GPU por pase. La revisión cambia al editar shaders, recursos, bindings, dispatch o el orden; el IDE rechaza mediciones de una revisión anterior.

`psnrDb`, `ssim`, hashes de salida/referencia y memoria son opcionales. Si el runtime incluye los dos SHA-256 de imagen, el panel muestra si la salida es byte a byte idéntica a la referencia. PSNR y SSIM expresan comparación con pérdida y no sustituyen una validación visual o funcional apropiada al algoritmo. Los informes se comparan por tiempo total frente al informe anterior de la misma revisión.

La compilación SPIR-V no produce por sí sola un informe GPU. El runtime que integra el grafo debe medir tiempos con consultas Vulkan, validar los datos de salida y escribir un informe real con el esquema publicado. El IDE no inventa mediciones ni marca una prueba de hardware como realizada.

## Alcance de esta integración

El primer alcance es el flujo genérico Vulkan Compute: recursos, pases, GLSL, validación estática, SPIR-V y una interfaz para importar resultados medidos. No incluye todavía un dispatcher C++ PS5 común a todos los frameworks, ni perfiles ejecutables integrados para FSR4 o HelixSR. Esas integraciones requieren adaptar las APIs y los contratos de cada runtime; HelixSR además exige los artefactos locales indicados por su upstream y el IDE no los empaqueta.

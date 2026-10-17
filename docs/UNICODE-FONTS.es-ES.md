# Fuentes Unicode en PS5 Homebrew Studio 1.1.9

## Usar una fuente multilingüe

1. Abre **Recursos** y pulsa **Importar recurso**.
2. Importa una fuente TrueType con extensión `.ttf` (máximo 20 MiB). Las fuentes OTF/CFF no son compatibles con el horneador incluido.
3. En **Fuente Unicode para compilación nativa (TTF)**, selecciónala.
4. Compila con el destino **Native UI · OpenGL 4.6 / C++20** o **Vulkan / RADV**.

Durante la compilación, el IDE recopila los puntos de código de los textos del proyecto y de los mensajes integrados de la pantalla. El horneador upstream crea atlas SDF específicos y los seis estilos tipográficos nativos se generan a partir de la fuente elegida. La cobertura se valida: si la fuente no contiene un carácter necesario, la compilación falla indicando su codepoint, en vez de producir silenciosamente un glifo vacío.

Esto permite representar textos latinos y extendidos, cirílico, griego, japonés, chino simplificado/tradicional, coreano y otros caracteres **si la fuente seleccionada incluye esos glifos**. No se necesita un atlas universal con todos los caracteres Unicode.

## Límites y comportamiento

- La selección de fuente afecta al texto del juego nativo; no traduce la interfaz del propio IDE, que continúa en español.
- Solo se hornean los caracteres detectados al compilar. Los caracteres generados dinámicamente en tiempo de ejecución también deben estar incluidos o requerirán una nueva compilación con dichos caracteres presentes en el modelo.
- El teclado virtual generado por el IDE sigue usando teclas ASCII. No incluye un IME para composición japonesa/china/coreana.
- No se declara soporte completo para shaping complejo, ligaduras ni dirección de derecha a izquierda para árabe, persa, hebreo u otras escrituras RTL. Unicode permite almacenar sus cadenas, pero dibujarlas correctamente requiere un motor de shaping.
- Las fuentes personalizadas pueden cambiar la apariencia respecto a las seis tipografías originales: el mismo TTF se hornea para todos los estilos nativos para garantizar la cobertura de glifos.
- La fuente original y `codepoints.txt` se conservan en `.ps5hs-font-source/` dentro del proyecto nativo para reconstrucción local. El paquete final contiene atlas horneados, no redistribuye la fuente TTF original por separado.
- El IDE no concede derechos sobre una fuente. Comprueba su licencia antes de distribuir el juego.

Si no seleccionas una fuente personalizada, el proyecto conserva las fuentes y la cobertura que proporciona la plantilla upstream. La vista previa del navegador puede usar sus propias fuentes de respaldo y no garantiza por sí sola que el ejecutable de PS5 contenga todos los glifos.

# Editor visual de escenas de juego

La vista **Juego 3D** permite construir la distribución y ajustar la física, la cámara y la presentación sin escribir código de juego. El IDE genera el motor AGC reutilizable y conecta sus datos al título; el modo **Código manual** queda como opción avanzada separada.

## Crear el nivel

1. Selecciona el backend **ps5link · Título nativo**. La pestaña **Juego 3D** muestra la escena en una vista 3D orbitable y sus herramientas.
2. Usa **+ Plataforma** para añadir bloques. Selecciona un bloque en la lista o en la escena y arrástralo para moverlo en X/Z. Arrastra con el botón derecho para orbitar, usa **Mayús + botón izquierdo** para desplazar la vista y la rueda para acercar o alejar.
3. Ajusta nombre, X, altura Y, Z, ancho, fondo y color desde el inspector. Las propiedades se guardan en el modelo del proyecto al cambiar de campo.
4. Usa los botones de cámara para orbitar 45 grados, cambiar la altura de observación o restablecer la vista. Las transformaciones se calculan en el plano del mundo y se mantienen al cambiar la cámara.
5. Selecciona un bloque y marca **Usar como inicio**, **Cristal**, **Checkpoint** o **Meta**. El nivel necesita un inicio, al menos dos plataformas y una meta.
6. Ajusta velocidad, aceleración, impulso de salto, gravedad, límite de caída y altura del personaje en **Física y mando**.
7. En **Cámara y presentación**, modifica seguimiento, colores y si la victoria exige reunir todos los cristales. Estos valores se generan directamente desde el modelo visual.

## Objetos 3D y superficies de aterrizaje

Usa **＋ Malla 3D** o el panel **Componentes → Escena 3D → Malla 3D** para añadir cubos, cristales facetados, esferas, cilindros, conos o pirámides. Selecciona la malla en el lienzo o en la pestaña **Objetos 3D**; arrástrala para moverla en X/Z y edita forma, altura, dimensiones, giro y color en el inspector. Son mallas procedurales creadas por el motor AGC del IDE y se regeneran desde el modelo guardado; no son modelos de muestra enlazados desde la plantilla.

En **Colisión del objeto**, activa la caja sólida y ajusta las semidimensiones X/Y/Z y el desfase vertical. La caja bloquea los laterales y la cara inferior, y permite aterrizar encima. Puedes ajustar X/Z con los tiradores de la escena y Y desde el inspector. El colisionador sigue alineado con los ejes del mundo, aunque la malla se gire.

## Interfaz y acciones

Los componentes de **Diseño** también se integran en la interfaz nativa que consume el motor. En **Flujos**, enlaza botones e interruptores con acciones integradas: iniciar, pausar, continuar, reiniciar y activar o desactivar el sonido. El motor enlaza el DualSense con el control que selecciones; no hacen falta nombres de funciones ni código de juego escrito a mano. Cada acción admite un único control principal, y el análisis verifica que el tipo de control y su evento sean compatibles.

Los textos del lienzo pueden usar `{current}`, `{total}`, `{percent}` y `{state}` para mostrar cristales reunidos, total de cristales, avance de ruta o estado del sonido. El lienzo muestra una vista de ejemplo y la salida AGC sustituye esos valores durante la partida. Las instrucciones y mensajes que no dependen de un estado también se editan como componentes de texto, con posición, tamaño y color en el inspector. El editor muestra el mapa del mando junto a las propiedades de la escena. Desde el IDE se pueden ajustar el nivel, la interfaz, los flujos, las colisiones, la cámara, los colores y los parámetros de salto. El código generado se muestra en **Código** en modo de solo lectura para inspección; editarlo manualmente cambia explícitamente al modo avanzado.

## Integración AGC

Al guardar, exportar o compilar un proyecto ps5link en modo visual, el IDE genera `src/main.c` desde la plantilla reutilizable AGC, `src/ps5hs_game_scene.h` desde la escena y `src/ps5hs_visual.c` desde los componentes y flujos. La cabecera lleva plataformas, objetos, sus cajas sólidas configurables, objetivos, físicas, cámara, paleta, pantallas y controles. El backend rechaza llamadas C manuales en modo visual y no compila si la escena, los objetivos o sus conexiones no son válidos. Antes de reemplazar un `src/main.c` anterior, conserva una copia de seguridad dentro de `src/`.

La escena y los flujos son la fuente del proyecto visual; el renderer y la simulación son capacidades incluidas del IDE. El runtime compone una exploradora procedural con casco, visor, mochila, brazos y piernas animados; los cristales son mallas facetadas y la meta tiene un arco con núcleo giratorio. Al modificar los bloques, la geometría, las físicas o la presentación, la fuente generada cambia en consecuencia. El build sólo confirma una compilación válida cuando termina el pipeline y verifica el artefacto nativo.

## Alcance actual del editor

El backend actual es un editor visual especializado en plataformas 3D, no un motor general de propósito amplio como Unity. El editor admite plataformas y seis primitivas procedurales; aún no hay importación de modelos arbitrarios, animación esquelética, materiales PBR ni componentes de física de propósito general. Sus colisionadores son cajas alineadas con los ejes del mundo y no siguen el giro de la malla. Las primitivas se renderizan con geometría generada por el IDE en AGC y no usan los modelos de ejemplo de la plantilla.

## Colisión por bloque

Cada plataforma tiene una caja de colisión independiente de la malla visible: se puede activar o desactivar y ajustar su medio ancho X, medio grosor Y, medio fondo Z y desfase vertical. La vista 3D muestra el volumen punteado y mantiene los tiradores alineados con X/Z al orbitar; en rojo indica que la colisión está desactivada. El valor inicial del grosor es 0,45 unidades y la tolerancia horizontal añade 0,24 unidades a la malla. Los objetos 3D tienen por separado una caja sólida opcional con dimensiones X/Y/Z ajustables.

El análisis usa velocidad, impulso de salto, gravedad y las cajas de aterrizaje de plataformas y objetos para estimar la conectividad. Antes del build, el servidor vuelve a comprobar que el inicio, la meta, los cristales y checkpoints estén en el recorrido alcanzable. Es una comprobación geométrica de niveles y no sustituye la prueba de juego en PS5.

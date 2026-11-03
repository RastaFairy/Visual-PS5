# Corrección de arranque: PowerShell, línea 627

## Síntoma

PowerShell muestra: `La referencia de variable no es válida. ":" no va seguido de un carácter de nombre de variable válido`, señalando `$sourceName:` en `runtime/server.ps1`, función `SaveProject`.

## Causa

En una cadena expandible de PowerShell, el carácter `:` inmediatamente después de un nombre de variable puede interpretarse como parte de una referencia cualificada (por ejemplo `$env:PATH`). En este caso se pretendía imprimir el nombre del fichero y luego dos puntos.

## Solución aplicada

Cambiar:

```powershell
- $sourceName: $description
```

por:

```powershell
- ${sourceName}: $description
```

La llave de cierre delimita inequívocamente el nombre de variable. No cambia el texto resultante del README del proyecto.

## Aplicación manual

1. Cierra la instancia del editor.
2. Abre `runtime/server.ps1` con un editor de texto UTF-8.
3. Busca `$sourceName: $description` y sustitúyelo por `${sourceName}: $description`.
4. Guarda el archivo y ejecuta de nuevo `start.bat`.

No cambies otras referencias como `$script:Root` o `$script:Url`: esas son variables de ámbito de script válidas.

## Verificación

El cambio se ha aplicado al paquete reconstruido y las pruebas JS del generador siguen pasando. La comprobación mediante el parser oficial de PowerShell debe realizarse en Windows/PowerShell; no se afirma aquí que se haya ejecutado desde el entorno de preparación.

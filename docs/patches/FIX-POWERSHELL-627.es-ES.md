# Corrección de arranque: PowerShell, línea 627

## Síntoma
PowerShell informa de una referencia de variable no válida, con el cursor en `$sourceName:` dentro de `runtime/server.ps1`, función `SaveProject`.

## Causa
En una cadena expandible, un signo de dos puntos inmediatamente después de un nombre de variable puede interpretarse como una referencia cualificada (como `$env:PATH`). Aquí se pretendía escribir el nombre de un fichero seguido de dos puntos.

## Solución
Cambiar:

```powershell
- $sourceName: $description
```

por:

```powershell
- ${sourceName}: $description
```

Las llaves delimitan el nombre de variable sin alterar el texto generado.

## Aplicación manual
1. Cierra el editor.
2. Abre `runtime/server.ps1` en un editor UTF-8.
3. Busca `$sourceName: $description` y sustitúyelo por `${sourceName}: $description`.
4. Guarda el archivo y vuelve a ejecutar `start.bat`.

No modifiques otras referencias como `$script:Root` o `$script:Url`: son variables de ámbito de script válidas.

## Validación
El cambio se encuentra en el ZIP reconstruido asociado a esta entrega. Las pruebas del generador JavaScript pasan. La validación con el parser oficial de PowerShell debe hacerse en Windows/PowerShell; no se afirma que el parser de destino se ejecutase durante la preparación.

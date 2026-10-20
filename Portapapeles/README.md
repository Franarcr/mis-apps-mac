# Portapapeles

Historial del portapapeles para macOS (14+). Guarda los últimos **100** elementos copiados: texto, imágenes y archivos. Los elementos fijados se conservan aparte y no cuentan para el límite.

## Uso

- **⌥⇧V** abre el panel de historial (también desde el icono 📋 de la barra de menú).
- **⌥⇧⌘V** pega sin formato: solo el texto, sin tipos de letra, colores ni enlaces, para que tome el formato del lugar donde pegas (útil al copiar de una web a un correo o a un documento). Lo copiado queda guardado también sin formato.

| Tecla | Acción |
| --- | --- |
| Escribir | Buscar (sin distinguir mayúsculas ni tildes) |
| ↑ ↓ | Moverse por la lista |
| ↩ o doble clic | Pegar en la app donde estabas |
| ⌘1–⌘9 | Pegar directamente ese elemento |
| ⌘P | Fijar o desfijar |
| ⌘⌫ | Eliminar |
| Esc | Cerrar |

- El menú de la barra muestra las 10 últimas copias. También permite pausar la captura, borrar el historial (excepto lo fijado) y abrir la app al iniciar sesión.

## Permisos

- **Pegado automático:** necesita el permiso de **Accesibilidad**, que se activa desde el menú › *Activar pegado automático…*. Sin él, al pulsar ↩ (o ⌥⇧⌘V) el elemento solo se copia y tienes que pegarlo tú con ⌘V.
- **Lectura del portapapeles:** si macOS pregunta si Portapapeles puede leer lo que copias de otras apps, elige **Permitir siempre**.

## Privacidad

Se ignora lo que los gestores de contraseñas marcan como confidencial (`org.nspasteboard.ConcealedType`, 1Password…). El historial se guarda sin cifrar en `~/Library/Application Support/Portapapeles/`.

## Compilar

```bash
./build.sh    # compila e instala en /Applications (única copia)
```

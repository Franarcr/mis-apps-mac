# Cleaner (iPad) — contexto

Versión para el iPad de MacCleaner (`~/Documents/GitHub/mac-cleaner`), bundle `com.francho.cleaner`.
Lee `../CLAUDE.md` (reglas generales).

- Secciones: Estado, Limpiar fotos, Archivos grandes, Duplicados y Velocidad (prueba con Cloudflare).
- Muestra solo lo que de verdad ocupa espacio en el iPad, y en pantalla vertical (2ef4a9e).
- Fran confirmó que funciona.
- Instalar: `./instalar-ipad.sh`. Compila con `-destination id=<UDID>`, porque «iOS genérico» deja fuera al iPad
  del perfil y la app falla con «no fue posible verificar su integridad».
- La firma caduca a los 7 días.

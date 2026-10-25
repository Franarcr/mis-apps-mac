# Grabador

Graba imágenes de sistemas operativos (Raspberry Pi OS, Ubuntu, Home Assistant…) en memorias USB y tarjetas SD para que arranquen. Inspirada en balenaEtcher. Es una app normal con ventana (aparece en el Dock). Requiere macOS 14 o posterior.

## Cómo se usa

1. **Elegir imagen**: botón *Elegir imagen*, ⌘O, o arrastra el archivo a la ventana o al icono del Dock. Acepta `.img`, `.iso`, `.bin`, `.raw`, `.wic` y comprimidas `.zip`, `.gz`, `.xz` y `.bz2`. Las comprimidas se descomprimen al vuelo, así que no ocupan espacio extra. De un `.zip` se usa la imagen que lleva dentro.
2. **Elegir unidad**: conecta el USB o mete la tarjeta SD y aparecerá sola en la lista. Si solo hay una unidad válida, se elige sola. Junto a cada unidad se ve su tamaño, su conexión y lo que contiene, para reconocerla.
3. **¡Grabar!**: Grabador te pide confirmación, porque **se borra todo lo que hay en la unidad**. Después macOS pide la contraseña de administrador con su propio cuadro. Durante la grabación se ven el porcentaje, la velocidad y el tiempo que falta.

Al terminar, Grabador **verifica** la unidad: vuelve a leer lo grabado y comprueba que su huella SHA-256 coincide con la de la imagen. Después la **expulsa**, así que ya se puede quitar. Las dos casillas de abajo desactivan cualquiera de esos pasos.

## Seguridad

- **Solo aparecen unidades externas.** El disco interno del Mac y el disco desde el que arranca macOS no aparecen nunca, aunque arranques desde uno externo.
- Las unidades demasiado pequeñas para la imagen no se pueden elegir. Las de más de 64 GB llevan un aviso para que compruebes que es la correcta.
- Para escribir en la unidad se usa `authopen`, la herramienta de macOS para abrir dispositivos con permiso de administrador: la contraseña la pide el sistema y la app nunca la ve.
- Mientras se graba, Grabador impide que macOS monte las particiones que van apareciendo, para que no salga el aviso de «disco no legible».
- Las ISO sin tabla de particiones, como las de Windows, llevan un aviso: grabadas tal cual en un USB normalmente no arrancan.

## Para pruebas

```bash
# Unidades donde se podría grabar
/Applications/Grabador.app/Contents/MacOS/Grabador --unidades
# Graba y verifica en un ARCHIVO (nunca en un disco)
/Applications/Grabador.app/Contents/MacOS/Grabador --prueba imagen.img.xz salida.bin
# Mostrar también imágenes de disco montadas en la lista (para probar sin un USB real)
defaults write com.fran.grabador mostrarVirtuales -bool YES
```

El registro está en `~/Library/Logs/Grabador/grabador.log`.

## Compilar

```bash
./build.sh
```

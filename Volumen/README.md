# Volumen

App de barra de menú para macOS (14.2+) que cambia el volumen de cada app por separado: por ejemplo, bajar la música sin bajar una videollamada.

- Desde el icono de la barra de menú aparecen las apps que están sonando (en negrita) y las que tienen un volumen cambiado, cada una con su deslizador: de **silencio** a **150 %**. Cerca del 100 % el deslizador se queda justo en 100.
- Recuerda el volumen de cada app: la próxima vez que suene, se aplica solo.
- *Restablecer todo al 100 %* devuelve todas las apps a su volumen normal. Al salir de Volumen, también.
- Las apps al 100 % no se tocan: su sonido va directo a los altavoces, como siempre.
- Si cambias de salida (por ejemplo, conectas auriculares), el sonido de las apps con volumen cambiado pasa a la nueva salida.
- Safari, Chrome y otras apps que reproducen desde procesos auxiliares se muestran con su nombre.

## Permisos

La primera vez que cambies un volumen, macOS pide permiso para **grabar el audio del sistema**. Volumen lo necesita para captar el sonido de la app y volver a enviarlo con otro volumen; no graba ni guarda nada. Si lo deniegas, la app cuyo volumen cambiaste queda en silencio: actívalo desde el menú › *Permiso de audio del sistema…* (Ajustes del Sistema › Privacidad y seguridad › Grabación de pantalla y audio del sistema) o vuelve a ponerla al 100 %.

## Cómo funciona

Usa los *taps* de audio de macOS 14.2: el tap capta el sonido de los procesos de la app y lo silencia en la salida normal, y un dispositivo agregado privado (la salida actual más el tap) lo vuelve a reproducir con el volumen elegido. El procesado del sonido está en Objective-C, en `Sources/CoreAudioTaps`.

## Compilar

```bash
./build.sh    # compila e instala en /Applications
```

La primera vez, `build.sh` genera el icono con [../iconos/crear-icono.swift](../iconos/crear-icono.swift).

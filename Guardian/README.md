# Guardián

App de barra de menú para macOS (14+) que vigila quién entra a tu Mac por AnyDesk y revisa si los
programas instalados son de fiar. Solo lee: nunca cambia la configuración de AnyDesk ni borra nada.

- **Conexiones de AnyDesk…**: cada equipo que se conectó, cuántas veces, cuándo y cómo (aceptada
  en pantalla, con la contraseña o con un acceso guardado), y si entró desde tu misma red (casa u
  oficina) o desde fuera. Marca como **de confianza** los equipos que reconoces y ponles nombre.
- **Aviso al instante**: cada vez que alguien entra llega una notificación; si el equipo no es de
  confianza, el aviso es urgente y el icono de la barra se pone rojo. También avisa al cerrarse.
- **Cortar ahora**: corta la conexión cerrando AnyDesk por completo (pide confirmación).
- **Programas instalados…**: la firma de cada app de Aplicaciones (de Apple, de la App Store,
  desarrollador verificado, hecha por ti, sin revisión, sin firma o firma rota), qué permisos puede
  pedir (cámara, micrófono, controlar otras apps), cuáles dan acceso remoto y cuáles arrancan solas.
  También avisa si están encendidos *Compartir pantalla* o *Sesión remota (SSH)* de macOS.

Los equipos de confianza se guardan en las preferencias de la app (`com.fran.guardian`).

## Compilar

```bash
./build.sh    # compila e instala en /Applications
```

Pruebas sin abrir la app (solo leen):

- `Guardian --conexiones`: resumen de quién entró por AnyDesk y si hay alguien conectado.
- `Guardian --programas`: programas para revisar y los que arrancan solos.
- `Guardian --captura <carpeta>`: dibuja las dos ventanas en PNG.

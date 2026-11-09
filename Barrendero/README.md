# Barrendero

App de barra de menú para macOS (14+) que limpia el correo de Mail cada semana con tus reglas:
publicidad, boletines, redes sociales, avisos de inicio de sesión del BN y el correo no deseado.

- **Revisar ahora…**: busca en las bandejas de entrada de todas las cuentas lo llegado desde la
  última limpieza y muestra la lista agrupada por remitente para confirmar. Lo que se mueve va a la
  **papelera** de cada cuenta, así que se puede recuperar.
- **Cada semana** (por defecto el lunes a las 9:00): revisa sola y te avisa con la lista para
  confirmar. Si desmarcas *Preguntar antes de mover a la papelera*, barre sin preguntar y avisa.
  Solo lo hace con Mail abierto: no lo abre por su cuenta.
- **Barrer siempre al remitente del correo seleccionado en Mail**: selecciona en Mail un correo de
  publicidad y elige esta opción para agregar su remitente a las reglas.
- **Reglas…**: remitentes que se barren, avisos que solo se barren por asunto (p. ej. «Inicio de
  sesión» del BN, pero no sus comprobantes), excepciones que nunca se barren (Poder Judicial,
  Hacienda, avisos de seguridad) y si se vacía el correo no deseado.
- Solo lee remitente, asunto y fecha; nunca el contenido de los correos. No envía nada.

Las reglas iniciales son las de la limpieza de noviembre de 2026 y quedan en
`~/Library/Application Support/Barrendero/reglas.json`.

La primera vez macOS pide permiso para que Barrendero use Mail (*Privacidad y seguridad →
Automatización*).

## Compilar

```bash
./build.sh    # compila e instala en /Applications
```

Prueba sin abrir la app (no mueve nada): `Barrendero --revisar 7` muestra qué barrería de los
últimos 7 días.

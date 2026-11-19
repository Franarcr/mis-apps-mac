# Mascota — contexto

App del Mac (`com.fran.mascota`) con **Tuqui, un tucán** que vive en la pantalla. Lee `../CLAUDE.md` (reglas generales).

- Camina por el borde de abajo y encima de las ventanas, y vuela para subirse a ellas.
- Si le mueves la ventana donde está, se cae.
- Duerme cuando no usas el Mac y «trabaja» cuando tecleas mucho.
- Tras 60 min seguidos de uso pide una pausa. Se cambia con la preferencia `minutosPausa`, y la cuenta vuelve a
  cero tras 5 min sin tocar el Mac.
- Menú en la barra (huella): mostrar o esconder, traerlo aquí y abrir al iniciar sesión. Tiene `BarraLink.swift`.
- Código: `Pet.swift` (estados y física), `PetView.swift` (dibujo) y `AppDelegate.swift` (menú).
- Compilar: `./build.sh` → `/Applications/Mascota.app`.
- El archivo `Height` es una imagen PNG con nombre raro, quizás guardada por error. Preguntar a Fran antes de borrarlo.

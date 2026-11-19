# Vitrina — contexto

App del Mac (`com.fran.vitrina`) para **instalar las apps caseras en otro Mac** (0eb8f62, a23850f).
Lee `../CLAUDE.md` (reglas generales).

## Cómo funciona

- `build.sh` compila Vitrina y mete dentro las apps caseras instaladas en este Mac.
  - `./build.sh --dmg` crea además `../dist/Vitrina.dmg` para llevarla a otro Mac.
  - Las apps no instaladas se compilan para el DMG.
- `Catalog.swift` describe cada app: para qué sirve, dónde vive y qué permisos pide. Al añadir una app casera
  nueva hay que agregarla aquí.
- En el otro Mac, Vitrina marca las apps que faltan o tienen versión nueva y las copia ella misma, para que macOS
  no pida «Abrir igualmente» en cada una. Al terminar dice qué falta hacer en cada app (permisos).
  - No ofrece una app si la instalada es más reciente.
- **Apps de Elena:** MacCleaner y Suite Notarial (`local.elena.*`). Si no están instaladas, se toman ya
  compiladas de `~/Documents/IA/Claude/Elena/mac-cleaner` y `.../Elena/suite-notarial`.
- `icono-de-app.swift` guarda en PNG el icono de una app para mostrarlo en la lista.

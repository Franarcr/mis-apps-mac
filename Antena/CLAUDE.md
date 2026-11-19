# Antena — contexto

App del Mac (`com.fran.antena`): **analizador de redes Wi-Fi** al estilo WiFi Explorer (3603a5f).
Lee `../CLAUDE.md` (reglas generales).

## Qué hace

- `Scanner.swift`: escanea cada pocos segundos, guarda el historial de señal y avisa de cambios. Las redes que
  dejan de verse se olvidan pasado un rato.
- `Network.swift` e `InfoElements.swift`: datos de cada punto de acceso.
  - Lee canal, ancho, generación y modos de los elementos de información de las balizas.
  - macOS solo mide el ruido del canal de la red conectada; si no hay medida vale −999.
- `ChartsView.swift`: gráficos por canal, con cada red como un trapecio de su ancho y su señal. En 2,4 GHz un
  canal de 20 MHz ocupa unos 22 MHz.
- `Sidebar.swift`: agrupa por nombre, canal, ancho, etc., y muestra una franja con la red conectada.
- `Vendors.swift`: fabricante según la MAC, con la lista del IEEE en `Resources/fabricantes.tsv`.
  - Para regenerarla: `Antena --fabricantes salida.tsv oui.csv mam.csv oui36.csv`, con los CSV del IEEE.
- Necesita el permiso de **Ubicación** para ver los BSSID. Sin él, las filas no se pueden seguir entre escaneos.

## Compilar

`./build.sh` → `/Applications/Antena.app`.

# Agente de cobros de Naret

Resume los avisos de cobro del Condominio Freses (Naret) que llegan a Mail
cada inicio de mes: monto, fecha límite, período y qué se cobra.

## Piezas

- `cobros_naret.py`: lee Mail (cuenta Google, `facturacionifreses@naret.cr`),
  saca los datos del XML y el PDF adjuntos, crea un recordatorio «Pagar Naret…»
  y escribe la nota «Cobros Naret» con cada cobro en ⏳ PENDIENTE o ✅ PAGADO.
  - `--estado`: solo revisa Recordatorios y actualiza PAGADO/PENDIENTE en la nota.
  - `--sin-guardar`, `--solo FTxxxx`: para pruebas.
- `pdftxt.swift`: saca el texto del PDF (`swiftc -O pdftxt.swift -o pdftxt`).
- `recordatorios.swift`: lee y crea los recordatorios sin abrir la app Recordatorios
  (EventKit). La primera vez macOS pide permiso para ver los recordatorios.
- `tarea-programada.md`: instrucciones de la tarea de Claude `cobros-naret`
  (8:00 a. m., del día 1 al 7 de cada mes).
- `com.fran.naret-pagos.plist`: revisor que corre cada hora (`--estado`).

## Instalación

El programa corre desde `~/Library/Application Support/NaretCobros/`, porque
macOS no deja que un programa automático lea `~/Documents`.

```bash
mkdir -p ~/Library/Application\ Support/NaretCobros
cp cobros_naret.py pdftxt.swift ~/Library/Application\ Support/NaretCobros/
cp recordatorios.swift Info-recordatorios.plist ~/Library/Application\ Support/NaretCobros/
cd ~/Library/Application\ Support/NaretCobros && swiftc -O pdftxt.swift -o pdftxt
swiftc -O recordatorios.swift -o recordatorios -Xlinker -sectcreate -Xlinker __TEXT \
  -Xlinker __info_plist -Xlinker Info-recordatorios.plist
codesign -s - -f -i com.fran.naret-recordatorios recordatorios
cp com.fran.naret-pagos.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.fran.naret-pagos.plist
```

Los datos de los cobros (`historial.jsonl`, `procesados.txt`, `estados.json`)
no se guardan en git.

No paga nada, no entra a bancos y no responde correos: solo lee y avisa.

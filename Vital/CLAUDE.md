# Vital — contexto que no se puede perder

App de salud estilo Bevel para el iPhone de Fran (Costa Rica). Habla con él en español, simple y directo.
Lee esto entero antes de tocar recuperación, energía, estrés o entreno.

## Reglas de Fran (no negociables)

1. **Nada es absoluto ni inventado.** Cada número sale de sus datos (reloj, Salud, Bevel) o de un estudio
   citado. Si no hay base, se dice y se piden los datos; nunca se pone una meta inventada
   (p. ej. «la energía debe terminar en 20–30 %» fue rechazado).
2. **Meta de sueño: 7 h** (no 7,5). Los entrenos no duran 90 min fijos: los marca en el reloj.
3. **La recuperación de la mañana NO cambia en el día.** Solo cambia el anillo interno («ahora X»).
4. **Comparar con Bevel día a día antes de instalar** cualquier cambio de recuperación/energía.
5. Explicar en palabras simples y esperar un «sí» antes de construir algo nuevo.
6. No hacer commit ni push hasta que él confirme que funciona.

## Recuperación (Recovery.swift) — cómo funciona y por qué

- Solo usa **datos de la noche**: VFC (SDNN, en logaritmo, contra base de 21 días), **pulso medio dormido**
  (`sleepingHR`, no el «pulso en reposo» de Apple), sueño (resta hasta 5 si < 7 h), temperatura de muñeca,
  frecuencia respiratoria y SpO₂ (solo restan si salen de su rango).
- **Nunca usar `restingHR` de Apple para la recuperación:** Apple guarda una sola muestra al día y la reescribe
  hasta la noche. El 11 nov pasó a 72 lpm tras caminar y hacer elíptica, y la recuperación bajó de 67 a 51.
- La de hoy se **fija** una hora después de despertar (UserDefaults `recuperacionFijada2`). Antes de eso la
  tarjeta dice «Provisional: queda fija a las …».
- Fórmula actual: `58 + 14·z(ln VFC) − 8·z(pulso dormido) − sueño − temp − resp − SpO₂`.
- Valores exactos de Bevel que Fran dio (para recalibrar): **6 nov 60, 7 nov 57, 9 nov 70, 10 nov 49**.
  Vital da 60, 56, 70, 58. El 10 nov no cuadra con nada de la noche (pendiente: más días de Bevel).
- Pide a Fran sus números de Bevel cuando haga falta recalibrar; no ajustes «a ojo».

## Energía / estrés (Stress.swift)

- El anillo interno = recuperación × energía ahora / energía al despertar; nunca supera la de la mañana.
- Estrés: compara el pulso con su pulso en calma (mediana y percentil 75 de sus muestras sedentarias, 14 días).
- **Sin base todavía:** la energía inicial `35 + 0,65·recuperación` y el ritmo de desgaste. Para calibrarlos
  hacen falta valores de su Energy Bank de Bevel a varias horas. No inventar.

## Entreno (SessionView.swift, HealthWriter.swift, Routines.swift)

- No hay app de Vital en el reloj (el emparejamiento con Xcode falla). Para pulso y calorías reales, Fran debe
  iniciar «Fuerza tradicional» en la app **Entreno de Apple**; Vital une sus series a ese entreno.
- Sin entreno en el reloj, Vital guarda en Salud un entreno de fuerza con las kcal activas que el reloj midió
  en ese rato (bajas: el reloj muestrea poco sin entreno iniciado).
- La sesión se guarda en cada cambio (UserDefaults `sesionEnCurso` + SetLog al marcar); se puede retomar.
- Pirámide: el peso sale de su mejor serie de la última vez (Epley, 2 repeticiones en reserva). No se castiga
  hacer menos repeticiones con más peso.

## Comandos útiles

- Compilar: `xcodebuild -project Vital.xcodeproj -scheme Vital -destination 'generic/platform=iOS' -derivedDataPath /tmp/vitalbuild -allowProvisioningUpdates build`
- Instalar: `xcrun devicectl device install app --device 00008110-00011CE23C33801E /tmp/vitalbuild/Build/Products/Debug-iphoneos/Vital.app`
- Ver cálculos: `xcrun devicectl device process launch --device 00008110-00011CE23C33801E --console --terminate-existing com.francho.vital -- -depurar`
  (imprime `DIA`, `RECUP`, `DEP`, `FCR`, `ENTRENO`; el iPhone debe estar desbloqueado).
  Otros: `-fijar-recuperacion N`, `-traza-manana`, `-inicio-entreno HH:MM:SS`.
- Datos del iPhone: `xcrun devicectl device copy from --device 00008110-00011CE23C33801E --domain-type appGroupDataContainer --domain-identifier group.com.francho.vital --source "Library/Application Support" --destination <carpeta>`
- La firma (equipo personal CQNAH77456) caduca cada 7 días: hay que reinstalar.

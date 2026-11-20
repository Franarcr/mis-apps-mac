# Rockola (carpeta Kvlt) — contexto

Juego de trivia musical para el iPad. Empezó como «Kvlt» (metal extremo, a3a25b8) y pasó a «Rockola» (191450f):
misma carpeta y bundle `com.francho.kvlt`, nombre visible «Rockola». Lee `../CLAUDE.md` (reglas generales).

## Qué tiene

- 6 géneros: metal, rock clásico, pop, salsa, merengue, rock en español (`Questions.swift`, `GenreQuestions.swift`).
- Datos verificados de bandas reales. La escena de Costa Rica solo lleva preguntas que agregue Fran, porque no había
  datos comprobados: no inventar.
- Modos: solo, por turnos y duelo cara a cara; panel por jugador y tabla de posiciones (`Dashboard.swift`).
- Motor en `Engine.swift`, juego en `Play.swift`, estilo en `Theme.swift`.

## Conciertos (juego de ritmo con su guitarra)

- Tarjeta «Conciertos» en el inicio. Eliges jugador (o «Sin guardar»), guitarra, velocidad y riff; hay afinador.
- `Listener.swift`: micrófono con AVAudioEngine (modo `measurement`) y detección con YIN. Una nota empieza cuando
  sube el volumen de golpe o cambia la altura; solo se acepta una ventana que empiece después del golpe.
- `Concerts.swift`: guitarras (la Dean, −1 semitono), riffs originales (7 eléctricos y 3 «Desenchufado», que
  siempre usan la acústica), partida y `Store.saveConcert`. Acierto = nota exacta u octava, dentro del margen de
  la dificultad (0,25 / 0,2 / 0,16 s; +0,06 en acústica).
- Acordes: 0,16 s después de cada golpe se mira el espectro (8192 muestras) repartido en 12 notas y se compara con
  una plantilla del acorde esperado con armónicos (`Concert.chordMatches`, umbral 0,86). En pruebas sintéticas el
  acorde correcto da ≥ 0,89; se confunden pares casi iguales (Mi5/Mim, La5/Lam) y la tónica sola vale como power chord.
- `ConcertViews.swift`: menú, afinador y pantalla de juego (Canvas con las 6 cuerdas; el acorde es una barra con nombre).

## Instalar

`./instalar-ipad.sh`: aparta perfiles viejos, compila para el UDID del iPad, instala y abre (reintenta si está
bloqueado). La firma caduca a los 7 días.

## Ideas aprobadas pero sin empezar

1. **Demo Tape:** carrera de una banda inventada.

Sus guitarras: Yamaha tipo Strat HSS, Gretsch con dos humbuckers y Dean tipo Explorer con dos humbuckers, más una
acústica. Todas en Mi estándar menos la Dean, en Mi♭ estándar (medio tono abajo). Usar solo riffs originales, nunca
canciones con derechos.

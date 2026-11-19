# Rockola (carpeta Kvlt) — contexto

Juego de trivia musical para el iPad. Empezó como «Kvlt» (metal extremo, a3a25b8) y pasó a «Rockola» (191450f):
misma carpeta y bundle `com.francho.kvlt`, nombre visible «Rockola». Lee `../CLAUDE.md` (reglas generales).

## Qué tiene

- 6 géneros: metal, rock clásico, pop, salsa, merengue, rock en español (`Questions.swift`, `GenreQuestions.swift`).
- Datos verificados de bandas reales. La escena de Costa Rica solo lleva preguntas que agregue Fran, porque no había
  datos comprobados: no inventar.
- Modos: solo, por turnos y duelo cara a cara; panel por jugador y tabla de posiciones (`Dashboard.swift`).
- Motor en `Engine.swift`, juego en `Play.swift`, estilo en `Theme.swift`.

## Instalar

`./instalar-ipad.sh`: aparta perfiles viejos, compila para el UDID del iPad, instala y abre (reintenta si está
bloqueado). La firma caduca a los 7 días.

## Ideas aprobadas pero sin empezar

1. **Conciertos:** juego de ritmo donde el iPad escucha su guitarra real.
2. **Demo Tape:** carrera de una banda inventada.

Sus guitarras: Yamaha tipo Strat HSS, Gretsch con dos humbuckers y Dean tipo Explorer con dos humbuckers, más una
acústica. Todas en Mi estándar menos la Dean, en Mi♭ estándar (medio tono abajo). Usar solo riffs originales, nunca
canciones con derechos.

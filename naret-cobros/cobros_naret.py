#!/usr/bin/env python3
"""Revisa en Mail los avisos de cobro de Naret (Condominio Freses) y, por cada
cobro nuevo: lo anota en la nota «Cobros Naret», crea un recordatorio para la
fecha límite y lo marca como procesado. Imprime una línea corta por cobro nuevo
(para la notificación) seguida del detalle.

Uso:  python3 -I cobros_naret.py [--dias 15] [--solo FT724700] [--sin-guardar]
No paga nada ni responde correos: solo lee.
"""
import argparse, datetime as dt, json, os, re, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ET

AQUI = os.path.dirname(os.path.abspath(__file__))
PROCESADOS = os.path.join(AQUI, "procesados.txt")
HISTORIAL = os.path.join(AQUI, "historial.jsonl")
PDFTXT = os.path.join(AQUI, "pdftxt")
REMITENTE = "facturacionifreses@naret.cr"
CUENTA, BUZON = "Google", "INBOX"
NOTA, CARPETA_NOTA, LISTA_REC = "Cobros Naret", "Notes", "Recordatorios"
MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
         "septiembre", "octubre", "noviembre", "diciembre"]


def osa(script, *args):
    r = subprocess.run(["osascript", "-", *args], input=script, text=True,
                       capture_output=True, timeout=240)
    if r.returncode:
        raise RuntimeError(r.stderr.strip())
    return r.stdout.rstrip("\n")


def buscar_correos(dias):
    s = f'''on run argv
tell application "Mail"
  set lim to (current date) - ({int(dias)} * days)
  set ms to (messages of mailbox "{BUZON}" of account "{CUENTA}" whose sender contains "{REMITENTE}" and subject contains "Aviso de cobro" and date received > lim)
  set out to ""
  repeat with m in ms
    set out to out & (id of m) & tab & (subject of m) & linefeed
  end repeat
  return out
end tell
end run'''
    res = []
    for linea in osa(s).splitlines():
        if "\t" in linea:
            mid, asunto = linea.split("\t", 1)
            ft = re.search(r"FT\d+", asunto)
            if ft:
                res.append((mid, ft.group(0)))
    return res


def guardar_adjuntos(mid, carpeta):
    s = f'''on run argv
tell application "Mail"
  set m to first message of mailbox "{BUZON}" of account "{CUENTA}" whose id is {int(mid)}
  repeat with a in (mail attachments of m)
    save a in POSIX file ((item 1 of argv) & "/" & (name of a))
  end repeat
end tell
end run'''
    osa(s, carpeta)


def colones(x):
    entero, dec = f"{x:,.2f}".split(".")
    return "₡" + entero.replace(",", ".") + "," + dec


def leer_cobro(carpeta, ft):
    xmls = [f for f in os.listdir(carpeta) if f.startswith("TE-") and f.endswith(".xml")]
    pdfs = [f for f in os.listdir(carpeta) if f.startswith("TE-") and f.endswith(".pdf")]
    raiz = ET.parse(os.path.join(carpeta, xmls[0])).getroot()
    q = lambda e, t: e.find(f"{{*}}{t}")
    emision = dt.datetime.fromisoformat(q(raiz, "FechaEmision").text).date()
    plazo = int(float((q(raiz, "PlazoCredito").text or "0")))
    limite = emision + dt.timedelta(days=plazo)
    total = float(q(q(raiz, "ResumenFactura"), "TotalComprobante").text)
    lineas = []
    for ld in raiz.findall(".//{*}LineaDetalle"):
        lineas.append((q(ld, "Detalle").text.strip(), float(q(ld, "MontoTotalLinea").text)))
    texto = subprocess.run([PDFTXT, os.path.join(carpeta, pdfs[0])], capture_output=True,
                           text=True, timeout=60).stdout if pdfs else ""
    com = re.search(r"Separación de IVA por\s*tasa\s*(.*?)\s*Datos para información", texto, re.S)
    comentario = " ".join(com.group(1).split()) if com else ""
    pagos = re.search(r"Datos para información de pagos\s*(.*?)\s*Moneda", texto, re.S)
    pagos = [p.strip() for p in pagos.group(1).splitlines() if p.strip()] if pagos else []
    per = re.search(r"(" + "|".join(MESES) + r")\s+(\d{4})", comentario, re.I)
    periodo = f"{per.group(1).lower()} {per.group(2)}" if per else ""
    up = comentario.upper()
    if "MANTENIMIENTO" in up:
        concepto = "Cuota de mantenimiento"
    elif "AGUA" in up:
        concepto = "Agua"
    else:
        concepto = comentario.split(" FRESES")[0].capitalize() or lineas[0][0]
    return {"ft": ft, "consecutivo": q(raiz, "NumeroConsecutivo").text,
            "concepto": concepto, "periodo": periodo, "comentario": comentario,
            "total": total, "emision": emision.isoformat(), "plazo_dias": plazo,
            "limite": limite.isoformat(), "lineas": lineas, "pagos": pagos}


def fecha_corta(iso):
    d = dt.date.fromisoformat(iso)
    return f"{d.day} {MESES[d.month - 1][:3]}"


def fecha_larga(iso):
    d = dt.date.fromisoformat(iso)
    return f"{d.day} de {MESES[d.month - 1]} de {d.year}"


def linea_corta(c):
    return (f"Naret – {c['concepto']} {c['periodo']}: {colones(c['total'])}. "
            f"Pagar antes del {fecha_corta(c['limite'])} ({c['ft']}).")


def detalle(c):
    t = [f"{c['concepto']} {c['periodo']} — {colones(c['total'])}",
         f"Fecha límite: {fecha_larga(c['limite'])} (emitido el {fecha_larga(c['emision'])}, plazo {c['plazo_dias']} días)",
         "Qué se cobra:"]
    t += [f"  • {d}: {colones(m)}" for d, m in c["lineas"]]
    if c["pagos"]:
        t.append("Cómo pagar: " + " | ".join(c["pagos"]))
    t.append(f"Referencia: {c['ft']} · aviso {c['consecutivo']}")
    return "\n".join(t)


def html(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


ESTADOS = os.path.join(AQUI, "estados.json")


def leer_historial():
    if not os.path.exists(HISTORIAL):
        return []
    return [json.loads(l) for l in open(HISTORIAL, encoding="utf-8") if l.strip()]


def estados_recordatorios():
    """FT -> fecha (aaaa-mm-dd) en que se marcó hecho, o "" si sigue pendiente."""
    s = f'''tell application "Reminders"
  set out to ""
  repeat with r in (reminders of list "{LISTA_REC}" whose name starts with "Pagar Naret")
    set b to body of r
    if b is missing value then set b to ""
    set cd to ""
    if completed of r then
      set x to completion date of r
      if x is not missing value then set cd to ((year of x) as string) & "-" & ((month of x as integer) as string) & "-" & ((day of x) as string)
      if cd is "" then set cd to "?"
    end if
    set out to out & cd & tab & (paragraph 1 of (do shell script "echo " & quoted form of b & " | grep -o 'FT[0-9]*' | head -1")) & linefeed
  end repeat
  return out
end tell'''
    res = {}
    for linea in osa(s).splitlines():
        if "\t" not in linea:
            continue
        cd, ft = linea.split("\t", 1)
        if not ft:
            continue
        if cd and cd != "?":
            y, m, d = map(int, cd.split("-"))
            cd = dt.date(y, m, d).isoformat()
        # si hay varios recordatorios del mismo FT, basta con que uno esté hecho
        if cd or ft not in res:
            res[ft] = cd
    return res


def html_cobro(c, pagado):
    lineas = detalle(c).splitlines()
    if pagado:
        cuando = "" if pagado == "?" else f", marcado el {fecha_corta(pagado)}"
        estado = (f'<div><b><span style="color:#1a7f37">✅ PAGADO{cuando}</span></b></div>')
        titulo = f"<div><b><s>{html(lineas[0])}</s></b></div>"
    else:
        estado = (f'<div><b><span style="color:#b35900">⏳ PENDIENTE: vence '
                  f'{fecha_corta(c["limite"])}</span></b></div>')
        titulo = f"<div><b>{html(lineas[0])}</b></div>"
    return titulo + estado + "".join(f"<div>{html(l)}</div>" for l in lineas[1:]) + "<div><br></div>"


def escribir_nota(estados):
    cuerpo = f"<div><h1>{NOTA}</h1></div>" + "".join(
        html_cobro(c, estados.get(c["ft"], "")) for c in leer_historial())
    s = f'''on run argv
tell application "Notes"
  set f to folder "{CARPETA_NOTA}" of default account
  set ns to (notes of f whose name is "{NOTA}")
  if (count of ns) is 0 then
    make new note at f with properties {{body:(item 1 of argv)}}
  else
    set body of (item 1 of ns) to (item 1 of argv)
  end if
end tell
end run'''
    osa(s, cuerpo)


def actualizar_estado(forzar=False):
    """Mira Recordatorios y reescribe la nota solo si algo cambió."""
    actual = {c["ft"]: "" for c in leer_historial()}
    rec = estados_recordatorios()
    for ft in actual:
        actual[ft] = rec.get(ft, "")
    antes = json.load(open(ESTADOS)) if os.path.exists(ESTADOS) else None
    if forzar or actual != antes:
        escribir_nota(actual)
        with open(ESTADOS, "w") as f:
            json.dump(actual, f, indent=1)
        return True
    return False


def crear_recordatorio(c):
    d = dt.date.fromisoformat(c["limite"])
    nombre = (f"Pagar Naret: {c['concepto']} {c['periodo']} {colones(c['total'])}, "
              f"vence {fecha_corta(c['limite'])}")
    s = f'''on run argv
set d to current date
set day of d to 1
set year of d to {d.year}
set month of d to {d.month}
set day of d to {d.day}
set time of d to 9 * hours
tell application "Reminders"
  set l to list "{LISTA_REC}"
  if (count of (reminders of l whose name is (item 1 of argv) and completed is false)) is 0 then
    -- un solo recordatorio: fecha = día que vence; aviso = en 1 minuto
    set ya to (current date) + 60
    make new reminder at end of l with properties {{name:(item 1 of argv), body:(item 2 of argv), due date:d, remind me date:ya}}
  end if
end tell
end run'''
    osa(s, nombre, detalle(c))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dias", type=int, default=15)
    ap.add_argument("--solo", help="procesar solo este FT (para pruebas)")
    ap.add_argument("--sin-guardar", action="store_true",
                    help="solo mostrar; no crea nota, recordatorio ni marca")
    ap.add_argument("--estado", action="store_true",
                    help="solo revisar Recordatorios y marcar PAGADO/PENDIENTE en la nota")
    a = ap.parse_args()
    if a.estado:
        cambio = actualizar_estado()
        print(dt.datetime.now().isoformat(timespec="minutes"),
              "nota actualizada" if cambio else "sin cambios")
        return
    hechos = set(open(PROCESADOS).read().split()) if os.path.exists(PROCESADOS) else set()
    nuevos = []
    for mid, ft in buscar_correos(a.dias):
        if ft in hechos or (a.solo and ft != a.solo):
            continue
        tmp = tempfile.mkdtemp(prefix="naret-")
        try:
            guardar_adjuntos(mid, tmp)
            c = leer_cobro(tmp, ft)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        if not a.sin_guardar:
            crear_recordatorio(c)
            with open(PROCESADOS, "a") as f:
                f.write(ft + "\n")
            with open(HISTORIAL, "a") as f:
                f.write(json.dumps(c, ensure_ascii=False) + "\n")
            hechos.add(ft)
        nuevos.append(c)
    if nuevos and not a.sin_guardar:
        actualizar_estado(forzar=True)
    if not nuevos:
        print("SIN COBROS NUEVOS")
        return
    for c in nuevos:
        print("AVISO: " + linea_corta(c))
    for c in nuevos:
        print("\n" + detalle(c))


if __name__ == "__main__":
    sys.exit(main())

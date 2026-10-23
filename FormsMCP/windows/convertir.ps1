<#
.SYNOPSIS
  Convierte los módulos de Oracle Forms de una carpeta a texto, para leerlos con Claude:
  formularios (.fmb), menús (.mmb) y bibliotecas de objetos (.olb) a XML con frmf2xml,
  y librerías PL/SQL (.pll) a .pld con frmcmp.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File convertir.ps1 -Origen C:\fuentes\forms

  Deja el resultado en C:\fuentes\forms\xml. Los archivos originales no se tocan:
  se trabaja sobre una copia.

.PARAMETER Origen
  Carpeta con los .fmb, .mmb, .olb y .pll (se incluyen las subcarpetas).

.PARAMETER Destino
  Carpeta donde quedan los .xml y .pld. Por defecto, la subcarpeta "xml" de Origen.

.PARAMETER Frmf2xml
  Ruta de frmf2xml.bat o .cmd si el script no lo encuentra solo.

.PARAMETER Frmcmp
  Ruta de frmcmp_batch.cmd (o frmcmp.exe) si el script no lo encuentra solo.
#>
param(
    [Parameter(Mandatory = $true)] [string] $Origen,
    [string] $Destino = "",
    [string] $Frmf2xml = "",
    [string] $Frmcmp = ""
)

$ErrorActionPreference = "Stop"
$Origen = (Resolve-Path $Origen).Path
if (-not $Destino) { $Destino = Join-Path $Origen "xml" }
New-Item -ItemType Directory -Force -Path $Destino | Out-Null
$Destino = (Resolve-Path $Destino).Path

# Busca una herramienta de Forms en las carpetas habituales de Oracle (la primera que aparezca).
function Find-FormsTool([string[]] $Names) {
    $roots = @($env:ORACLE_HOME, $env:DOMAIN_HOME, "C:\Oracle", "C:\app", "D:\Oracle", "C:\Middleware") |
        Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
    foreach ($root in $roots) {
        foreach ($name in $Names) {
            $found = Get-ChildItem -Path $root -Recurse -Filter $name -File -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($found) { return $found.FullName }
        }
    }
    return ""
}

if (-not $Frmf2xml) { $Frmf2xml = Find-FormsTool @("frmf2xml.bat", "frmf2xml.cmd") }
if (-not $Frmf2xml) {
    Write-Host "No encontré frmf2xml. Búscalo en la instalación de Forms y pásalo con -Frmf2xml 'ruta\frmf2xml.bat'." -ForegroundColor Red
    exit 1
}
if (-not $Frmcmp) { $Frmcmp = Find-FormsTool @("frmcmp_batch.cmd", "frmcmp_batch.bat", "frmcmp.exe") }
Write-Host "frmf2xml: $Frmf2xml"
Write-Host "frmcmp:   $(if ($Frmcmp) { $Frmcmp } else { '(no encontrado: las .pll no se convertirán)' })"
Write-Host ""

# Se trabaja sobre una copia: frmf2xml escribe junto al archivo, y así los módulos se encuentran
# entre sí (un formulario que hereda de una .olb o adjunta una .pll necesita tenerlas al lado).
$trabajo = Join-Path $env:TEMP ("forms2xml_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $trabajo | Out-Null
$modulos = Get-ChildItem -Path $Origen -Recurse -File -Include *.fmb, *.mmb, *.olb, *.pll |
    Where-Object { $_.FullName -notlike "$Destino*" }
foreach ($m in $modulos) { Copy-Item $m.FullName -Destination $trabajo -Force }
$env:FORMS_PATH = "$trabajo;$Origen;$env:FORMS_PATH"

# Lo que dicen frmf2xml y frmcmp queda en conversion.log, por si algo falla.
$log = Join-Path $Destino "conversion.log"
Set-Content -Path $log -Value "Conversión $(Get-Date)" -Encoding UTF8
$ok = 0
$fallos = @()
Push-Location $trabajo
try {
    foreach ($m in Get-ChildItem -Path $trabajo -File) {
        $ext = $m.Extension.ToLower()
        if ($ext -eq ".pll") {
            if (-not $Frmcmp) { $fallos += "$($m.Name): no hay frmcmp"; continue }
            & $Frmcmp "module=$($m.FullName)" "module_type=LIBRARY" "script=YES" "batch=YES" 2>&1 |
                Out-File -FilePath $log -Append -Encoding UTF8
            $salida = Join-Path $trabajo ($m.BaseName + ".pld")
        } else {
            & $Frmf2xml "OVERWRITE=YES" "USE_PROPERTY_IDS=NO" $m.FullName 2>&1 |
                Out-File -FilePath $log -Append -Encoding UTF8
            # frmf2xml genera nombre_fmb.xml, nombre_mmb.xml o nombre_olb.xml.
            $salida = Join-Path $trabajo ($m.BaseName + "_" + $ext.TrimStart(".") + ".xml")
        }
        if (Test-Path $salida) {
            Copy-Item $salida -Destination $Destino -Force
            Write-Host "OK     $($m.Name)" -ForegroundColor Green
            $ok++
        } else {
            Write-Host "ERROR  $($m.Name)" -ForegroundColor Red
            $fallos += $m.Name
        }
    }
} finally {
    Pop-Location
    Remove-Item -Recurse -Force $trabajo -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "$ok módulos convertidos en $Destino"
if ($fallos.Count -gt 0) {
    Write-Host "No se pudieron convertir: $($fallos -join ', ')" -ForegroundColor Yellow
    Write-Host "El detalle está en $log."
    Write-Host "Para una .pll, también sirve abrirla en Forms Builder y usar Archivo > Convertir (a .pld)."
}

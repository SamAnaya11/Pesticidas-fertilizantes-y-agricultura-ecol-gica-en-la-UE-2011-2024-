"""
01_descargar_datos.py
Descarga las tablas de Eurostat desde su API pública y las guarda en data/raw/.

Uso:
    python scripts/01_descargar_datos.py               # descarga solo lo que falte
    python scripts/01_descargar_datos.py --actualizar  # vuelve a descargar todo
"""

import gzip
import json
import sys
import urllib.request
from datetime import date
from pathlib import Path

# Carpetas del proyecto (rutas relativas a este script)
CARPETA_PROYECTO = Path(__file__).resolve().parent.parent
CARPETA_RAW = CARPETA_PROYECTO / "data" / "raw"
ARCHIVO_FUENTES = CARPETA_RAW / "fuente_datos.json"

# Dirección base de la API de Eurostat (formato TSV comprimido)
URL_API = "https://ec.europa.eu/eurostat/api/dissemination/sdmx/2.1/data/{codigo}/{filtro}?format=TSV&compressed=true"

# Tablas que necesitamos.
# El "filtro" sirve para descargar solo una parte de tablas muy grandes
# (vacío = tabla completa). Formato: valores de cada dimensión separados por puntos.
TABLAS = {
    "aei_fm_salpest09": {"descripcion": "Ventas de pesticidas por tipo (kg)", "filtro": ""},
    "aei_hri": {"descripcion": "Indicador armonizado de riesgo de pesticidas (HRI1) por grupo de sustancias", "filtro": ""},
    "sdg_02_53": {"descripcion": "Uso y riesgo de pesticidas químicos (índice 2015-2017 = 100)", "filtro": ""},
    "aei_fm_usefert": {"descripcion": "Consumo de fertilizantes minerales (toneladas de nitrógeno y fósforo)", "filtro": ""},
    "aei_pr_gnb": {"descripcion": "Balance bruto de nutrientes (nitrógeno y fósforo)", "filtro": ""},
    "sdg_02_40": {"descripcion": "% de la superficie agraria utilizada que es ecológica", "filtro": ""},
    "apro_cpsh1": {"descripcion": "Superficie agraria utilizada, SAU (miles de ha)", "filtro": "A.UAA.MAR_THS_HA."},
}


def descargar_tabla(codigo, filtro):
    """Descarga una tabla de Eurostat y devuelve el texto TSV descomprimido."""
    url = URL_API.format(codigo=codigo, filtro=filtro)
    print(f"  Descargando {codigo} ...")
    with urllib.request.urlopen(url, timeout=180) as respuesta:
        contenido_comprimido = respuesta.read()
    texto = gzip.decompress(contenido_comprimido).decode("utf-8")
    return url, texto


def cargar_fuentes():
    """Lee fuente_datos.json si existe (para conservar fechas de descargas anteriores)."""
    if ARCHIVO_FUENTES.exists():
        with open(ARCHIVO_FUENTES, encoding="utf-8") as f:
            return json.load(f)
    return {}


def main():
    actualizar = "--actualizar" in sys.argv
    CARPETA_RAW.mkdir(parents=True, exist_ok=True)
    fuentes = cargar_fuentes()

    print("Paso 1: descarga de datos de Eurostat")
    for codigo, info in TABLAS.items():
        archivo = CARPETA_RAW / f"{codigo}.tsv"

        # Si ya lo tenemos y no se pide actualizar, no se vuelve a descargar
        if archivo.exists() and not actualizar:
            print(f"  {codigo}: ya existe, se omite (usa --actualizar para volver a descargar)")
            continue

        url, texto = descargar_tabla(codigo, info["filtro"])
        with open(archivo, "w", encoding="utf-8") as f:
            f.write(texto)

        numero_filas = len(texto.splitlines()) - 1  # sin contar la cabecera
        print(f"  {codigo}: {numero_filas} filas guardadas en {archivo.name}")

        # Guardamos de dónde sale cada archivo y cuándo se descargó
        fuentes[codigo] = {
            "descripcion": info["descripcion"],
            "url_api": url,
            "url_web": f"https://ec.europa.eu/eurostat/databrowser/view/{codigo}/default/table",
            "archivo": f"data/raw/{codigo}.tsv",
            "fecha_descarga": date.today().isoformat(),
        }

    with open(ARCHIVO_FUENTES, "w", encoding="utf-8") as f:
        json.dump(fuentes, f, ensure_ascii=False, indent=2)
    print(f"  Información de las fuentes guardada en {ARCHIVO_FUENTES.name}")


if __name__ == "__main__":
    main()

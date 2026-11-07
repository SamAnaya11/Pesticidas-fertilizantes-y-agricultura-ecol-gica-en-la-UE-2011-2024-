"""
02_limpieza.py
Limpia los archivos originales de Eurostat (data/raw/) y genera las tablas
del modelo en estrella en data/processed/ (formato .csv).

Pasos para cada tabla de Eurostat:
  1. Separar la primera columna ("freq,pesticid,unit,geo") en una columna por dimensión.
  2. Pasar de formato ancho (un año por columna) a formato largo con melt().
  3. Separar el número de la nota (por ejemplo "744072 p" -> 744072 y "p").
  4. Eliminar las celdas sin dato (":"), salvo las confidenciales, que se guardan
     con valor vacío para poder contarlas después.
  5. Quedarnos con la UE-27 y los años 2011-2024.
  6. Traducir los códigos al español.
"""

from pathlib import Path

import pandas as pd

CARPETA_PROYECTO = Path(__file__).resolve().parent.parent
CARPETA_RAW = CARPETA_PROYECTO / "data" / "raw"
CARPETA_PROCESSED = CARPETA_PROYECTO / "data" / "processed"

AÑO_INICIO = 2011
AÑO_FIN = 2024

# ---------------------------------------------------------------------------
# Diccionarios de traducción
# ---------------------------------------------------------------------------

# Países de la UE-27 y el agregado de la UE
PAISES = {
    "AT": "Austria", "BE": "Bélgica", "BG": "Bulgaria", "CY": "Chipre",
    "CZ": "Chequia", "DE": "Alemania", "DK": "Dinamarca", "EE": "Estonia",
    "EL": "Grecia", "ES": "España", "FI": "Finlandia", "FR": "Francia",
    "HR": "Croacia", "HU": "Hungría", "IE": "Irlanda", "IT": "Italia",
    "LT": "Lituania", "LU": "Luxemburgo", "LV": "Letonia", "MT": "Malta",
    "NL": "Países Bajos", "PL": "Polonia", "PT": "Portugal", "RO": "Rumanía",
    "SE": "Suecia", "SI": "Eslovenia", "SK": "Eslovaquia",
    "EU27_2020": "UE-27",
}

# Tipos de pesticida: total (nivel 0), grupos (nivel 1) y clases (nivel 2)
TIPOS_PESTICIDA = {
    "TOTAL": "Total pesticidas",
    "F": "Fungicidas y bactericidas",
    "F01": "Fungicidas inorgánicos (cobre, azufre)",
    "F02": "Fungicidas de carbamatos y ditiocarbamatos",
    "F03": "Fungicidas de bencimidazoles",
    "F04": "Fungicidas de imidazoles y triazoles",
    "F05": "Fungicidas de morfolinas",
    "F07": "Bactericidas",
    "F99": "Otros fungicidas y bactericidas",
    "H": "Herbicidas",
    "H01": "Herbicidas fenoxi-fitohormonas",
    "H02": "Herbicidas de triazinas y triazinonas",
    "H03": "Herbicidas de amidas y anilidas",
    "H04": "Herbicidas de carbamatos y biscarbamatos",
    "H05": "Herbicidas derivados de dinitroanilina",
    "H06": "Herbicidas derivados de urea, uracilo o sulfonilurea",
    "H99": "Otros herbicidas",
    "I": "Insecticidas y acaricidas",
    "I01": "Insecticidas piretroides",
    "I02": "Insecticidas de hidrocarburos clorados",
    "I03": "Insecticidas de carbamatos y oxima-carbamatos",
    "I04": "Insecticidas organofosforados",
    "I06": "Acaricidas",
    "I99": "Otros insecticidas",
    "M": "Molusquicidas",
    "M01": "Molusquicidas",
    "PGR": "Reguladores del crecimiento",
    "PGR01": "Reguladores fisiológicos del crecimiento",
    "PGR02": "Antigerminantes",
    "PGR03": "Otros reguladores del crecimiento",
    "ZR": "Otros fitosanitarios",
    "ZR01": "Aceites minerales",
    "ZR02": "Aceites vegetales",
    "ZR03": "Esterilizantes del suelo (incl. nematicidas)",
    "ZR04": "Rodenticidas",
    "ZR99": "Resto de fitosanitarios",
}

NUTRIENTES = {"N": "Nitrógeno", "P": "Fósforo"}

# Grupos de sustancias del indicador de riesgo HRI1 y su ponderación oficial
# (Directiva (UE) 2019/782): cuanto más peligroso el grupo, más pesa.
GRUPOS_RIESGO = {
    "GRP1": ("Grupo 1: sustancias de bajo riesgo", 1),
    "GRP2": ("Grupo 2: sustancias aprobadas (resto)", 8),
    "GRP3": ("Grupo 3: candidatas a sustitución", 16),
    "GRP4": ("Grupo 4: sustancias no aprobadas", 64),
}

# Significado de las notas de Eurostat (se documenta en el README)
NOTAS = {
    "b": "ruptura de serie",
    "c": "confidencial",
    "d": "definición distinta",
    "e": "estimado",
    "p": "provisional",
    "u": "baja fiabilidad",
}


# ---------------------------------------------------------------------------
# Funciones de limpieza
# ---------------------------------------------------------------------------

def leer_tabla_eurostat(codigo):
    """Lee un .tsv de Eurostat y lo devuelve limpio y en formato largo."""
    df = pd.read_csv(CARPETA_RAW / f"{codigo}.tsv", sep="\t", dtype=str)

    # 1. La primera columna tiene todas las dimensiones juntas: "freq,unit,geo\TIME_PERIOD"
    primera_columna = df.columns[0]
    nombres_dimensiones = primera_columna.split("\\")[0].split(",")
    dimensiones = df[primera_columna].str.split(",", expand=True)
    dimensiones.columns = nombres_dimensiones
    df = pd.concat([dimensiones, df.drop(columns=primera_columna)], axis=1)

    # Los nombres de los años vienen con espacios ("2011 ")
    df.columns = [str(c).strip() for c in df.columns]

    # 2. Un año por columna -> una fila por año (formato largo)
    columnas_año = [c for c in df.columns if c.isdigit()]
    df = df.melt(id_vars=nombres_dimensiones, value_vars=columnas_año,
                 var_name="año", value_name="celda")
    df["año"] = df["año"].astype(int)

    # 3. Separar el número de la nota. Ejemplos: "744072 p", "45.9 e", ": @C", ": "
    partes = df["celda"].str.strip().str.extract(r"^([0-9.]+|:)\s*(.*)$")
    df["valor"] = pd.to_numeric(partes[0].replace(":", None), errors="coerce")
    # Eurostat marca la confidencialidad con "@C": la convertimos en la nota "c"
    df["nota"] = partes[1].str.replace("@C", "c").str.strip()
    df = df.drop(columns="celda")

    # 4. Quitar celdas sin dato, pero conservar las confidenciales (valor vacío + nota "c")
    es_confidencial = df["nota"].str.contains("c", na=False)
    df = df[df["valor"].notna() | es_confidencial]

    # 5. Solo UE-27 (países y agregado) y el periodo de estudio
    df = df[df["geo"].isin(PAISES.keys())]
    df = df[(df["año"] >= AÑO_INICIO) & (df["año"] <= AÑO_FIN)]

    df = df.rename(columns={"geo": "codigo_pais"})
    df["nota"] = df["nota"].replace("", None)
    return df.reset_index(drop=True)


def nivel_pesticida(codigo):
    """0 = total, 1 = grupo (F, H, I...), 2 = clase (F01, H02...)."""
    if codigo == "TOTAL":
        return 0
    if codigo.isalpha():
        return 1
    return 2


def grupo_pesticida(codigo):
    """Devuelve el código del grupo al que pertenece (F01 -> F, PGR02 -> PGR)."""
    if codigo == "TOTAL":
        return "TOTAL"
    return codigo.rstrip("0123456789")


def guardar(df, nombre):
    df.to_csv(CARPETA_PROCESSED / f"{nombre}.csv", index=False, encoding="utf-8")
    print(f"  {nombre}.csv: {len(df)} filas")


# ---------------------------------------------------------------------------
# Construcción de las tablas
# ---------------------------------------------------------------------------

def crear_dimensiones():
    dim_pais = pd.DataFrame({"codigo_pais": list(PAISES.keys()),
                             "pais": list(PAISES.values())})
    dim_pais["es_agregado"] = (dim_pais["codigo_pais"] == "EU27_2020").astype(int)
    guardar(dim_pais, "dim_pais")

    dim_tipo = pd.DataFrame({"codigo_pesticida": list(TIPOS_PESTICIDA.keys()),
                             "tipo_pesticida": list(TIPOS_PESTICIDA.values())})
    dim_tipo["nivel"] = dim_tipo["codigo_pesticida"].apply(nivel_pesticida)
    dim_tipo["codigo_grupo"] = dim_tipo["codigo_pesticida"].apply(grupo_pesticida)
    dim_tipo["grupo"] = dim_tipo["codigo_grupo"].map(TIPOS_PESTICIDA)
    guardar(dim_tipo, "dim_tipo_pesticida")

    dim_nutriente = pd.DataFrame({"codigo_nutriente": list(NUTRIENTES.keys()),
                                  "nutriente": list(NUTRIENTES.values())})
    guardar(dim_nutriente, "dim_nutriente")

    dim_grupo_riesgo = pd.DataFrame({
        "codigo_grupo_riesgo": list(GRUPOS_RIESGO.keys()),
        "grupo_riesgo": [v[0] for v in GRUPOS_RIESGO.values()],
        "ponderacion": [v[1] for v in GRUPOS_RIESGO.values()],
    })
    guardar(dim_grupo_riesgo, "dim_grupo_riesgo")


def crear_hechos():
    # Ventas de pesticidas (kg): solo los niveles 0, 1 y 2 que hemos traducido
    df = leer_tabla_eurostat("aei_fm_salpest09")
    df = df[df["pesticid"].isin(TIPOS_PESTICIDA.keys())]
    df = df.rename(columns={"pesticid": "codigo_pesticida", "valor": "kg"})
    guardar(df[["año", "codigo_pais", "codigo_pesticida", "kg", "nota"]], "fact_ventas_pesticidas")

    # Indicador oficial "uso y riesgo de pesticidas químicos" (2015-2017 = 100)
    df = leer_tabla_eurostat("sdg_02_53")
    df = df.rename(columns={"valor": "indice_2015_2017"})
    guardar(df[["año", "codigo_pais", "indice_2015_2017", "nota"]], "fact_riesgo_pesticidas")

    # Indicador HRI1 por grupo de sustancias (2011-2013 = 100)
    df = leer_tabla_eurostat("aei_hri")
    df = df[df["subst_cat"].isin(GRUPOS_RIESGO.keys())]
    df = df.rename(columns={"subst_cat": "codigo_grupo_riesgo", "valor": "indice_2011_2013"})
    guardar(df[["año", "codigo_pais", "codigo_grupo_riesgo", "indice_2011_2013", "nota"]],
            "fact_riesgo_grupos")

    # Consumo de fertilizantes minerales (toneladas)
    df = leer_tabla_eurostat("aei_fm_usefert")
    df = df.rename(columns={"nutrient": "codigo_nutriente", "valor": "toneladas"})
    guardar(df[["año", "codigo_pais", "codigo_nutriente", "toneladas", "nota"]], "fact_fertilizantes")

    # Balance bruto de nutrientes: nos quedamos con el balance por hectárea (kg/ha)
    df = leer_tabla_eurostat("aei_pr_gnb")
    df = df[df["indic_ag"] == "BAL_UAA"]
    df = df.rename(columns={"nutrient": "codigo_nutriente", "valor": "balance_kg_ha"})
    guardar(df[["año", "codigo_pais", "codigo_nutriente", "balance_kg_ha", "nota"]],
            "fact_balance_nutrientes")

    # Superficie agraria utilizada: Eurostat la da en miles de ha -> la pasamos a ha
    df = leer_tabla_eurostat("apro_cpsh1")
    df["sau_ha"] = df["valor"] * 1000
    guardar(df[["año", "codigo_pais", "sau_ha", "nota"]], "fact_sau")

    # % de la superficie agraria que es ecológica
    df = leer_tabla_eurostat("sdg_02_40")
    df = df.rename(columns={"valor": "pct_sau_ecologica"})
    guardar(df[["año", "codigo_pais", "pct_sau_ecologica", "nota"]], "fact_pct_ecologica")


def main():
    print("Paso 2: limpieza y transformación con pandas")
    CARPETA_PROCESSED.mkdir(parents=True, exist_ok=True)
    crear_dimensiones()
    crear_hechos()


if __name__ == "__main__":
    main()

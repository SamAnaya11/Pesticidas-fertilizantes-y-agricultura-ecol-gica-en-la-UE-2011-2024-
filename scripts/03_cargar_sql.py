"""
03_cargar_sql.py
Crea la base de datos SQLite con el esquema de sql/01_esquema.sql
y carga en ella las tablas limpias de data/processed/.
"""

import sqlite3
from pathlib import Path

import pandas as pd

CARPETA_PROYECTO = Path(__file__).resolve().parent.parent
CARPETA_PROCESSED = CARPETA_PROYECTO / "data" / "processed"
ARCHIVO_ESQUEMA = CARPETA_PROYECTO / "sql" / "01_esquema.sql"
ARCHIVO_BD = CARPETA_PROYECTO / "database" / "pesticidas_fertilizantes.db"

# Orden de carga: primero las dimensiones, después los hechos (por las claves foráneas)
TABLAS = [
    "dim_pais",
    "dim_tipo_pesticida",
    "dim_nutriente",
    "dim_grupo_riesgo",
    "fact_ventas_pesticidas",
    "fact_riesgo_pesticidas",
    "fact_riesgo_grupos",
    "fact_fertilizantes",
    "fact_balance_nutrientes",
    "fact_sau",
    "fact_pct_ecologica",
]


def main():
    print("Paso 3: carga en la base de datos SQLite")
    ARCHIVO_BD.parent.mkdir(parents=True, exist_ok=True)

    conexion = sqlite3.connect(ARCHIVO_BD)
    conexion.execute("PRAGMA foreign_keys = ON")

    # 1. Crear tablas y vistas (el esquema borra las anteriores si existen)
    with open(ARCHIVO_ESQUEMA, encoding="utf-8") as f:
        conexion.executescript(f.read())

    # 2. Cargar cada CSV en su tabla. Con if_exists="append" se respeta
    #    el esquema que acabamos de crear (tipos y claves primarias).
    for tabla in TABLAS:
        df = pd.read_csv(CARPETA_PROCESSED / f"{tabla}.csv")
        df.to_sql(tabla, conexion, if_exists="append", index=False)
        print(f"  {tabla}: {len(df)} filas cargadas")

    # 3. Comprobación: ninguna fila de hechos sin su país en dim_pais
    huerfanas = conexion.execute(
        "SELECT COUNT(*) FROM pragma_foreign_key_check"
    ).fetchone()[0]
    print(f"  Comprobación de claves foráneas: {huerfanas} errores")

    conexion.commit()
    conexion.close()
    print(f"  Base de datos creada en {ARCHIVO_BD.relative_to(CARPETA_PROYECTO)}")


if __name__ == "__main__":
    main()

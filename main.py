"""
main.py
Ejecuta todo el proyecto en orden:
  1. Descarga de datos de Eurostat
  2. Limpieza con pandas
  3. Carga en SQLite
  4. Ejecución del notebook de análisis (genera gráficos y resultados)

Uso:
    python main.py
"""

import os
import subprocess
import sys
from pathlib import Path

CARPETA_PROYECTO = Path(__file__).resolve().parent

PASOS = [
    [sys.executable, "scripts/01_descargar_datos.py"],
    [sys.executable, "scripts/02_limpieza.py"],
    [sys.executable, "scripts/03_cargar_sql.py"],
    [sys.executable, "-m", "jupyter", "nbconvert", "--to", "notebook", "--execute",
     "--inplace", "notebooks/analisis_pesticidas_fertilizantes.ipynb"],
]


def main():
    # Para que los acentos se vean bien en la consola de Windows
    entorno = os.environ.copy()
    entorno["PYTHONIOENCODING"] = "utf-8"

    for paso in PASOS:
        print("\n>>> " + " ".join(paso[1:]))
        resultado = subprocess.run(paso, cwd=CARPETA_PROYECTO, env=entorno)
        if resultado.returncode != 0:
            print("Error en este paso. Se detiene el proceso.")
            sys.exit(1)

    print("\nProceso completado. Abre notebooks/analisis_pesticidas_fertilizantes.ipynb para ver el análisis.")


if __name__ == "__main__":
    main()

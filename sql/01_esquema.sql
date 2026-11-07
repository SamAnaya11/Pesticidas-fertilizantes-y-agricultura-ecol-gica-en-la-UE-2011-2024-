-- =============================================================================
-- 01_esquema.sql
-- Modelo en estrella: pesticidas, fertilizantes y agricultura ecológica en la UE
-- Base de datos: SQLite
-- =============================================================================

DROP VIEW  IF EXISTS v_pesticidas_por_grupo;
DROP VIEW  IF EXISTS v_pesticidas_kg_ha;
DROP VIEW  IF EXISTS v_fertilizantes_kg_ha;

DROP TABLE IF EXISTS fact_ventas_pesticidas;
DROP TABLE IF EXISTS fact_riesgo_pesticidas;
DROP TABLE IF EXISTS fact_riesgo_grupos;
DROP TABLE IF EXISTS fact_fertilizantes;
DROP TABLE IF EXISTS fact_balance_nutrientes;
DROP TABLE IF EXISTS fact_sau;
DROP TABLE IF EXISTS fact_pct_ecologica;
DROP TABLE IF EXISTS dim_pais;
DROP TABLE IF EXISTS dim_tipo_pesticida;
DROP TABLE IF EXISTS dim_nutriente;
DROP TABLE IF EXISTS dim_grupo_riesgo;

-- -----------------------------------------------------------------------------
-- Dimensiones
-- -----------------------------------------------------------------------------

CREATE TABLE dim_pais (
    codigo_pais  TEXT PRIMARY KEY,      -- código Eurostat (ES, FR, EU27_2020...)
    pais         TEXT NOT NULL,
    es_agregado  INTEGER NOT NULL       -- 1 = UE-27, 0 = país
);

CREATE TABLE dim_tipo_pesticida (
    codigo_pesticida  TEXT PRIMARY KEY, -- TOTAL, F, F01...
    tipo_pesticida    TEXT NOT NULL,
    nivel             INTEGER NOT NULL, -- 0 = total, 1 = grupo, 2 = clase
    codigo_grupo      TEXT NOT NULL,
    grupo             TEXT NOT NULL
);

CREATE TABLE dim_nutriente (
    codigo_nutriente  TEXT PRIMARY KEY, -- N, P
    nutriente         TEXT NOT NULL
);

CREATE TABLE dim_grupo_riesgo (
    codigo_grupo_riesgo  TEXT PRIMARY KEY, -- GRP1 ... GRP4
    grupo_riesgo         TEXT NOT NULL,
    ponderacion          INTEGER NOT NULL  -- peso en el indicador HRI1
);

-- -----------------------------------------------------------------------------
-- Tablas de hechos
-- -----------------------------------------------------------------------------

-- Ventas de pesticidas. kg es NULL cuando el dato es confidencial (nota 'c')
CREATE TABLE fact_ventas_pesticidas (
    año               INTEGER NOT NULL,
    codigo_pais       TEXT NOT NULL REFERENCES dim_pais (codigo_pais),
    codigo_pesticida  TEXT NOT NULL REFERENCES dim_tipo_pesticida (codigo_pesticida),
    kg                REAL,
    nota              TEXT,
    PRIMARY KEY (año, codigo_pais, codigo_pesticida)
);

-- Indicador oficial del objetivo "De la granja a la mesa" (media 2015-2017 = 100)
CREATE TABLE fact_riesgo_pesticidas (
    año               INTEGER NOT NULL,
    codigo_pais       TEXT NOT NULL REFERENCES dim_pais (codigo_pais),
    indice_2015_2017  REAL,
    nota              TEXT,
    PRIMARY KEY (año, codigo_pais)
);

-- Indicador de riesgo HRI1 desglosado por grupo de sustancias (media 2011-2013 = 100)
CREATE TABLE fact_riesgo_grupos (
    año                  INTEGER NOT NULL,
    codigo_pais          TEXT NOT NULL REFERENCES dim_pais (codigo_pais),
    codigo_grupo_riesgo  TEXT NOT NULL REFERENCES dim_grupo_riesgo (codigo_grupo_riesgo),
    indice_2011_2013     REAL,
    nota                 TEXT,
    PRIMARY KEY (año, codigo_pais, codigo_grupo_riesgo)
);

CREATE TABLE fact_fertilizantes (
    año               INTEGER NOT NULL,
    codigo_pais       TEXT NOT NULL REFERENCES dim_pais (codigo_pais),
    codigo_nutriente  TEXT NOT NULL REFERENCES dim_nutriente (codigo_nutriente),
    toneladas         REAL,
    nota              TEXT,
    PRIMARY KEY (año, codigo_pais, codigo_nutriente)
);

-- Balance bruto de nutrientes: entradas - salidas, en kg por hectárea de SAU.
-- Un valor positivo indica exceso de nutriente (riesgo de contaminación)
CREATE TABLE fact_balance_nutrientes (
    año               INTEGER NOT NULL,
    codigo_pais       TEXT NOT NULL REFERENCES dim_pais (codigo_pais),
    codigo_nutriente  TEXT NOT NULL REFERENCES dim_nutriente (codigo_nutriente),
    balance_kg_ha     REAL,
    nota              TEXT,
    PRIMARY KEY (año, codigo_pais, codigo_nutriente)
);

CREATE TABLE fact_sau (
    año          INTEGER NOT NULL,
    codigo_pais  TEXT NOT NULL REFERENCES dim_pais (codigo_pais),
    sau_ha       REAL,
    nota         TEXT,
    PRIMARY KEY (año, codigo_pais)
);

CREATE TABLE fact_pct_ecologica (
    año                INTEGER NOT NULL,
    codigo_pais        TEXT NOT NULL REFERENCES dim_pais (codigo_pais),
    pct_sau_ecologica  REAL,
    nota               TEXT,
    PRIMARY KEY (año, codigo_pais)
);

-- -----------------------------------------------------------------------------
-- Vistas
-- -----------------------------------------------------------------------------

-- Ventas por grupo de pesticida (fungicidas, herbicidas...) con nombres
CREATE VIEW v_pesticidas_por_grupo AS
SELECT
    v.año,
    v.codigo_pais,
    p.pais,
    v.codigo_pesticida AS codigo_grupo,
    t.tipo_pesticida   AS grupo,
    v.kg,
    v.nota
FROM fact_ventas_pesticidas AS v
JOIN dim_pais               AS p ON p.codigo_pais = v.codigo_pais
JOIN dim_tipo_pesticida     AS t ON t.codigo_pesticida = v.codigo_pesticida
WHERE t.nivel = 1;

-- Ventas totales de pesticidas por hectárea de superficie agraria
CREATE VIEW v_pesticidas_kg_ha AS
SELECT
    v.año,
    v.codigo_pais,
    p.pais,
    v.kg                AS kg_total,
    s.sau_ha,
    v.kg / s.sau_ha     AS kg_ha,
    v.nota
FROM fact_ventas_pesticidas AS v
JOIN dim_pais               AS p ON p.codigo_pais = v.codigo_pais
LEFT JOIN fact_sau          AS s ON s.codigo_pais = v.codigo_pais AND s.año = v.año
WHERE v.codigo_pesticida = 'TOTAL';

-- Fertilizantes minerales por hectárea (toneladas -> kg)
CREATE VIEW v_fertilizantes_kg_ha AS
SELECT
    f.año,
    f.codigo_pais,
    p.pais,
    p.es_agregado,
    n.nutriente,
    f.toneladas,
    s.sau_ha,
    f.toneladas * 1000 / s.sau_ha AS kg_ha,
    f.nota
FROM fact_fertilizantes AS f
JOIN dim_pais           AS p ON p.codigo_pais = f.codigo_pais
JOIN dim_nutriente      AS n ON n.codigo_nutriente = f.codigo_nutriente
LEFT JOIN fact_sau      AS s ON s.codigo_pais = f.codigo_pais AND s.año = f.año;

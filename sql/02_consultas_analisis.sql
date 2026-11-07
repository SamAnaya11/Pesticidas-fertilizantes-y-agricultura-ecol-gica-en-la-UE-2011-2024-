-- =============================================================================
-- 02_consultas_analisis.sql
-- Consultas de análisis. Cada consulta empieza con "-- nombre: ..." para que
-- el notebook pueda cargarla por su nombre.
--
-- Nota sobre el "total UE" de pesticidas: Eurostat no publica un agregado UE
-- de ventas de pesticidas y muchos países tienen años confidenciales. Para que
-- la serie sea comparable año a año, se suman solo los países con la serie
-- completa 2011-2024 (14 años con dato).
-- =============================================================================


-- nombre: 01_pesticidas_total_ue_espana
-- Pregunta 1. Ventas totales de pesticidas en la UE (países con serie completa)
-- y en España, con variación anual (LAG) e índice 2011 = 100 (FIRST_VALUE).
WITH paises_serie_completa AS (
    SELECT codigo_pais
    FROM fact_ventas_pesticidas
    WHERE codigo_pesticida = 'TOTAL'
    GROUP BY codigo_pais
    HAVING COUNT(kg) = 14              -- COUNT(kg) no cuenta los NULL (confidenciales)
),
total_ue AS (
    SELECT v.año, COUNT(*) AS num_paises, SUM(v.kg) AS kg_ue
    FROM fact_ventas_pesticidas AS v
    JOIN paises_serie_completa  AS c ON c.codigo_pais = v.codigo_pais
    WHERE v.codigo_pesticida = 'TOTAL'
    GROUP BY v.año
),
espana AS (
    SELECT año, kg AS kg_espana
    FROM fact_ventas_pesticidas
    WHERE codigo_pesticida = 'TOTAL' AND codigo_pais = 'ES'
)
SELECT
    u.año,
    u.num_paises,
    ROUND(u.kg_ue / 1e6, 2)                                                          AS millones_kg_ue,
    ROUND(100.0 * u.kg_ue / FIRST_VALUE(u.kg_ue) OVER (ORDER BY u.año), 1)           AS indice_ue_2011,
    ROUND(e.kg_espana / 1e6, 2)                                                      AS millones_kg_espana,
    ROUND(100.0 * (e.kg_espana - LAG(e.kg_espana) OVER (ORDER BY u.año))
          / LAG(e.kg_espana) OVER (ORDER BY u.año), 1)                               AS var_anual_espana_pct,
    ROUND(100.0 * e.kg_espana / FIRST_VALUE(e.kg_espana) OVER (ORDER BY u.año), 1)   AS indice_espana_2011,
    ROUND(100.0 * e.kg_espana / u.kg_ue, 1)                                          AS cuota_espana_pct
FROM total_ue AS u
JOIN espana   AS e ON e.año = u.año
ORDER BY u.año;


-- nombre: 02_pesticidas_ue_por_grupo
-- Pregunta 1. Ventas en la UE por grupo de pesticida. Para cada grupo se suman
-- los países que tienen ese grupo completo los 14 años (HAVING).
WITH paises_completos_por_grupo AS (
    SELECT codigo_pais, codigo_grupo
    FROM v_pesticidas_por_grupo
    GROUP BY codigo_pais, codigo_grupo
    HAVING COUNT(kg) = 14
),
suma_por_grupo AS (
    SELECT g.año, g.codigo_grupo, g.grupo, COUNT(*) AS num_paises, SUM(g.kg) AS kg
    FROM v_pesticidas_por_grupo      AS g
    JOIN paises_completos_por_grupo  AS c
         ON c.codigo_pais = g.codigo_pais AND c.codigo_grupo = g.codigo_grupo
    GROUP BY g.año, g.codigo_grupo, g.grupo
)
SELECT
    año,
    grupo,
    num_paises,
    ROUND(kg / 1e6, 2)                                                            AS millones_kg,
    ROUND(100.0 * kg / FIRST_VALUE(kg) OVER (PARTITION BY codigo_grupo ORDER BY año), 1) AS indice_2011
FROM suma_por_grupo
ORDER BY codigo_grupo, año;


-- nombre: 03_pesticidas_espana_por_grupo
-- Pregunta 1. España: ventas por grupo y peso de cada grupo en el total del año.
-- CASE marca los datos confidenciales.
SELECT
    g.año,
    g.grupo,
    ROUND(g.kg / 1e6, 2)                    AS millones_kg,
    ROUND(100.0 * g.kg / t.kg, 1)           AS pct_del_total,
    CASE WHEN g.kg IS NULL THEN 'confidencial' ELSE 'publicado' END AS estado_dato
FROM v_pesticidas_por_grupo AS g
JOIN fact_ventas_pesticidas AS t
     ON t.codigo_pais = g.codigo_pais AND t.año = g.año AND t.codigo_pesticida = 'TOTAL'
WHERE g.codigo_pais = 'ES'
ORDER BY g.año, g.codigo_grupo;


-- nombre: 04_cambio_por_grupo_espana
-- Pregunta 1. España: cambio de cada grupo entre 2011, la media 2015-2017
-- (referencia de la estrategia) y 2024. Se "pivotan" los años con CASE.
-- Molusquicidas y reguladores del crecimiento quedan fuera: son confidenciales.
WITH tres_periodos AS (
    SELECT
        codigo_grupo,
        grupo,
        SUM(CASE WHEN año = 2011 THEN kg END)                 AS kg_2011,
        AVG(CASE WHEN año BETWEEN 2015 AND 2017 THEN kg END)  AS kg_2015_2017,
        SUM(CASE WHEN año = 2024 THEN kg END)                 AS kg_2024
    FROM v_pesticidas_por_grupo
    WHERE codigo_pais = 'ES'
    GROUP BY codigo_grupo, grupo
)
SELECT
    grupo,
    ROUND(kg_2011 / 1e6, 2)                                   AS millones_kg_2011,
    ROUND(kg_2015_2017 / 1e6, 2)                              AS millones_kg_2015_2017,
    ROUND(kg_2024 / 1e6, 2)                                   AS millones_kg_2024,
    ROUND(100.0 * (kg_2024 - kg_2011) / kg_2011, 1)           AS cambio_desde_2011_pct,
    ROUND(100.0 * (kg_2024 - kg_2015_2017) / kg_2015_2017, 1) AS cambio_desde_2015_2017_pct
FROM tres_periodos
WHERE kg_2011 IS NOT NULL AND kg_2024 IS NOT NULL
ORDER BY kg_2024 DESC;


-- nombre: 05_fertilizantes_ue_espana
-- Pregunta 2. Fertilizantes minerales (N y P) en la UE y en España.
-- UE = suma de los países con serie completa 2011-2024; se compara con el
-- agregado oficial UE-27, que Eurostat solo publica hasta 2019.
WITH paises_completos AS (
    SELECT codigo_pais, codigo_nutriente
    FROM fact_fertilizantes
    WHERE codigo_pais <> 'EU27_2020'
    GROUP BY codigo_pais, codigo_nutriente
    HAVING COUNT(toneladas) = 14
),
suma_ue AS (
    SELECT
        f.año,
        f.codigo_nutriente,
        COUNT(*)          AS num_paises,
        SUM(f.toneladas)  AS toneladas_ue,
        SUM(s.sau_ha)     AS sau_ha_ue
    FROM fact_fertilizantes AS f
    JOIN paises_completos   AS c ON c.codigo_pais = f.codigo_pais AND c.codigo_nutriente = f.codigo_nutriente
    JOIN fact_sau           AS s ON s.codigo_pais = f.codigo_pais AND s.año = f.año
    GROUP BY f.año, f.codigo_nutriente
)
SELECT
    u.año,
    n.nutriente,
    u.num_paises,
    ROUND(u.toneladas_ue / 1e6, 3)                                                   AS millones_t_ue,
    ROUND(oficial.toneladas / 1e6, 3)                                                AS millones_t_ue27_oficial,
    ROUND(u.toneladas_ue * 1000 / u.sau_ha_ue, 1)                                    AS kg_ha_ue,
    ROUND(100.0 * u.toneladas_ue
          / FIRST_VALUE(u.toneladas_ue) OVER (PARTITION BY u.codigo_nutriente ORDER BY u.año), 1) AS indice_ue_2011,
    ROUND(es.toneladas / 1e3, 1)                                                     AS miles_t_espana,
    ROUND(es.kg_ha, 1)                                                               AS kg_ha_espana,
    ROUND(100.0 * es.toneladas
          / FIRST_VALUE(es.toneladas) OVER (PARTITION BY u.codigo_nutriente ORDER BY u.año), 1)   AS indice_espana_2011,
    es.nota                                                                          AS nota_espana
FROM suma_ue                    AS u
JOIN dim_nutriente              AS n  ON n.codigo_nutriente = u.codigo_nutriente
LEFT JOIN fact_fertilizantes    AS oficial
     ON oficial.año = u.año AND oficial.codigo_nutriente = u.codigo_nutriente AND oficial.codigo_pais = 'EU27_2020'
LEFT JOIN v_fertilizantes_kg_ha AS es
     ON es.año = u.año AND es.nutriente = n.nutriente AND es.codigo_pais = 'ES'
ORDER BY n.nutriente DESC, u.año;


-- nombre: 06_ranking_exceso_nitrogeno
-- Pregunta 3. Ranking de exceso de nitrógeno (kg N por ha) con el último año
-- disponible de cada país. Como varios países solo tienen datos hasta 2015,
-- se hacen dos rankings separados (PARTITION BY) para no mezclar épocas.
WITH ultimo_año AS (
    SELECT codigo_pais, MAX(año) AS año
    FROM fact_balance_nutrientes
    WHERE codigo_nutriente = 'N' AND balance_kg_ha IS NOT NULL AND codigo_pais <> 'EU27_2020'
    GROUP BY codigo_pais
),
ultimo_dato AS (
    SELECT
        b.codigo_pais,
        b.año,
        b.balance_kg_ha,
        b.nota,
        CASE WHEN b.año >= 2020 THEN 'reciente (2020-2023)' ELSE 'antiguo (2012-2015)' END AS periodo_dato
    FROM fact_balance_nutrientes AS b
    JOIN ultimo_año              AS u ON u.codigo_pais = b.codigo_pais AND u.año = b.año
    WHERE b.codigo_nutriente = 'N'
)
SELECT
    d.periodo_dato,
    RANK() OVER (PARTITION BY d.periodo_dato ORDER BY d.balance_kg_ha DESC) AS ranking,
    p.pais,
    d.año                                        AS año_dato,
    ROUND(d.balance_kg_ha, 1)                    AS exceso_n_kg_ha,
    -- diferencia con la media de los países con dato reciente (subconsulta)
    ROUND(d.balance_kg_ha - (
        SELECT AVG(balance_kg_ha) FROM ultimo_dato WHERE año >= 2020
    ), 1)                                        AS diferencia_media_reciente,
    CASE WHEN d.nota LIKE '%e%' THEN 'estimado' ELSE '' END AS aviso
FROM ultimo_dato AS d
JOIN dim_pais    AS p ON p.codigo_pais = d.codigo_pais
ORDER BY d.periodo_dato DESC, ranking;


-- nombre: 07_ecologico_vs_pesticidas
-- Pregunta 4. Por país: media 2020-2024 del % de superficie ecológica y de los
-- kg de pesticida por hectárea. Solo países con al menos 3 años de ambos datos.
-- Se añade el peso de los fungicidas inorgánicos (cobre, azufre), que también
-- se usan en agricultura ecológica.
WITH datos_pais_año AS (
    SELECT
        v.codigo_pais,
        v.pais,
        v.año,
        v.kg_ha,
        e.pct_sau_ecologica,
        100.0 * f01.kg / v.kg_total AS pct_fungicidas_inorganicos
    FROM v_pesticidas_kg_ha  AS v
    JOIN fact_pct_ecologica  AS e ON e.codigo_pais = v.codigo_pais AND e.año = v.año
    LEFT JOIN fact_ventas_pesticidas AS f01
         ON f01.codigo_pais = v.codigo_pais AND f01.año = v.año AND f01.codigo_pesticida = 'F01'
    WHERE v.año BETWEEN 2020 AND 2024
      AND v.kg_ha IS NOT NULL
      AND e.pct_sau_ecologica IS NOT NULL
)
SELECT
    codigo_pais,
    pais,
    COUNT(*)                                  AS años_con_dato,
    ROUND(AVG(pct_sau_ecologica), 1)          AS pct_ecologica,
    ROUND(AVG(kg_ha), 2)                      AS kg_pesticida_ha,
    ROUND(AVG(pct_fungicidas_inorganicos), 1) AS pct_fungicidas_inorganicos
FROM datos_pais_año
GROUP BY codigo_pais, pais
HAVING COUNT(*) >= 3
ORDER BY pct_ecologica DESC;


-- nombre: 08_base_proyeccion_ventas
-- Pregunta 5. Datos de partida para la proyección a 2030 de las ventas en kg:
-- media 2015-2017 (periodo de referencia de la estrategia) y último año.
WITH paises_serie_completa AS (
    SELECT codigo_pais
    FROM fact_ventas_pesticidas
    WHERE codigo_pesticida = 'TOTAL'
    GROUP BY codigo_pais
    HAVING COUNT(kg) = 14
),
series AS (
    SELECT 'UE (países con serie completa)' AS ambito, v.año, SUM(v.kg) AS kg
    FROM fact_ventas_pesticidas AS v
    JOIN paises_serie_completa  AS c ON c.codigo_pais = v.codigo_pais
    WHERE v.codigo_pesticida = 'TOTAL'
    GROUP BY v.año
    UNION ALL
    SELECT 'España', año, kg
    FROM fact_ventas_pesticidas
    WHERE codigo_pesticida = 'TOTAL' AND codigo_pais = 'ES'
)
SELECT
    ambito,
    AVG(CASE WHEN año BETWEEN 2015 AND 2017 THEN kg END)          AS kg_media_2015_2017,
    MAX(año)                                                       AS ultimo_año,
    SUM(CASE WHEN año = (SELECT MAX(año) FROM series) THEN kg END) AS kg_ultimo_año
FROM series
GROUP BY ambito
ORDER BY ambito DESC;


-- nombre: 09_indicador_riesgo_ue_espana
-- Pregunta 5. Indicador oficial "uso y riesgo de pesticidas químicos"
-- (media 2015-2017 = 100; el objetivo 2030 es 50) para la UE-27 y España.
SELECT
    r.año,
    p.pais,
    r.indice_2015_2017,
    r.indice_2015_2017 - LAG(r.indice_2015_2017) OVER (PARTITION BY r.codigo_pais ORDER BY r.año) AS cambio_anual
FROM fact_riesgo_pesticidas AS r
JOIN dim_pais               AS p ON p.codigo_pais = r.codigo_pais
WHERE r.codigo_pais IN ('EU27_2020', 'ES')
ORDER BY p.pais DESC, r.año;


-- nombre: 10_ranking_reduccion_riesgo
-- Pregunta 5. ¿Qué países han reducido más el indicador de riesgo?
-- Último año publicado de cada país (muchos años son confidenciales).
WITH ultimo_dato AS (
    SELECT codigo_pais, MAX(año) AS año
    FROM fact_riesgo_pesticidas
    WHERE indice_2015_2017 IS NOT NULL AND codigo_pais <> 'EU27_2020'
    GROUP BY codigo_pais
)
SELECT
    RANK() OVER (ORDER BY r.indice_2015_2017)  AS ranking,
    p.pais,
    r.año                                       AS año_dato,
    r.indice_2015_2017,
    CASE WHEN r.indice_2015_2017 <= 50 THEN 'Sí' ELSE 'No' END AS cumple_objetivo_2030
FROM fact_riesgo_pesticidas AS r
JOIN ultimo_dato            AS u ON u.codigo_pais = r.codigo_pais AND u.año = r.año
JOIN dim_pais               AS p ON p.codigo_pais = r.codigo_pais
ORDER BY ranking;


-- nombre: 11_riesgo_por_grupo_ue
-- Pregunta 5. Indicador HRI1 de la UE-27 por grupo de sustancias (2011-2013 = 100).
-- Explica por qué el riesgo baja más que los kilos: cada grupo pesa distinto.
SELECT
    g.grupo_riesgo,
    g.ponderacion,
    SUM(CASE WHEN r.año = 2011 THEN r.indice_2011_2013 END) AS indice_2011,
    SUM(CASE WHEN r.año = 2017 THEN r.indice_2011_2013 END) AS indice_2017,
    SUM(CASE WHEN r.año = 2024 THEN r.indice_2011_2013 END) AS indice_2024
FROM fact_riesgo_grupos AS r
JOIN dim_grupo_riesgo   AS g ON g.codigo_grupo_riesgo = r.codigo_grupo_riesgo
WHERE r.codigo_pais = 'EU27_2020'
GROUP BY g.codigo_grupo_riesgo, g.grupo_riesgo, g.ponderacion
ORDER BY g.codigo_grupo_riesgo;


-- nombre: 12_cobertura_datos_pesticidas
-- Limitaciones. Años con dato publicado y años confidenciales del total de
-- ventas de pesticidas por país (14 años posibles: 2011-2024).
SELECT
    p.pais,
    COUNT(v.kg)                                          AS años_con_dato,
    SUM(CASE WHEN v.nota LIKE '%c%' THEN 1 ELSE 0 END)   AS años_confidenciales,
    14 - COUNT(v.kg)                                     AS años_sin_dato,
    CASE WHEN COUNT(v.kg) = 14 THEN 'completa' ELSE 'incompleta' END AS serie
FROM dim_pais AS p
LEFT JOIN fact_ventas_pesticidas AS v
     ON v.codigo_pais = p.codigo_pais AND v.codigo_pesticida = 'TOTAL'
WHERE p.es_agregado = 0
GROUP BY p.pais
HAVING COUNT(v.kg) < 14
ORDER BY años_con_dato;

-- =============================================================================
-- CONSULTAS: Agregados por período (Continuous Aggregates)
-- Usar estas vistas en lugar de log_records para análisis histórico.
-- Son instantáneas: TimescaleDB las pre-calcula en background.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Promedio diario de una variable por equipo — último mes
-- -----------------------------------------------------------------------------
SELECT
    primary_id,
    record_name,
    bucket,
    avg_value,
    min_value,
    max_value,
    sample_count
FROM log_daily
WHERE
    record_name = '<NOMBRE_VARIABLE>'
    AND bucket >= NOW() - INTERVAL '30 days'
ORDER BY primary_id, bucket DESC;

-- -----------------------------------------------------------------------------
-- 2. Comparativa semanal de todos los equipos para una variable
-- -----------------------------------------------------------------------------
SELECT
    primary_id,
    bucket AS semana,
    ROUND(avg_value::numeric, 4) AS promedio,
    ROUND(min_value::numeric, 4) AS minimo,
    ROUND(max_value::numeric, 4) AS maximo,
    sample_count AS muestras
FROM log_weekly
WHERE
    record_name = '<NOMBRE_VARIABLE>'
    AND bucket >= NOW() - INTERVAL '12 weeks'
ORDER BY bucket DESC, primary_id;

-- -----------------------------------------------------------------------------
-- 3. Resumen mensual de un equipo específico — año actual
-- -----------------------------------------------------------------------------
SELECT
    record_name,
    bucket AS mes,
    ROUND(avg_value::numeric, 4) AS promedio,
    min_value,
    max_value,
    sample_count
FROM log_monthly
WHERE
    primary_id = '<IP_EQUIPO>'
    AND bucket >= DATE_TRUNC('year', NOW())
ORDER BY record_name, bucket;

-- -----------------------------------------------------------------------------
-- 4. Tendencia semestral de todos los equipos
-- -----------------------------------------------------------------------------
SELECT
    primary_id,
    record_name,
    bucket AS semestre,
    ROUND(avg_value::numeric, 4) AS promedio_semestre
FROM log_semester
ORDER BY bucket DESC, primary_id, record_name;

-- -----------------------------------------------------------------------------
-- 5. Resumen anual — ranking de equipos por valor máximo de una variable
-- -----------------------------------------------------------------------------
SELECT
    primary_id,
    bucket AS anio,
    ROUND(max_value::numeric, 4) AS pico_maximo,
    ROUND(avg_value::numeric, 4) AS promedio_anual,
    sample_count
FROM log_yearly
WHERE record_name = '<NOMBRE_VARIABLE>'
ORDER BY bucket DESC, max_value DESC;

-- -----------------------------------------------------------------------------
-- 6. Evolución diaria de múltiples variables de un equipo (útil para graficar)
-- -----------------------------------------------------------------------------
SELECT
    record_name,
    bucket AS dia,
    avg_value,
    sample_count
FROM log_daily
WHERE
    primary_id = '<IP_EQUIPO>'
    AND bucket BETWEEN '<FECHA_INICIO>' AND '<FECHA_FIN>'
ORDER BY record_name, bucket;

-- -----------------------------------------------------------------------------
-- 7. Variables con mayor varianza (max - min) en la última semana
--    Útil para detectar anomalías o equipos inestables
-- -----------------------------------------------------------------------------
SELECT
    primary_id,
    record_name,
    ROUND((max_value - min_value)::numeric, 4) AS varianza_pico,
    ROUND(avg_value::numeric, 4)               AS promedio,
    sample_count
FROM log_daily
WHERE bucket >= NOW() - INTERVAL '7 days'
ORDER BY varianza_pico DESC
LIMIT 20;

-- -----------------------------------------------------------------------------
-- 8. Forzar refresco manual de un aggregate (si los datos son muy recientes)
--    Útil justo después de inyectar datos históricos masivos
-- -----------------------------------------------------------------------------
-- CALL refresh_continuous_aggregate('log_daily',   '<FECHA_INICIO>', '<FECHA_FIN>');
-- CALL refresh_continuous_aggregate('log_weekly',  '<FECHA_INICIO>', '<FECHA_FIN>');
-- CALL refresh_continuous_aggregate('log_monthly', '<FECHA_INICIO>', '<FECHA_FIN>');

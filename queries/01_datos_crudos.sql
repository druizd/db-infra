-- =============================================================================
-- CONSULTAS: Datos crudos — tabla log_records
-- =============================================================================
-- Los parámetros entre <> deben reemplazarse con valores reales.
-- Ejemplo de primary_id: '151.20.35.10'
-- Ejemplo de record_name: 'CPU_Load', 'Memory_Usage', 'Disk_Read'
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Últimos N registros de un equipo específico
-- -----------------------------------------------------------------------------
SELECT
    primary_id,
    record_name,
    record_ts,
    record_value
FROM log_records
WHERE primary_id = '<IP_EQUIPO>'
ORDER BY record_ts DESC
LIMIT 100;

-- -----------------------------------------------------------------------------
-- 2. Todos los registros de una variable en un rango de tiempo
-- -----------------------------------------------------------------------------
SELECT
    primary_id,
    record_ts,
    record_value
FROM log_records
WHERE
    record_name = '<NOMBRE_VARIABLE>'
    AND record_ts >= '<FECHA_INICIO>'     -- ej: '2024-03-01 00:00:00+00'
    AND record_ts <  '<FECHA_FIN>'        -- ej: '2024-04-01 00:00:00+00'
ORDER BY record_ts;

-- -----------------------------------------------------------------------------
-- 3. Últimas 24 horas para un equipo y variable específicos
-- -----------------------------------------------------------------------------
SELECT
    record_ts,
    record_value
FROM log_records
WHERE
    primary_id  = '<IP_EQUIPO>'
    AND record_name = '<NOMBRE_VARIABLE>'
    AND record_ts >= NOW() - INTERVAL '24 hours'
ORDER BY record_ts DESC;

-- -----------------------------------------------------------------------------
-- 4. Cuántos registros existen por equipo
-- -----------------------------------------------------------------------------
SELECT
    primary_id,
    COUNT(*) AS total_registros,
    MIN(record_ts) AS primer_registro,
    MAX(record_ts) AS ultimo_registro
FROM log_records
GROUP BY primary_id
ORDER BY total_registros DESC;

-- -----------------------------------------------------------------------------
-- 5. Qué variables (record_name) existen para un equipo
-- -----------------------------------------------------------------------------
SELECT DISTINCT record_name
FROM log_records
WHERE primary_id = '<IP_EQUIPO>'
ORDER BY record_name;

-- -----------------------------------------------------------------------------
-- 6. Detección de gaps: rangos de tiempo sin datos (útil para debug)
--    Muestra saltos de más de 1 hora entre registros consecutivos
-- -----------------------------------------------------------------------------
WITH gaps AS (
    SELECT
        primary_id,
        record_name,
        record_ts,
        LAG(record_ts) OVER (PARTITION BY primary_id, record_name ORDER BY record_ts) AS prev_ts
    FROM log_records
    WHERE primary_id = '<IP_EQUIPO>'
)
SELECT
    primary_id,
    record_name,
    prev_ts AS inicio_gap,
    record_ts AS fin_gap,
    record_ts - prev_ts AS duracion_gap
FROM gaps
WHERE record_ts - prev_ts > INTERVAL '1 hour'
ORDER BY duracion_gap DESC;

-- -----------------------------------------------------------------------------
-- 7. Verificar si hay duplicados (no debería haberlos por el índice único)
-- -----------------------------------------------------------------------------
SELECT
    primary_id,
    record_name,
    record_ts,
    COUNT(*) AS ocurrencias
FROM log_records
GROUP BY primary_id, record_name, record_ts
HAVING COUNT(*) > 1
ORDER BY ocurrencias DESC;

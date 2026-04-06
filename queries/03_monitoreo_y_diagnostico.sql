-- =============================================================================
-- CONSULTAS: Monitoreo, diagnóstico y estado de la DB
-- Ejecutar desde psql o cualquier cliente PostgreSQL conectado a logmetrics
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Estado general de los chunks de la hypertable
-- -----------------------------------------------------------------------------
SELECT
    chunk_name,
    range_start,
    range_end,
    is_compressed,
    chunk_tablespace
FROM timescaledb_information.chunks
WHERE hypertable_name = 'log_records'
ORDER BY range_start DESC
LIMIT 20;

-- -----------------------------------------------------------------------------
-- 2. Tamaño total de la tabla y sus índices
-- -----------------------------------------------------------------------------
SELECT
    hypertable_name,
    pg_size_pretty(hypertable_size(format('%I', hypertable_name)::regclass)) AS tamaño_total
FROM timescaledb_information.hypertables
WHERE hypertable_name = 'log_records';

-- Desglosado: tabla vs índices
SELECT * FROM hypertable_detailed_size('log_records');

-- -----------------------------------------------------------------------------
-- 3. Verificar que los continuous aggregates están configurados correctamente
-- -----------------------------------------------------------------------------
SELECT
    view_name,
    materialization_hypertable_name,
    compression_enabled,
    finalized
FROM timescaledb_information.continuous_aggregates
ORDER BY view_name;

-- -----------------------------------------------------------------------------
-- 4. Políticas de refresco activas
-- -----------------------------------------------------------------------------
SELECT
    application_name,
    schedule_interval,
    config
FROM timescaledb_information.jobs
WHERE application_name LIKE '%Continuous Aggregate%'
   OR application_name LIKE '%Compression%'
ORDER BY application_name;

-- -----------------------------------------------------------------------------
-- 5. Comprobación de integridad: total de filas y rango temporal
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*)        AS total_filas,
    COUNT(DISTINCT primary_id)  AS equipos_distintos,
    COUNT(DISTINCT record_name) AS variables_distintas,
    MIN(record_ts)  AS primer_registro,
    MAX(record_ts)  AS ultimo_registro,
    MAX(record_ts) - MIN(record_ts) AS rango_total
FROM log_records;

-- -----------------------------------------------------------------------------
-- 6. Última vez que ingresaron datos por equipo (liveness check)
-- -----------------------------------------------------------------------------
SELECT
    primary_id,
    MAX(record_ts) AS ultimo_dato,
    NOW() - MAX(record_ts) AS tiempo_desde_ultimo_dato
FROM log_records
GROUP BY primary_id
ORDER BY ultimo_dato DESC;

-- -----------------------------------------------------------------------------
-- 7. Chunks comprimidos vs sin comprimir
-- -----------------------------------------------------------------------------
SELECT
    is_compressed,
    COUNT(*) AS cantidad_chunks
FROM timescaledb_information.chunks
WHERE hypertable_name = 'log_records'
GROUP BY is_compressed;

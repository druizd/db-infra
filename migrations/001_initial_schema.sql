-- =============================================================================
-- MIGRACIÓN 001: Esquema inicial completo para TimescaleDB
-- Aplica en: base de datos logmetrics
-- Idempotente: puede ejecutarse múltiples veces sin error
-- =============================================================================

-- -----------------------------------------------------------------------------
-- PASO 1: Crear tabla principal (hypertable)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS log_records (
    primary_id     VARCHAR(50)  NOT NULL,
    reception_date DATE         NOT NULL,
    record_name    VARCHAR(50)  NOT NULL,
    record_ts      TIMESTAMPTZ  NOT NULL,   -- columna de partición temporal
    record_value   FLOAT
);

-- -----------------------------------------------------------------------------
-- PASO 2: Convertir a hypertable con partición dual
--   - record_ts        → partición temporal  (chunks por rango de tiempo)
--   - primary_id       → partición espacial  (16 particiones para 500+ equipos)
-- -----------------------------------------------------------------------------
SELECT create_hypertable(
    'log_records',
    'record_ts',
    partitioning_column => 'primary_id',
    number_partitions   => 16,
    if_not_exists       => TRUE
);

-- -----------------------------------------------------------------------------
-- PASO 3: Índices de rendimiento
-- -----------------------------------------------------------------------------

-- Índice compuesto: consultas por equipo + rango de tiempo → O(log n)
CREATE INDEX IF NOT EXISTS idx_log_records_device_time
    ON log_records (primary_id, record_ts DESC);

-- Índice único: previene duplicados (equipo + variable + timestamp).
-- Permite reprocesar el mismo CSV de forma segura (ON CONFLICT DO NOTHING).
CREATE UNIQUE INDEX IF NOT EXISTS uq_log_records_device_name_ts
    ON log_records (primary_id, record_name, record_ts);

-- -----------------------------------------------------------------------------
-- PASO 4: Política de compresión automática
--   - segmentby: agrupa por equipo+variable dentro de cada chunk comprimido
--   - Comprime chunks con más de 7 días de antigüedad
-- -----------------------------------------------------------------------------
ALTER TABLE log_records SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'primary_id, record_name'
);

SELECT add_compression_policy(
    'log_records',
    INTERVAL '7 days',
    if_not_exists => TRUE
);

-- -----------------------------------------------------------------------------
-- PASO 5: Continuous Aggregates (vistas pre-calculadas por periodo)
-- TimescaleDB las actualiza en background; las consultas son instantáneas.
-- -----------------------------------------------------------------------------

-- Agregado DIARIO
CREATE MATERIALIZED VIEW IF NOT EXISTS log_daily
WITH (timescaledb.continuous) AS
SELECT
    primary_id,
    record_name,
    time_bucket('1 day', record_ts) AS bucket,
    AVG(record_value)  AS avg_value,
    MIN(record_value)  AS min_value,
    MAX(record_value)  AS max_value,
    COUNT(*)           AS sample_count
FROM log_records
GROUP BY primary_id, record_name, bucket
WITH NO DATA;

-- Agregado SEMANAL
CREATE MATERIALIZED VIEW IF NOT EXISTS log_weekly
WITH (timescaledb.continuous) AS
SELECT
    primary_id,
    record_name,
    time_bucket('1 week', record_ts) AS bucket,
    AVG(record_value)  AS avg_value,
    MIN(record_value)  AS min_value,
    MAX(record_value)  AS max_value,
    COUNT(*)           AS sample_count
FROM log_records
GROUP BY primary_id, record_name, bucket
WITH NO DATA;

-- Agregado MENSUAL
CREATE MATERIALIZED VIEW IF NOT EXISTS log_monthly
WITH (timescaledb.continuous) AS
SELECT
    primary_id,
    record_name,
    time_bucket('1 month', record_ts) AS bucket,
    AVG(record_value)  AS avg_value,
    MIN(record_value)  AS min_value,
    MAX(record_value)  AS max_value,
    COUNT(*)           AS sample_count
FROM log_records
GROUP BY primary_id, record_name, bucket
WITH NO DATA;

-- Agregado SEMESTRAL
CREATE MATERIALIZED VIEW IF NOT EXISTS log_semester
WITH (timescaledb.continuous) AS
SELECT
    primary_id,
    record_name,
    time_bucket('6 months', record_ts) AS bucket,
    AVG(record_value)  AS avg_value,
    MIN(record_value)  AS min_value,
    MAX(record_value)  AS max_value,
    COUNT(*)           AS sample_count
FROM log_records
GROUP BY primary_id, record_name, bucket
WITH NO DATA;

-- Agregado ANUAL
CREATE MATERIALIZED VIEW IF NOT EXISTS log_yearly
WITH (timescaledb.continuous) AS
SELECT
    primary_id,
    record_name,
    time_bucket('1 year', record_ts) AS bucket,
    AVG(record_value)  AS avg_value,
    MIN(record_value)  AS min_value,
    MAX(record_value)  AS max_value,
    COUNT(*)           AS sample_count
FROM log_records
GROUP BY primary_id, record_name, bucket
WITH NO DATA;

-- -----------------------------------------------------------------------------
-- PASO 6: Políticas de refresco automático de los aggregates
-- -----------------------------------------------------------------------------
SELECT add_continuous_aggregate_policy('log_daily',
    start_offset      => INTERVAL '3 days',
    end_offset        => INTERVAL '1 day',
    schedule_interval => INTERVAL '1 hour',
    if_not_exists     => TRUE);

SELECT add_continuous_aggregate_policy('log_weekly',
    start_offset      => INTERVAL '4 weeks',
    end_offset        => INTERVAL '1 week',
    schedule_interval => INTERVAL '1 day',
    if_not_exists     => TRUE);

SELECT add_continuous_aggregate_policy('log_monthly',
    start_offset      => INTERVAL '4 months',
    end_offset        => INTERVAL '1 month',
    schedule_interval => INTERVAL '1 day',
    if_not_exists     => TRUE);

SELECT add_continuous_aggregate_policy('log_semester',
    start_offset      => INTERVAL '2 years',
    end_offset        => INTERVAL '6 months',
    schedule_interval => INTERVAL '1 week',
    if_not_exists     => TRUE);

SELECT add_continuous_aggregate_policy('log_yearly',
    start_offset      => INTERVAL '4 years',
    end_offset        => INTERVAL '1 year',
    schedule_interval => INTERVAL '1 month',
    if_not_exists     => TRUE);

-- =============================================================================
-- MIGRACIÓN 002: Actualizar DB existente al esquema completo
--
-- USO: Ejecutar SOLO si ya existe una DB con el esquema ANTERIOR:
--   - Tabla con columnas separadas (record_date DATE + record_time TIME), O
--   - Tabla sin partición espacial / sin índices / sin aggregates
--
-- ⚠️  PASO DESTRUCTIVO: Esta migración elimina y re-crea la tabla.
--    Asegúrate de tener backup antes de ejecutar en producción.
--
-- CÓMO EJECUTAR (dentro del contenedor):
--   docker exec -it <nombre_contenedor> psql -U postgres -d logmetrics -f /migrations/002_upgrade_existing_db.sql
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- PASO 1: Eliminar vistas dependientes de la tabla (si existen)
-- Las continuous aggregates deben eliminarse antes que la tabla base.
-- -----------------------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS log_yearly   CASCADE;
DROP MATERIALIZED VIEW IF EXISTS log_semester CASCADE;
DROP MATERIALIZED VIEW IF EXISTS log_monthly  CASCADE;
DROP MATERIALIZED VIEW IF EXISTS log_weekly   CASCADE;
DROP MATERIALIZED VIEW IF EXISTS log_daily    CASCADE;

-- -----------------------------------------------------------------------------
-- PASO 2: Eliminar la tabla vieja (con cualquier esquema anterior)
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS log_records CASCADE;

COMMIT;

-- -----------------------------------------------------------------------------
-- PASO 3: Re-crear con esquema nuevo (fuera de la transacción: TimescaleDB lo requiere)
-- -----------------------------------------------------------------------------
CREATE TABLE log_records (
    primary_id     VARCHAR(50)  NOT NULL,
    reception_date DATE         NOT NULL,
    record_name    VARCHAR(50)  NOT NULL,
    record_ts      TIMESTAMPTZ  NOT NULL,
    record_value   FLOAT
);

SELECT create_hypertable(
    'log_records',
    'record_ts',
    partitioning_column => 'primary_id',
    number_partitions   => 16,
    if_not_exists       => TRUE
);

-- -----------------------------------------------------------------------------
-- PASO 4: Índices
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_log_records_device_time
    ON log_records (primary_id, record_ts DESC);

CREATE UNIQUE INDEX IF NOT EXISTS uq_log_records_device_name_ts
    ON log_records (primary_id, record_name, record_ts);

-- -----------------------------------------------------------------------------
-- PASO 5: Compresión
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
-- PASO 6: Continuous Aggregates
-- -----------------------------------------------------------------------------
CREATE MATERIALIZED VIEW log_daily
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

CREATE MATERIALIZED VIEW log_weekly
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

CREATE MATERIALIZED VIEW log_monthly
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

CREATE MATERIALIZED VIEW log_semester
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

CREATE MATERIALIZED VIEW log_yearly
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
-- PASO 7: Políticas de refresco
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

-- -----------------------------------------------------------------------------
-- Verificación final
-- -----------------------------------------------------------------------------
SELECT
    hypertable_name,
    num_dimensions
FROM timescaledb_information.hypertables
WHERE hypertable_name = 'log_records';

SELECT view_name, materialization_hypertable_name
FROM timescaledb_information.continuous_aggregates
ORDER BY view_name;

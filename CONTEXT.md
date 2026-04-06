# db-infra — Contexto del Repositorio

## ¿Qué es?

Repositorio de **Infraestructura como Código (IaC)** para la base de datos central del sistema.  
Define y levanta la instancia de **TimescaleDB** (PostgreSQL con extensión de series temporales) que almacena todos los registros de logs procesados por el pipeline.

## Posición en el sistema

```
[csvprocessor (Win)] ─── [csvshipper-win (Win)] ──→ [RabbitMQ] ──→ [csvconsumer (Linux)] ──INSERT──→ [db-infra / TimescaleDB]
```

Este es el **destino final** de todos los datos del sistema. Debe estar levantado **antes** que cualquier otro servicio.

## Stack técnico

| Componente | Detalle |
|------------|---------|
| Base de datos | TimescaleDB `latest-pg15` (PostgreSQL 15 + extensión TimescaleDB) |
| Orquestación | Docker Compose |
| Persistencia | Volumen Docker nombrado (`timescaledb_data`) |
| Puerto expuesto | `5432` (PostgreSQL estándar) |

## Configuración (`docker-compose.yml`)

```yaml
imagen:    timescale/timescaledb:latest-pg15
usuario:   postgres
password:  postgres123
base de datos: logmetrics
puerto:    5432
restart:   unless-stopped
volumen:   timescaledb_data (persistente entre reinicios)
```

## Esquema completo de `log_records`

La tabla `log_records` es una **hypertable de TimescaleDB** con partición dual (tiempo + espacio).  
El esquema es generado automáticamente por el `csvprocessor` en cada archivo `.sql` que produce.

### Tabla principal

```sql
CREATE TABLE IF NOT EXISTS log_records (
    primary_id     VARCHAR(50)  NOT NULL,   -- IP o identificador del equipo
    reception_date DATE         NOT NULL,   -- Fecha de recepción del CSV
    record_name    VARCHAR(50)  NOT NULL,   -- Nombre de la variable (ej: CPU_Load)
    record_ts      TIMESTAMPTZ  NOT NULL,   -- Timestamp del dato (columna de partición)
    record_value   FLOAT                    -- Valor medido
);
```

### Hypertable con partición dual

```sql
SELECT create_hypertable(
    'log_records',
    'record_ts',                       -- partición temporal (eje principal)
    partitioning_column => 'primary_id',
    number_partitions   => 16,         -- distribución espacial para 500+ equipos
    if_not_exists       => TRUE
);
```

### Índices

```sql
-- Consultas por equipo + rango de tiempo → O(log n)
CREATE INDEX IF NOT EXISTS idx_log_records_device_time
    ON log_records (primary_id, record_ts DESC);

-- Previene duplicados (equipo + variable + timestamp)
CREATE UNIQUE INDEX IF NOT EXISTS uq_log_records_device_name_ts
    ON log_records (primary_id, record_name, record_ts);
```

### Compresión automática

```sql
ALTER TABLE log_records SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'primary_id, record_name'  -- agrupa por equipo+variable
);

-- Comprime chunks con más de 7 días de antigüedad
SELECT add_compression_policy('log_records', INTERVAL '7 days', if_not_exists => TRUE);
```

### Continuous Aggregates (vistas pre-calculadas)

TimescaleDB mantiene 5 vistas de agregados que se actualizan automáticamente en background:

| Vista | Bucket | Refresco |
|-------|--------|----------|
| `log_daily` | 1 día | Cada hora |
| `log_weekly` | 1 semana | Cada día |
| `log_monthly` | 1 mes | Cada día |
| `log_semester` | 6 meses | Cada semana |
| `log_yearly` | 1 año | Cada mes |

Cada vista expone: `primary_id`, `record_name`, `bucket`, `avg_value`, `min_value`, `max_value`, `sample_count`.

> **Regla de oro**: Para análisis histórico, usar siempre las vistas `log_daily`/`log_weekly`/etc.  
> Para datos en tiempo real o últimas horas, consultar directamente `log_records`.

## Estructura del repositorio

```
db-infra/
├── docker-compose.yml                  # Infraestructura del contenedor TimescaleDB
├── migrations/
│   ├── 001_initial_schema.sql          # Crear esquema desde cero (DB nueva)
│   └── 002_upgrade_existing_db.sql     # Actualizar DB con esquema viejo a esquema nuevo
├── queries/
│   ├── 01_datos_crudos.sql             # Consultas sobre log_records
│   ├── 02_aggregates_por_periodo.sql   # Consultas sobre log_daily/weekly/monthly/etc.
│   └── 03_monitoreo_y_diagnostico.sql  # Estado de chunks, tamaños, integridad
├── CONTEXT.md                          # Este archivo
└── README.md
```

## Comandos de despliegue

```bash
# Levantar la base de datos en background
docker-compose up -d

# Ver logs
docker-compose logs -f

# Detener (sin borrar datos)
docker-compose down

# Destruir incluyendo datos (⚠️ irreversible)
docker-compose down -v
```

## Cómo aplicar las migraciones

### DB nueva (primera vez)

```bash
# 1. Levantar el contenedor
docker-compose up -d

# 2. Aplicar el esquema inicial
docker exec -i $(docker-compose ps -q timescale) \
  psql -U postgres -d logmetrics \
  < migrations/001_initial_schema.sql
```

### DB existente con esquema viejo

> ⚠️ **Destructivo**: elimina y re-crea la tabla. Asegúrate de tener backup.

```bash
docker exec -i $(docker-compose ps -q timescale) \
  psql -U postgres -d logmetrics \
  < migrations/002_upgrade_existing_db.sql
```

### Verificar el estado después de migrar

```bash
docker exec -it $(docker-compose ps -q timescale) \
  psql -U postgres -d logmetrics -c \
  "SELECT view_name FROM timescaledb_information.continuous_aggregates;"
```

## Cómo usar las queries de ejemplo

```bash
# Ejecutar cualquier archivo de queries
docker exec -i $(docker-compose ps -q timescale) \
  psql -U postgres -d logmetrics \
  < queries/02_aggregates_por_periodo.sql

# O conectarse de forma interactiva
docker exec -it $(docker-compose ps -q timescale) \
  psql -U postgres -d logmetrics
```

## Consideraciones de red

- El `csvconsumer` (Linux) se conecta a este servicio usando `localhost:5432` cuando corre en el mismo host (gracias a `network_mode: host` en el compose del consumer)
- Si estuviera en un host separado, se usaría la IP LAN del servidor

## CI/CD

Tiene un pipeline de **GitHub Actions** conectado a la rama `main` que valida los archivos al hacer push, asegurando que la definición de infraestructura sea siempre válida antes de llegar a producción.

## Repositorios relacionados

| Repositorio | Relación |
|-------------|----------|
| `csvconsumer` | Se conecta a esta DB para ejecutar los SQL recibidos de RabbitMQ |
| `csvprocessor` | Genera los SQL con el esquema correcto para esta DB |
| `csvshipper-win` | Transporta los SQL al consumer que los ejecuta aquí |

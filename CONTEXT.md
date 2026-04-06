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

## Esquema esperado

La base de datos `logmetrics` debe contener una tabla `log_records` configurada como **hypertable de TimescaleDB** (particionada por tiempo). El esquema exacto lo genera el `csvprocessor` al crear los SQL de inserción.

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

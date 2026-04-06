# TiemscaleDB - Infraestructura de SQL Shipper

Este repositorio contiene la definición como código (IaC) de la Base de Datos central del proyecto SQL Shipper.

Utiliza **TimescaleDB** (PostgreSQL) para alojar de forma robusta las transacciones SQL.

## Levantamiento
Este servicio debe levantarse de forma perimetral antes de arrancar a los consumidores.

```bash
docker-compose up -d
```

## Ci / CD
Cuenta con un pipeline de Github Actions conectado a la rama `main` que valida las subidas.

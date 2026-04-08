# Supported Engines

Wokku supports 9 database engines via Dokku plugins.

## Engines

| Engine | Type | Dokku Plugin |
|--------|------|-------------|
| **PostgreSQL** | Relational | dokku-postgres |
| **MySQL** | Relational | dokku-mysql |
| **MariaDB** | Relational | dokku-mariadb |
| **Redis** | Key-value / Cache | dokku-redis |
| **MongoDB** | Document | dokku-mongo |
| **Memcached** | Cache | dokku-memcached |
| **RabbitMQ** | Message Queue | dokku-rabbitmq |
| **Elasticsearch** | Search | dokku-elasticsearch |
| **MinIO** | Object Storage | dokku-minio |

## Connection URLs

When you link a database to an app, Wokku automatically sets the connection URL as an environment variable:

| Engine | Environment Variable |
|--------|---------------------|
| PostgreSQL | `DATABASE_URL` |
| MySQL | `DATABASE_URL` |
| MariaDB | `DATABASE_URL` |
| Redis | `REDIS_URL` |
| MongoDB | `MONGO_URL` |
| Memcached | `MEMCACHED_URL` |
| RabbitMQ | `RABBITMQ_URL` |
| Elasticsearch | `ELASTICSEARCH_URL` |
| MinIO | `MINIO_URL` |

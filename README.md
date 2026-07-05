# Magento 2 — Boilerplate Docker Compose (manual, sin abstracciones)

Entorno local para Magento Open Source 2.4.8, pensado para levantarse con
`docker compose` puro — sin Warden ni DDEV — para que tengas control total
sobre cada servicio.

## Stack

| Servicio    | Imagen                          | Notas |
|-------------|----------------------------------|-------|
| nginx       | `nginx:1.26-alpine`              | vhost estándar recomendado por Adobe |
| php-fpm     | build local (`docker/php`)       | PHP 8.3 + extensiones requeridas |
| db          | `mariadb:11.4`                   | alternativa gratuita a MySQL 8.4 |
| opensearch  | `opensearchproject/opensearch:2.19.0` | motor de búsqueda obligatorio desde 2.4.x |
| redis       | `redis:7.2-alpine`               | cache y sesiones |
| cron        | build local (mismo `docker/php` que php-fpm) | corre `bin/magento cron:run` cada 60s — sin este servicio los indexers en "Update by Schedule" nunca se procesan solos |
| mailpit     | `axllent/mailpit`                | atrapa los correos que envía Magento (checkout, contraseñas, etc.) |

Deliberadamente **no** incluye Varnish ni RabbitMQ — para desarrollo local no
son indispensables (Magento cae a `db` como backend de colas y a Redis/nginx
como cache). Si más adelante los necesitas, se agregan como dos servicios más
en `docker-compose.yml` sin tocar el resto.

## Por qué estas versiones

Magento Open Source 2.4.8 (la release estable actual, soportada hasta abril
2028) requiere PHP 8.3/8.4, MySQL 8.4 o MariaDB 11.4, OpenSearch 2.19,
Redis 7.2+. Ya existe 2.4.9 (mayo 2026), pero al ser tan reciente muchas
extensiones de terceros todavía no la certifican — por eso el boilerplate
apunta a 2.4.8.

## 1. Preparar el proyecto

```bash
cp .env.example .env
# ajusta PROJECT_NAME, puertos, credenciales de DB si hace falta
```

### Si estás detrás de Netskope (o cualquier proxy con SSL inspection)

Exporta el certificado raíz de Netskope (el mismo que ya usas para
`NODE_EXTRA_CA_CERTS` en Windows) y colócalo aquí:

```
docker/php/certs/corporate-ca.crt
```

El `Dockerfile` de `php-fpm` lo copia al almacén de confianza del
contenedor con `update-ca-certificates` y configura `SSL_CERT_FILE` /
`COMPOSER_CAFILE` para que Composer, curl y PHP confíen en él automáticamente.
Sin esto, `composer create-project` y cualquier llamada a APIs externas
fallarán con errores de certificado dentro del contenedor — el mismo síntoma
que ya viste con Cursor y Claude Code fuera de Docker.

Si no estás en la red de Truper (por ejemplo, trabajando desde casa), deja
la carpeta vacía y este paso se ignora solo.

## 2. Levantar el entorno

```bash
make up        # docker compose up -d
make ps        # ver estado de los contenedores
```

## 3. Instalar Magento Open Source

Como es Open Source, no necesitas llaves de repo.magento.com — el
boilerplate usa el mirror gratuito de Mage-OS:

```bash
mkdir -p src
make install-oss VERSION=2.4.8
```

Esto descarga el código en `./src`, que está montado dentro del contenedor
`php-fpm` en `/var/www/html` y servido por nginx.

Luego, dentro del contenedor:

```bash
make shell

bin/magento setup:install \
  --base-url=http://localhost:8080/ \
  --db-host=db \
  --db-name=magento \
  --db-user=magento \
  --db-password=magento \
  --admin-firstname=Carlos \
  --admin-lastname=Boor \
  --admin-email=carlos.boor@gmail.com \
  --admin-user=admin \
  --admin-password=Admin123! \
  --language=es_MX \
  --currency=MXN \
  --timezone=America/Mexico_City \
  --use-rewrites=1 \
  --search-engine=opensearch \
  --opensearch-host=opensearch \
  --opensearch-port=9200 \
  --cache-backend=redis \
  --cache-backend-redis-server=redis \
  --page-cache=redis \
  --page-cache-redis-server=redis \
  --session-save=redis \
  --session-save-redis-host=redis

bin/magento deploy:mode:set developer
bin/magento indexer:reindex
bin/magento cache:flush
```

Abre `http://localhost:8080/` (storefront) y `http://localhost:8080/admin`
(panel). Mailpit queda en `http://localhost:8025` para revisar los correos
que Magento envía sin necesidad de un SMTP real.

## Estructura de un proyecto Magento 2 (dentro de `src/`)

Esto es lo que vas a encontrar una vez instalado — vale la pena entenderlo
antes de tocar código, porque Magento organiza todo por **módulos** y
**áreas**, no por "páginas" como en un proyecto React típico:

```
src/
├── app/
│   ├── code/                # TU código: módulos propios, en formato Vendor/Module
│   │   └── Vendor/
│   │       └── Module/
│   │           ├── etc/             # module.xml, di.xml, config declarativo
│   │           ├── Controller/      # controladores por área (frontend/adminhtml)
│   │           ├── Block/           # lógica de presentación (ViewModel-ish)
│   │           ├── Model/           # entidades, servicios, repositorios
│   │           ├── Setup/Patch/     # migraciones de esquema y datos
│   │           └── view/
│   │               ├── frontend/    # templates .phtml, layout XML, JS/CSS del storefront
│   │               └── adminhtml/   # lo mismo pero para el panel de admin
│   ├── design/               # temas (herencia de temas, similar a herencia de componentes)
│   └── etc/                  # configuración global de la app (di.xml, config.xml)
├── bin/magento               # CLI — el equivalente al "artisan" de Laravel
├── generated/                # código autogenerado (proxies, interceptors para plugins) — NO se versiona
├── lib/                      # librería interna de Magento (Magento\Framework)
├── pub/                      # document root real de nginx
│   ├── static/                # assets compilados (CSS/JS/imágenes procesadas)
│   └── media/                 # uploads de usuarios/catálogo
├── var/                      # cache, logs, sesiones, reportes — NO se versiona
├── vendor/                    # dependencias de Composer (incluido el propio "core" de Magento)
└── composer.json
```

### Conceptos clave si vienes de React/Node

- **Módulos, no componentes.** La unidad de organización es el módulo
  (`app/code/Vendor/Module`), con su propio `module.xml`, controladores,
  bloques y vistas. Es más parecido a un monorepo de paquetes internos que a
  una estructura de componentes.
- **`di.xml` es tu inyección de dependencias.** Ahí declaras preferencias de
  interfaces, plugins (interceptors, similar a un HOC/middleware que
  envuelve un método) y observers (equivalentes a eventos/pub-sub).
- **Layout XML en vez de JSX.** El árbol de bloques de una página se define
  declarativamente en XML (`view/frontend/layout/*.xml`), y cada bloque
  apunta a un `.phtml` (PHP + HTML, no un motor de templates separado).
- **`bin/magento setup:upgrade` / `di:compile` / `static-content:deploy`**
  son los tres comandos que vas a correr constantemente después de tocar
  módulos, `di.xml` o assets — son el equivalente a un "build" pero por
  etapas.
- **`generated/` y `var/` son descartables.** Igual que `node_modules` o
  `.next`, se regeneran solos; no se versionan.

## Comandos útiles

```bash
make shell     # entra al contenedor de PHP
make logs      # logs de nginx + php-fpm
make restart   # reinicia todos los contenedores
make down      # apaga todo (los datos persisten en volúmenes Docker)
make perf-check   # diagnóstico rápido de rendimiento
make perf-setup   # despliega estáticos + compila DI (tras borrar volúmenes)
make compile      # regenera generated/ si falta Http\Interceptor
```

## Rendimiento en Windows

Magento en Docker Desktop sobre NTFS es lento por defecto. Este boilerplate
mitiga eso con volúmenes Linux para `var/`, `generated/`, `pub/static/` y
`vendor/`, OPcache sin `stat()` por request, php-fpm con 20 workers y estáticos
desplegados (nginx sirve JS/CSS directo, sin pasar por `static.php`).

### Síntomas y soluciones

| Síntoma | Causa probable | Solución |
|---------|----------------|----------|
| 100+ requests JS en pending, carga > 60 s | `pub/static/` vacío | `make perf-setup` |
| `Http\Interceptor does not exist` | `generated/` vacío | `make compile` |
| Error 500, permission denied en `var/` | permisos del volumen | `docker compose restart php-fpm` |
| Todo lento tras `docker compose down -v` | volúmenes borrados | `make perf-setup` |

### Diagnóstico

```bash
make perf-check
```

Objetivo: `static files (luma/es_MX)` > 1000, `js sample time` < 0.05 s.

Tras instalar Magento por primera vez, ejecuta `make perf-setup` una vez
(~15 min). En developer mode la primera carga HTML tras `cache:flush` sigue
siendo más lenta (~5–10 s); las siguientes deberían bajar a ~1–2 s.

## Notas

- Este boilerplate asume desarrollo local. Para producción faltan Varnish,
  TLS real, separación de servicios en hosts distintos y hardening general.
- Si en algún momento prefieres no mantener el `docker-compose.yml` a mano,
  Warden y DDEV hacen exactamente esto mismo mejor empaquetado — quedan como
  opción B si el mantenimiento manual empieza a pesar.

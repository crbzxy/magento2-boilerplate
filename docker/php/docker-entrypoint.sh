#!/bin/bash
set -e

# Volúmenes Docker se crean como root; php-fpm corre como www-data.
for dir in var generated pub/static vendor; do
    if [ -d "/var/www/html/$dir" ]; then
        chown -R www-data:www-data "/var/www/html/$dir"
        chmod -R ug+rwx "/var/www/html/$dir"
    fi
done

if [ ! -f /var/www/html/generated/code/Magento/Framework/App/Http/Interceptor.php ]; then
    echo "WARN: generated/ vacío — ejecuta: make compile" >&2
fi

staticCount=$(find /var/www/html/pub/static/frontend/Magento/luma/es_MX -type f 2>/dev/null | wc -l)
if [ "$staticCount" -lt 100 ]; then
    echo "WARN: pub/static casi vacío ($staticCount archivos) — ejecuta: make perf-setup" >&2
fi

if [ -f /var/www/html/bin/magento ]; then
    chmod +x /var/www/html/bin/magento
fi

exec docker-php-entrypoint "$@"

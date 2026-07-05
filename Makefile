.PHONY: up down shell logs restart install-oss build ps perf-setup compile perf-check cache-flush theme-deploy upgrade diff-luma-base

# Levanta todos los contenedores en segundo plano
up:
	docker compose up -d

# Detiene y elimina los contenedores (conserva volúmenes/datos)
down:
	docker compose down

# Reconstruye la imagen de php-fpm (después de tocar el Dockerfile)
build:
	docker compose build php-fpm

# Entra al contenedor de PHP como shell interactivo
shell:
	docker compose exec php-fpm bash

# Sigue los logs de nginx y php-fpm
logs:
	docker compose logs -f nginx php-fpm

restart:
	docker compose restart

ps:
	docker compose ps

# Limpia cache (tras cambios en .phtml, layout XML, PHP, o LESS en developer mode)
cache-flush:
	docker compose exec php-fpm bin/magento cache:flush

# Despliega estáticos del tema Truper + corrige permisos (tras cambios en LESS/CSS)
#
# En developer mode, setup:static-content:deploy NO recompila los .css ya
# materializados: styles-m.css/styles-l.css se generan una sola vez, al vuelo,
# la primera vez que el navegador los pide (vía static.php), y nginx los sigue
# sirviendo desde disco después aunque cambie el LESS fuente. Por eso este target
# borra los .css compilados del tema antes de redeployar, para forzar que la
# próxima petición los recompile con los cambios de LESS.
theme-deploy:
	docker compose exec php-fpm bash -c 'rm -f pub/static/frontend/Truper/default/*/css/styles-*.css pub/static/frontend/Truper/default/*/css/critical.css'
	docker compose exec php-fpm bin/magento setup:static-content:deploy es_MX -f --theme Truper/default --jobs=4
	docker compose exec php-fpm chown -R www-data:www-data pub/static
	docker compose exec php-fpm bin/magento cache:flush

# Optimización de rendimiento (Windows): despliega estáticos, compila DI y limpia cache.
# Ejecutar tras el primer up o cuando var/generated/pub/static queden vacíos por volúmenes Docker.
# Tarda ~15 min la primera vez; las siguientes son más rápidas.
perf-setup:
	docker compose exec php-fpm bin/magento setup:static-content:deploy es_MX en_US -f --jobs=4
	docker compose exec php-fpm bin/magento setup:di:compile
	docker compose exec php-fpm bin/magento cache:flush

# Script único post-upgrade / post-volumen-borrado: deja el sitio operativo de punta a punta.
# Ejecutar tras `composer update`, `setup:upgrade` manual, cambios en di.xml/módulos,
# o cuando `docker compose down -v` borró generated/pub-static/var.
upgrade:
	docker compose exec php-fpm bin/magento setup:upgrade
	docker compose exec php-fpm bin/magento setup:di:compile
	docker compose exec php-fpm bash -c 'rm -f pub/static/frontend/Truper/default/*/css/styles-*.css pub/static/frontend/Truper/default/*/css/critical.css'
	docker compose exec php-fpm bin/magento setup:static-content:deploy es_MX en_US -f --theme Truper/default --jobs=4
	docker compose exec php-fpm bin/magento indexer:reindex
	docker compose exec php-fpm chown -R www-data:www-data var generated pub/static
	docker compose exec php-fpm bin/magento cache:flush

# Regenera generated/ (fix: "Http\Interceptor does not exist"). Tarda ~8 min.
compile:
	docker compose exec php-fpm bin/magento setup:di:compile
	docker compose exec php-fpm bin/magento cache:flush

# Diagnóstico rápido de rendimiento (developer mode en Windows/Docker).
perf-check:
	docker compose exec php-fpm bash -c '\
		echo "=== Magento perf-check ==="; \
		bin/magento deploy:mode:show; \
		test -f generated/code/Magento/Framework/App/Http/Interceptor.php && echo "generated: OK" || echo "generated: FAIL — ejecuta: make compile"; \
		STATIC=$$(find pub/static/frontend/Truper/default/es_MX -type f 2>/dev/null | wc -l); \
		echo "static files (Truper/default/es_MX): $$STATIC"; \
		[ "$$STATIC" -ge 100 ] 2>/dev/null && echo "static: OK" || echo "static: FAIL — ejecuta: make theme-deploy (o make upgrade)"; \
		JS=$$(curl -s -o /dev/null -w "%{time_total}" http://nginx/static/frontend/Truper/default/es_MX/requirejs/require.js); \
		echo "js sample time: $${JS}s (objetivo: < 0.05s)"; \
	'

# Detecta si _luma-base.less (copia manual de Luma _theme.less) se desincronizó
# tras un upgrade de Magento/Luma. Correr después de `composer update`.
diff-luma-base:
	docker compose exec php-fpm diff \
		app/design/frontend/Truper/default/web/css/source/_luma-base.less \
		vendor/magento/theme-frontend-luma/web/css/source/_theme.less \
		&& echo "diff-luma-base: sin cambios" \
		|| echo "diff-luma-base: _luma-base.less desincronizado — revisar diff arriba y actualizar"

# Descarga Magento Open Source dentro de ./src usando composer
# (requiere que la carpeta src/ esté vacía).
# Uso: make install-oss VERSION=2.4.8
install-oss:
	docker compose run --rm php-fpm composer create-project \
		--repository-url=https://mirror.mage-os.org/ \
		magento/project-community-edition=$(VERSION) /var/www/html

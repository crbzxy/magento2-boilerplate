.PHONY: up down shell logs restart install-oss build ps perf-setup compile perf-check

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

# Optimización de rendimiento (Windows): despliega estáticos, compila DI y limpia cache.
# Ejecutar tras el primer up o cuando var/generated/pub/static queden vacíos por volúmenes Docker.
# Tarda ~15 min la primera vez; las siguientes son más rápidas.
perf-setup:
	docker compose exec php-fpm bin/magento setup:static-content:deploy es_MX en_US -f --jobs=4
	docker compose exec php-fpm bin/magento setup:di:compile
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
		STATIC=$$(find pub/static/frontend/Magento/luma/es_MX -type f 2>/dev/null | wc -l); \
		echo "static files (luma/es_MX): $$STATIC"; \
		[ "$$STATIC" -ge 100 ] 2>/dev/null && echo "static: OK" || echo "static: FAIL — ejecuta: make perf-setup"; \
		JS=$$(curl -s -o /dev/null -w "%{time_total}" http://nginx/static/frontend/Magento/luma/es_MX/requirejs/require.js); \
		echo "js sample time: $${JS}s (objetivo: < 0.05s)"; \
	'

# Descarga Magento Open Source dentro de ./src usando composer
# (requiere que la carpeta src/ esté vacía).
# Uso: make install-oss VERSION=2.4.8
install-oss:
	docker compose run --rm php-fpm composer create-project \
		--repository-url=https://mirror.mage-os.org/ \
		magento/project-community-edition=$(VERSION) /var/www/html

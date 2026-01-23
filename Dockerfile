FROM php:8.1-apache

# 1. Installazione dipendenze di sistema
RUN apt-get update && apt-get install -y \
    git unzip libzip-dev libpng-dev libjpeg-dev libfreetype6-dev \
    curl libxml2-dev libicu-dev libonig-dev \
    && rm -rf /var/lib/apt/lists/*

# 2. Estensioni PHP
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
    zip gd mysqli pdo pdo_mysql opcache intl xml mbstring

# 3. Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# 4. Directory di lavoro e copia file
WORKDIR /var/www/html
COPY . .

# 5. Installazione dipendenze con pulizia cache
RUN git config --global url."https://github.com/".insteadOf "git@github.com:" && \
    rm -f composer.lock && \
    composer clear-cache && \
    composer install --no-dev --optimize-autoloader --no-interaction --no-scripts

# 6. Permessi e Mod rewrite
RUN a2enmod rewrite && \
    chown -R www-data:www-data /var/www/html && \
    chmod -R 775 /var/www/html/data /var/www/html/config

# 7. CMD: Avvio e Installazione
CMD sed -i "s/Listen 80/Listen 8080/g" /etc/apache2/ports.conf; \
    sed -i "s/<VirtualHost \*:80>/<VirtualHost \*:8080>/g" /etc/apache2/sites-available/000-default.conf; \
    \
    if [ ! -f /var/www/html/config/generis/database.conf.php ]; then \
        echo "Inizio installazione pulita di TAO..."; \
        php /var/www/html/tao/scripts/taoInstall.php \
        --db_driver pdo_mysql \
        --db_host ${MYSQLHOST} \
        --db_port ${MYSQLPORT} \
        --db_name ${MYSQLDATABASE} \
        --db_user ${MYSQLUSER} \
        --db_pass ${MYSQLPASSWORD} \
        --module_namespace http://sample/first.rdf \
        --module_url https://${RAILWAY_STATIC_URL:-localhost} \
        --user_login admin \
        --user_pass admin \
        -vvv -e taoCe,taoInvalsi; \
    fi; \
    \
    echo "Avvio Apache sulla porta 8080..."; \
    apache2-foreground

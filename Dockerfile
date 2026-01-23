FROM php:8.1-apache

# Dichiarazione ARG obbligatoria per Railway
ARG GITHUB_TOKEN
ENV GITHUB_TOKEN=$GITHUB_TOKEN

RUN apt-get update && apt-get install -y \
    git unzip libzip-dev libpng-dev libjpeg-dev libfreetype6-dev \
    curl libxml2-dev libicu-dev libonig-dev \
    && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) zip gd mysqli pdo pdo_mysql opcache intl xml mbstring

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html
COPY . .

# --- SEZIONE CRITICA ---
# Creiamo il file auth.json manualmente prima di installare
RUN git config --global url."https://github.com/".insteadOf "git@github.com:" && \
    echo "{\"github-oauth\": {\"github.com\": \"$GITHUB_TOKEN\"}}" > /root/.composer/auth.json && \
    rm -f composer.lock && \
    composer install --no-dev --optimize-autoloader --no-interaction --no-scripts
# -----------------------

RUN a2enmod rewrite && \
    chown -R www-data:www-data /var/www/html && \
    chmod -R 775 /var/www/html/data /var/www/html/config

CMD sed -i "s/Listen 80/Listen 8080/g" /etc/apache2/ports.conf; \
    sed -i "s/<VirtualHost \*:80>/<VirtualHost \*:8080>/g" /etc/apache2/sites-available/000-default.conf; \
    if [ ! -f /var/www/html/config/generis/database.conf.php ]; then \
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
    apache2-foreground

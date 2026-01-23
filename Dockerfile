FROM php:8.1-apache

# 1. Argomenti e variabili d'ambiente
ARG COMPOSER_AUTH
ENV COMPOSER_AUTH=${COMPOSER_AUTH}
ENV NVM_DIR=/root/.nvm
ENV NODE_VERSION=14.21.3

# 2. Installazione dipendenze di sistema
RUN apt-get update && apt-get install -y \
    git \
    unzip \
    libzip-dev \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    curl \
    libxml2-dev \
    libicu-dev \
    libonig-dev \
    && rm -rf /var/lib/apt/lists/*

# 3. Estensioni PHP
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
    zip gd mysqli pdo pdo_mysql opcache intl xml mbstring

# 4. Node.js 14
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash && \
    . "$NVM_DIR/nvm.sh" && nvm install $NODE_VERSION && nvm alias default $NODE_VERSION
ENV PATH=$NVM_DIR/versions/node/v$NODE_VERSION/bin:$PATH

# 5. Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# 6. Directory di lavoro
WORKDIR /var/www/html
COPY . .

# 7. Dipendenze applicazione
RUN git config --global url."https://github.com/".insteadOf "git@github.com:" && \
    composer install --no-dev --optimize-autoloader --no-interaction

# 8. Abilita Rewrite
RUN a2enmod rewrite

# 9. Permessi iniziali
RUN chown -R www-data:www-data /var/www/html && \
    chmod -R 775 /var/www/html/data /var/www/html/config

# 10. CMD: Script di avvio pulito e senza commenti interni
CMD rm -f /etc/apache2/mods-enabled/mpm_event.* /etc/apache2/mods-enabled/mpm_worker.* || true; \
    a2enmod mpm_prefork || true; \
    sed -i "s/Listen 80/Listen 8080/g" /etc/apache2/ports.conf; \
    sed -i "s/<VirtualHost \*:80>/<VirtualHost \*:8080>/g" /etc/apache2/sites-available/000-default.conf; \
    if [ -f /var/www/html/config/generis/database.conf.php ]; then \
        echo "Tabelle trovate. Pulizia cache..."; \
        rm -rf /var/www/html/data/generis/cache/* || true; \
    else \
        echo "Inizio installazione TAO..."; \
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
        -vvv -e taoCe; \
    fi; \
    chown -R www-data:www-data /var/www/html/data /var/www/html/config /var/www/html/models; \
    chmod -R 775 /var/www/html/data /var/www/html/config; \
    echo "Avvio Apache sulla porta 8080..."; \
    apache2-foreground

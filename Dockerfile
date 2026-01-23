FROM php:8.1-apache

# Usa COMPOSER_AUTH invece di GITHUB_TOKEN
ARG COMPOSER_AUTH
ENV COMPOSER_AUTH=$COMPOSER_AUTH

RUN apt-get update && apt-get install -y \
    git unzip libzip-dev libpng-dev libjpeg-dev libfreetype6-dev \
    curl libxml2-dev libicu-dev libonig-dev \
    && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) zip gd mysqli pdo pdo_mysql opcache intl xml mbstring

# Imposta le variabili d'ambiente per NVM e Node
ENV NVM_DIR=/root/.nvm
ENV NODE_VERSION=14.21.3

# Installa NVM e Node.js 14
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash \
    && . $NVM_DIR/nvm.sh \
    && nvm install $NODE_VERSION \
    && nvm alias default $NODE_VERSION \
    && nvm use default

# Aggiunge i binari di Node al PATH
ENV PATH=$NVM_DIR/versions/node/v$NODE_VERSION/bin:$PATH

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

COPY . .

# Configurazione Git e Installazione dipendenze
RUN git config --global url."https://github.com/".insteadOf "git@github.com:" && \
    git config --global url."https://".insteadOf "git://" && \
    rm -f composer.lock && \
    composer install --no-dev --optimize-autoloader --no-interaction --no-scripts

RUN a2enmod rewrite && \
    chown -R www-data:www-data /var/www/html && \
    chmod -R 775 /var/www/html/data /var/www/html/config

CMD a2dismod mpm_event mpm_worker 2>/dev/null || true; \
    a2enmod mpm_prefork; \
    sed -i "s/Listen 80/Listen 8080/g" /etc/apache2/ports.conf; \
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
        -vvv -e taoCe; \
    fi; \
    apache2-foreground

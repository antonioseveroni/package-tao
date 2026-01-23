FROM php:8.1-apache

# 1. Argomenti e variabili d'ambiente per Composer/Node
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

# 3. Installazione estensioni PHP (incluse quelle necessarie per TAO)
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
    zip \
    gd \
    mysqli \
    pdo \
    pdo_mysql \
    opcache \
    intl \
    xml \
    mbstring

# 4. Installazione Node.js 14 via NVM
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash && \
    . "$NVM_DIR/nvm.sh" && \
    nvm install $NODE_VERSION && \
    nvm alias default $NODE_VERSION && \
    nvm use default
ENV NODE_PATH=$NVM_DIR/versions/node/v$NODE_VERSION/lib/node_modules
ENV PATH=$NVM_DIR/versions/node/v$NODE_VERSION/bin:$PATH

# 5. Installazione Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# 6. Configurazione directory di lavoro e copia file
WORKDIR /var/www/html
COPY . .

# 7. Installazione dipendenze dell'applicazione
RUN git config --global url."https://github.com/".insteadOf "git@github.com:" && \
    git config --global url."https://".insteadOf "git://" && \
    composer install --no-dev --optimize-autoloader --no-interaction

# 8. Configurazione Apache (abilitazione moduli necessari)
RUN a2enmod rewrite

# 9. Permessi per TAO (data e config devono essere scrivibili)
RUN chown -R www-data:www-data /var/www/html && \
    chmod -R 775 /var/www/html/data /var/www/html/config

# 10. CMD: Script di avvio corretto
CMD rm -f /etc/apache2/mods-enabled/mpm_event.* /etc/apache2/mods-enabled/mpm_worker.* || true; \
    a2enmod mpm_prefork || true; \
    sed -i "s/80/${PORT}/g" /etc/apache2/sites-available/000-default.conf /etc/apache2/ports.conf; \
    echo "error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT" > /usr/local/etc/php/conf.d/error_logging.ini; \
    echo "Verifica connessione al database..."; \
    php -r "\$c=@mysqli_connect('${MYSQLHOST}', '${MYSQLUSER}', '${MYSQLPASSWORD}', '${MYSQLDATABASE}', '${MYSQLPORT}'); if(!\$c){echo 'ERRORE: Database non raggiungibile'.PHP_EOL; exit(1);} echo 'Database connesso!'.PHP_EOL;"; \
    if [ $? -eq 0 ]; then \
        if [ ! -f /var/www/html/config/generis/database.conf.php ]; then \
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
        else \
            echo "TAO risulta gia configurato."; \
        fi; \
    fi; \
    echo "Avvio Apache..."; \
    apache2-foreground

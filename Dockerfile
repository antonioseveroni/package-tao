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

# Disabilita la visualizzazione degli errori nell'output (va nei log di Railway invece)
RUN echo "display_errors = Off" >> /usr/local/etc/php/conf.d/docker-php-errors.ini && \
    echo "error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT" >> /usr/local/etc/php/conf.d/docker-php-errors.ini
    
COPY . .

# Crea le cartelle necessarie prima di composer install
RUN mkdir -p data config/generis && \
    chmod -R 775 data config

# Configurazione Git e Installazione dipendenze
RUN export PATH=$NVM_DIR/versions/node/v$NODE_VERSION/bin:$PATH && \
    git config --global url."https://github.com/".insteadOf "git@github.com:" && \
    git config --global url."https://".insteadOf "git://" && \
    rm -f composer.lock && \
    composer install --no-dev --optimize-autoloader --no-interaction

# Esegui gli script post-install di composer
RUN composer run-script post-install-cmd || true

RUN a2enmod rewrite && \
    chown -R www-data:www-data /var/www/html && \
    chmod -R 775 /var/www/html/data /var/www/html/config

# Configura Apache durante il build - Fix MPM e ServerName
RUN echo "ServerName localhost" >> /etc/apache2/apache2.conf && \
    rm -f /etc/apache2/mods-enabled/mpm_event.load \
         /etc/apache2/mods-enabled/mpm_event.conf \
         /etc/apache2/mods-enabled/mpm_worker.load \
         /etc/apache2/mods-enabled/mpm_worker.conf && \
    a2enmod mpm_prefork && \
    sed -i "s/Listen 80/Listen 8080/g" /etc/apache2/ports.conf && \
    sed -i "s/<VirtualHost \*:80>/<VirtualHost \*:8080>/g" /etc/apache2/sites-available/000-default.conf

# ... (parte iniziale del Dockerfile invariata) ...

COPY <<'EOF' /start.sh
#!/bin/bash

# 1. Configurazione porta Railway
sed -i "s/Listen 8080/Listen ${PORT:-8080}/g" /etc/apache2/ports.conf
sed -i "s/<VirtualHost \*:8080>/<VirtualHost \*:${PORT:-8080}>/g" /etc/apache2/sites-available/000-default.conf

# 2. Fix Apache MPM
rm -f /etc/apache2/mods-enabled/mpm_event.* /etc/apache2/mods-enabled/mpm_worker.*
a2enmod mpm_prefork 2>/dev/null || true

# 3. Installazione Core taoCe
if [ ! -f /var/www/html/config/tao/SessionCookieService.conf.php ]; then
    echo "Installazione Core in corso..."
    rm -f /var/www/html/config/generis/database.conf.php
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
    -vvv -e taoCe
fi

# 4. Installazione taoInvalsi con verifica cartella
# Cerchiamo la cartella corretta (potrebbe chiamarsi taoInvalsi o TAO-INVALSI-CUSTOMIZATION)
EXT_NAME="taoInvalsi"
if [ ! -d "/var/www/html/$EXT_NAME" ]; then
    # Se non esiste taoInvalsi, proviamo a vedere se la cartella è TAO-INVALSI-CUSTOMIZATION
    if [ -d "/var/www/html/TAO-INVALSI-CUSTOMIZATION" ]; then
        EXT_NAME="TAO-INVALSI-CUSTOMIZATION"
    fi
fi

echo "Tentativo installazione estensione: $EXT_NAME"
# Eseguiamo il comando forzando l'argomento tra virgolette per evitare l'errore "Usage"
php /var/www/html/tao/scripts/installExtension.php "$EXT_NAME" && echo "Installazione $EXT_NAME completata." || echo "Errore installazione $EXT_NAME."

# Pulizia finale
php /var/www/html/tao/scripts/taoUpdate.php -vv || true
chown -R www-data:www-data /var/www/html
apache2-foreground
EOF

RUN chmod +x /start.sh

CMD ["/start.sh"]

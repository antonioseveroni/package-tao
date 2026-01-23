FROM php:8.1-apache

# Accept COMPOSER_AUTH as build argument
ARG COMPOSER_AUTH
ENV COMPOSER_AUTH=${COMPOSER_AUTH}

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    unzip \
    libzip-dev \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install PHP extensions
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
    zip \
    gd \
    mysqli \
    pdo \
    pdo_mysql \
    opcache

# Install Node.js 14 via NVM
SHELL ["/bin/bash", "-c"]
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash && \
    source "$HOME/.nvm/nvm.sh" && \
    nvm install 14 && \
    nvm use 14 && \
    nvm alias default 14 && \
    ln -s "$HOME/.nvm/versions/node/v14.*/bin/node" /usr/local/bin/node && \
    ln -s "$HOME/.nvm/versions/node/v14.*/bin/npm" /usr/local/bin/npm

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Set working directory
WORKDIR /var/www/html

# Copy application files
COPY . .

# Configure git and install dependencies
RUN git config --global url."https://github.com/".insteadOf "git@github.com:" && \
    git config --global url."https://".insteadOf "git://" && \
    composer install --no-dev --optimize-autoloader --no-interaction

# Apache configuration
RUN a2enmod rewrite

# Set proper permissions
RUN chown -R www-data:www-data /var/www/html

# Expose port
EXPOSE 80

CMD ["apache2-foreground"]

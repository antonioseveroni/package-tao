FROM php:8.1-apache

# Install system dependencies and PHP extensions
RUN apt-get update && apt-get install -y \
    git \
    unzip \
    libzip-dev \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
    zip \
    gd \
    mysqli \
    pdo \
    pdo_mysql \
    opcache

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Set working directory
WORKDIR /var/www/html

# Copy application files
COPY . .

# Install dependencies
COPY composer-setup.sh .
RUN chmod +x composer-setup.sh && ./composer-setup.sh

# Apache configuration
RUN a2enmod rewrite

# Expose port
EXPOSE 80

CMD ["apache2-foreground"]

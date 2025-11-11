#!/bin/bash

# Laravel Forge Deployment Script
# Optimized for large applications

cd /home/prdevpel/pr-test-devpel.on-forge.com
git pull origin main

# Install composer dependencies with increased memory
php -d memory_limit=2048M /usr/local/bin/composer install --no-interaction --prefer-dist --optimize-autoloader --no-dev

# Run migrations (if any)
php -d memory_limit=2048M artisan migrate --force

# Clear all caches
php -d memory_limit=2048M artisan cache:clear
php -d memory_limit=2048M artisan config:clear
php -d memory_limit=2048M artisan view:clear

# Cache config only (skip routes due to memory)
php -d memory_limit=2048M artisan config:cache

# Optimize autoloader
php -d memory_limit=2048M artisan optimize

# Restart queue workers
php -d memory_limit=2048M artisan queue:restart

echo "Deployment completed successfully!"

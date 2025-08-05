#!/bin/bash

# Variables
REPO_URL="https://github.com/dstacks2024-droid/Cloudtv-Panel.git"
INSTALL_DIR="/var/www/cloudtv"
MYSQL_PASSWORD="CloudTVpass123"
DOMAIN="yourdomain.com"

echo "Updating system..."
apt update && apt upgrade -y

echo "Installing dependencies..."
apt install -y curl gnupg build-essential nginx mysql-server ffmpeg git

echo "Installing Node.js LTS..."
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt install -y nodejs

echo "Installing PM2..."
npm install -g pm2

echo "Cloning GitHub repo..."
git clone $REPO_URL $INSTALL_DIR
cd $INSTALL_DIR

echo "Installing backend dependencies..."
cd backend
npm install

echo "Setting up database..."
mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_PASSWORD'; FLUSH PRIVILEGES;"
mysql -u root -p$MYSQL_PASSWORD < database/init.sql

echo "Starting backend with PM2..."
pm2 start server.js --name cloudtv-backend
pm2 save
pm2 startup systemd

echo "Building frontend..."
cd ../frontend
npm install
npm run build

echo "Setting up NGINX config..."
cat > /etc/nginx/sites-available/cloudtv <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    root $INSTALL_DIR/frontend/build;
    index index.html;

    location /api/ {
        proxy_pass http://localhost:8080/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }

    location / {
        try_files \$uri /index.html;
    }
}
EOF

ln -s /etc/nginx/sites-available/cloudtv /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

echo "✅ CloudTV Panel is now installed."
echo "Visit: http://$DOMAIN"

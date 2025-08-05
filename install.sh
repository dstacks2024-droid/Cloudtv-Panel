#!/bin/bash

# === CONFIGURE THESE ===
MYSQL_ROOT_PASSWORD="CloudTVpass123"
DOMAIN_NAME="" # Leave blank to skip SSL (e.g., yourdomain.com)
FRONTEND_DIR="frontend"
BACKEND_DIR="backend"

# === System Update ===
apt update && apt upgrade -y

# === Install Required Packages ===
apt install -y curl gnupg2 software-properties-common build-essential nginx mysql-server ffmpeg

# === Install Node.js 18 ===
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

# === Install PM2 ===
npm install -g pm2

# === Secure MySQL and Create DB ===
echo "Securing MySQL..."
mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
CREATE DATABASE IF NOT EXISTS cloudtv CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
EOF

# === Set Up Backend ===
echo "Setting up backend..."
cd $BACKEND_DIR
npm install
cp .env.example .env 2>/dev/null
sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=${MYSQL_ROOT_PASSWORD}/" .env
pm2 start index.js --name cloudtv-api
pm2 save
cd ..

# === Set Up Frontend ===
echo "Setting up frontend build..."
cd $FRONTEND_DIR
npm install
npm run build
cd ..

# === Configure NGINX ===
echo "Configuring NGINX..."
cat > /etc/nginx/sites-available/cloudtv <<EOL
server {
    listen 80;
    server_name ${DOMAIN_NAME};

    root /var/www/cloudtv;
    index index.html;

    location / {
        try_files \$uri /index.html;
    }

    location /api/ {
        proxy_pass http://localhost:8080/api/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOL

# === Deploy Frontend ===
rm -rf /var/www/cloudtv
cp -r $FRONTEND_DIR/build /var/www/cloudtv

ln -s /etc/nginx/sites-available/cloudtv /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

# === Install SSL if domain is set ===
if [ ! -z "$DOMAIN_NAME" ]; then
    echo "Installing Certbot SSL..."
    apt install -y certbot python3-certbot-nginx
    certbot --nginx -d $DOMAIN_NAME --non-interactive --agree-tos -m admin@$DOMAIN_NAME
fi

# === Enable Services on Boot ===
systemctl enable mysql
systemctl enable nginx
pm2 startup systemd -u $(whoami) --hp $HOME
pm2 save

echo "✅ CloudTV installation complete."
echo "Frontend: http://${DOMAIN_NAME:-your_server_ip}"
echo "Backend API: http://localhost:8080/api/"

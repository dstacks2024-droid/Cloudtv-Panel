#!/bin/bash

# Set MySQL root password
MYSQL_ROOT_PASSWORD="CloudTVpass123"

echo "Updating system..."
apt update && apt upgrade -y

echo "Installing dependencies..."
apt install -y curl wget gnupg software-properties-common ffmpeg nginx

echo "Installing Node.js (LTS)..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

echo "Installing PM2..."
npm install -g pm2

echo "Installing MySQL..."
DEBIAN_FRONTEND=noninteractive apt install -y mysql-server
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}'; FLUSH PRIVILEGES;"

echo "Cloning CloudTV Panel..."
mkdir -p /opt/cloudtv
cd /opt/cloudtv
git clone https://github.com/dstacks2024-droid/Cloudtv-Panel.git .
cd backend
npm install

echo "Starting backend with PM2..."
pm2 start index.js --name cloudtv-backend
pm2 save
pm2 startup systemd -u $USER --hp $HOME

echo "Deploying frontend..."
mkdir -p /var/www/html
cp -r ../frontend/* /var/www/html/

echo "Configuring Nginx..."
cat >/etc/nginx/sites-available/cloudtv <<EOL
server {
    listen 80;
    server_name _;

    location /api/ {
        proxy_pass http://localhost:8000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }

    location / {
        root /var/www/html;
        index index.html;
        try_files \$uri \$uri/ =404;
    }
}
EOL

ln -sf /etc/nginx/sites-available/cloudtv /etc/nginx/sites-enabled/cloudtv
rm -f /etc/nginx/sites-enabled/default

echo "Restarting Nginx..."
systemctl restart nginx
systemctl enable nginx

echo "Cloud TV panel installed and running."
echo "Visit your server IP to see the frontend."

#!/bin/bash
set -e

MYSQL_ROOT_PASSWORD="CloudTVpass123"
DEPLOY_ZIP_URL="https://www.dropbox.com/scl/fo/xmmyvtptze8k5y1teile5/AMTABiEqtAwJ1yntfBona1s?rlkey=vxdn6duquzh27rezpzgoqdhn1&dl=1"

echo "🔧 Starting CloudTV installation..."

apt update && apt upgrade -y
apt install -y curl wget git unzip nginx mysql-server ffmpeg build-essential

curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs
npm install -g pm2

systemctl enable mysql
systemctl start mysql
mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
EOF

mkdir -p /opt/cloudtv
cd /opt/cloudtv
wget -O CloudTV_Deploy.zip "$DEPLOY_ZIP_URL"
unzip -o CloudTV_Deploy.zip -d /opt/cloudtv

cd /opt/cloudtv/backend
npm install
pm2 start index.js --name cloudtv-backend
pm2 save
pm2 startup systemd -u $USER --hp $HOME

FRONTEND_DIR="/opt/cloudtv/frontend"
if [ -d "$FRONTEND_DIR" ]; then
    rm -rf /var/www/html/*
    cp -r "$FRONTEND_DIR"/* /var/www/html/
else
    echo "❌ ERROR: Frontend directory not found!"
    exit 1
fi

cat >/etc/nginx/sites-available/default <<EOL
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.html;
    server_name _;

    location /api/ {
        proxy_pass http://localhost:3000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOL

systemctl restart nginx

echo ""
echo "✅ CloudTV Installation Complete!"
echo "🌐 Visit your panel at: http://<YOUR_SERVER_IP>"
echo "🛠 Backend running with PM2 as: cloudtv-backend"
echo "🔐 MySQL Root Password: ${MYSQL_ROOT_PASSWORD}"
echo ""

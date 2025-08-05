#!/bin/bash

echo "🔧 Updating system and installing dependencies..."
sudo apt update
sudo apt install -y curl gnupg lsb-release ca-certificates apt-transport-https software-properties-common

echo "📦 Installing Node.js..."
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

echo "📦 Installing MySQL Server..."
sudo apt install -y mysql-server

echo "🔐 Setting MySQL root password..."
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'CloudTVpass123'; FLUSH PRIVILEGES;"

echo "📦 Installing PM2..."
sudo npm install -g pm2
pm2 startup systemd -u $USER --hp $HOME

echo "📦 Installing Nginx and FFmpeg..."
sudo apt install -y nginx ffmpeg

echo "🌐 Cloning CloudTV Panel from GitHub..."
git clone https://github.com/dstacks2024-droid/Cloudtv-Panel.git /opt/cloudtv

echo "🚀 Setting up Backend..."
cd /opt/cloudtv/backend || exit 1
npm install
pm2 start index.js --name cloudtv
pm2 save

echo "🌐 Setting up Frontend..."
sudo cp -r /opt/cloudtv/frontend/* /var/www/html/

echo "⚙️ Configuring Nginx..."
sudo tee /etc/nginx/sites-available/cloudtv <<EOF
server {
    listen 80;
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
        root /var/www/html;
        index index.html index.htm;
    }
}
EOF

sudo ln -s /etc/nginx/sites-available/cloudtv /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo systemctl restart nginx

echo "✅ CloudTV Panel installation complete!"

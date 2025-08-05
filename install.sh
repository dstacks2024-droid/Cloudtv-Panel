#!/bin/bash

# Cloud TV Install Script

echo "📦 Installing dependencies..."

# Update packages
sudo apt update && sudo apt upgrade -y

# Install Node.js (LTS), MySQL, Nginx, FFmpeg, Git, unzip
sudo apt install -y nodejs npm mysql-server nginx ffmpeg git unzip curl

# Setup MySQL root password
echo "🔐 Configuring MySQL..."
sudo mysql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'CloudTVpass123';
FLUSH PRIVILEGES;
EOF

# Clone GitHub repo
echo "📁 Cloning CloudTV repo..."
mkdir -p /opt/cloudtv
cd /opt/cloudtv
git clone https://github.com/dstacks2024-droid/Cloudtv-Panel.git .
npm install

# Start backend with PM2
echo "🚀 Starting backend with PM2..."
sudo npm install -g pm2
pm2 start index.js --name cloudtv-backend
pm2 save
pm2 startup systemd
sudo env PATH=$PATH:/usr/bin pm2 startup systemd -u $USER --hp $HOME

# Deploy frontend
echo "🌐 Deploying frontend..."
sudo rm -rf /var/www/html/*
sudo cp index.html /var/www/html/
sudo systemctl restart nginx

# Configure Nginx reverse proxy
echo "🔧 Setting up Nginx reverse proxy..."

sudo bash -c 'cat > /etc/nginx/sites-available/cloudtv <<EOF
server {
    listen 80;
    server_name _;

    location /api/ {
        proxy_pass http://localhost:8000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }

    location / {
        root /var/www/html;
        index index.html index.htm;
    }
}
EOF'

sudo ln -sf /etc/nginx/sites-available/cloudtv /etc/nginx/sites-enabled/cloudtv
sudo nginx -t && sudo systemctl reload nginx

echo "✅ Cloud TV panel installed and running."
echo "Visit your server IP to see the frontend."

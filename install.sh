
#!/bin/bash

set -e

echo "🚀 Starting CloudTV Panel installation..."

# Update system packages
sudo apt update && sudo apt upgrade -y

# Install dependencies
sudo apt install -y curl wget gnupg2 ca-certificates lsb-release apt-transport-https software-properties-common unzip ffmpeg

# Install Node.js (LTS)
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

# Install PM2 globally
sudo npm install -g pm2

# Install MySQL and set root password
sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password password CloudTVpass123'
sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password CloudTVpass123'
sudo apt install -y mysql-server

# Install Nginx
sudo apt install -y nginx

# Clone CloudTV repo
sudo git clone https://github.com/dstacks2024-droid/Cloudtv-Panel.git /opt/cloudtv

# Backend Setup
cd /opt/cloudtv/backend
sudo npm install
pm2 start index.js --name cloudtv-backend
pm2 save
pm2 startup systemd -u $USER --hp $HOME

# Frontend Setup
sudo mkdir -p /var/www/html
sudo cp -r /opt/cloudtv/frontend/* /var/www/html/
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html

# Nginx Configuration
sudo bash -c 'cat > /etc/nginx/sites-available/cloudtv <<EOF
server {
    listen 80;
    server_name _;

    root /var/www/html;
    index index.html;

    location /api/ {
        proxy_pass http://localhost:8000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF'

sudo ln -sf /etc/nginx/sites-available/cloudtv /etc/nginx/sites-enabled/cloudtv
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl restart nginx

echo "✅ Cloud TV panel installed and running."
echo "🌐 Visit: http://<YOUR_SERVER_IP>"

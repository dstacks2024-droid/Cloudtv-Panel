#!/bin/bash

# --- SETUP VARIABLES ---
MYSQL_ROOT_PASS="CloudTVpass123"
REPO_URL="https://github.com/dstacks2024-droid/Cloudtv-Panel.git"
INSTALL_DIR="/opt/cloudtv"

echo "🔧 Updating system..."
apt update && apt upgrade -y

echo "📦 Installing dependencies..."
apt install -y curl wget gnupg ffmpeg nginx mysql-server build-essential git

# --- NODEJS INSTALL ---
echo "📦 Installing Node.js LTS..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

# --- PM2 INSTALL ---
npm install -g pm2

# --- MySQL CONFIG ---
echo "🛠️ Configuring MySQL..."
systemctl start mysql
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASS}'; FLUSH PRIVILEGES;" || true

# --- CLONE PROJECT ---
echo "📁 Cloning Cloud TV Panel from GitHub..."
rm -rf "$INSTALL_DIR"
git clone "$REPO_URL" "$INSTALL_DIR"

# --- INSTALL BACKEND ---
echo "⚙️ Setting up backend..."
cd "$INSTALL_DIR/backend" || exit
npm install
pm2 start index.js --name cloudtv-backend
pm2 save
pm2 startup systemd -u $USER --hp $HOME

# --- INSTALL FRONTEND ---
echo "⚙️ Setting up frontend..."
cd "$INSTALL_DIR/frontend" || exit
npm install
npm run build

# --- NGINX CONFIG ---
echo "🌐 Configuring Nginx to serve frontend..."

cat > /etc/nginx/sites-available/cloudtv <<EOF
server {
    listen 80;
    server_name _;

    root $INSTALL_DIR/frontend/dist;
    index index.html;

    location /api/ {
        proxy_pass http://localhost:3000/;
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

ln -sf /etc/nginx/sites-available/cloudtv /etc/nginx/sites-enabled/cloudtv
rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx
systemctl enable nginx

# --- DONE ---
echo ""
echo "✅ Cloud TV Panel is now installed and running!"
echo "🌐 Visit http://<your-server-ip> to access the panel."
echo "⚙️ MySQL root password: ${MYSQL_ROOT_PASS}"

#!/bin/bash

# --- Configuration variables ---
DB_ROOT_PASS="RootPass123!"   # Change this before running for security
DB_NAME="iptv_panel"
DB_USER="iptvuser"
DB_PASS="iptvpass123"
ADMIN_USER="admin"
ADMIN_EMAIL="admin@example.com"
ADMIN_PASS="admin123"
WEB_ROOT="/var/www/iptv-panel"

# --- Update system and install packages ---
echo "[1/10] Updating system and installing required packages..."
apt update && apt upgrade -y
apt install -y apache2 mysql-server php php-mysql php-xml php-mbstring php-curl php-gd unzip curl libapache2-mod-php

# Enable mod_rewrite for Apache
echo "[2/10] Enabling Apache mod_rewrite..."
a2enmod rewrite

# Restart Apache to apply mods
systemctl restart apache2

# --- Secure MySQL (noninteractive) ---
echo "[3/10] Securing MySQL installation and setting root password..."
# Set root password and remove anonymous users, disallow remote root login, remove test db, reload privileges
mysql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_ROOT_PASS';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

# --- Create IPTV panel database and user ---
echo "[4/10] Creating MySQL database and user for IPTV panel..."
mysql -uroot -p"$DB_ROOT_PASS" <<EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

# --- Create database tables ---
echo "[5/10] Creating database tables..."
mysql -u"$DB_USER" -p"$DB_PASS" $DB_NAME <<EOF
CREATE TABLE IF NOT EXISTS users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(50) UNIQUE NOT NULL,
  email VARCHAR(100) NOT NULL,
  password VARCHAR(255) NOT NULL,
  role ENUM('admin','user') DEFAULT 'user',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS streams (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  stream_url TEXT NOT NULL,
  created_by INT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS epg (
  id INT AUTO_INCREMENT PRIMARY KEY,
  channel_name VARCHAR(255),
  start_time DATETIME,
  end_time DATETIME,
  title VARCHAR(255),
  description TEXT
);
EOF

# --- Create initial admin user ---
echo "[6/10] Creating initial admin user..."
HASHED_PASS=$(php -r "echo password_hash('$ADMIN_PASS', PASSWORD_DEFAULT);")
mysql -u"$DB_USER" -p"$DB_PASS" $DB_NAME <<EOF
INSERT INTO users (username, email, password, role) VALUES
('$ADMIN_USER', '$ADMIN_EMAIL', '$HASHED_PASS', 'admin')
ON DUPLICATE KEY UPDATE username=username;
EOF

# --- Setup web root ---
echo "[7/10] Setting up web root and panel files..."

mkdir -p $WEB_ROOT/public
chown -R www-data:www-data $WEB_ROOT
chmod -R 755 $WEB_ROOT

# --- Write .htaccess to enable URL rewriting ---
cat > $WEB_ROOT/public/.htaccess <<'EOF'
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule ^(.*)$ index.php?/$1 [L,QSA]
EOF

# --- Write config file ---
mkdir -p $WEB_ROOT/config
cat > $WEB_ROOT/config/config.php <<EOF
<?php
return [
    'db_host' => 'localhost',
    'db_name' => '$DB_NAME',
    'db_user' => '$DB_USER',
    'db_pass' => '$DB_PASS',
];
EOF

# --- Write database connection class ---
mkdir -p $WEB_ROOT/src
cat > $WEB_ROOT/src/db.php <<'EOF'
<?php
class Database {
    private static \$instance = null;
    private \$conn;

    private function __construct() {
        \$config = include __DIR__ . '/../config/config.php';
        \$this->conn = new mysqli(
            \$config['db_host'],
            \$config['db_user'],
            \$config['db_pass'],
            \$config['db_name']
        );
        if (\$this->conn->connect_error) {
            die("Database connection failed: " . \$this->conn->connect_error);
        }
        \$this->conn->set_charset("utf8mb4");
    }

    public static function getInstance() {
        if (self::\$instance === null) {
            self::\$instance = new Database();
        }
        return self::\$instance;
    }

    public function getConnection() {
        return \$this->conn;
    }
}
EOF

# --- Write auth functions ---
cat > $WEB_ROOT/src/auth.php <<'EOF'
<?php
session_start();

require_once 'db.php';

function isLoggedIn() {
    return isset($_SESSION['user_id']);
}

function isAdmin() {
    return isset($_SESSION['role']) && $_SESSION['role'] === 'admin';
}

function requireLogin() {
    if (!isLoggedIn()) {
        header('Location: login.php');
        exit;
    }
}

function login($username, $password) {
    $db = Database::getInstance()->getConnection();
    $stmt = $db->prepare("SELECT id, password, role FROM users WHERE username = ?");
    $stmt->bind_param('s', $username);
    $stmt->execute();
    $result = $stmt->get_result();
    if ($row = $result->fetch_assoc()) {
        if (password_verify($password, $row['password'])) {
            $_SESSION['user_id'] = $row['id'];
            $_SESSION['username'] = $username;
            $_SESSION['role'] = $row['role'];
            return true;
        }
    }
    return false;
}

function logout() {
    session_destroy();
}
EOF

# --- Write streams functions ---
cat > $WEB_ROOT/src/stream.php <<'EOF'
<?php
require_once 'db.php';

function getStreams() {
    $db = Database::getInstance()->getConnection();
    $result = $db->query("SELECT streams.*, users.username AS created_by_name FROM streams JOIN users ON streams.created_by = users.id ORDER BY streams.id DESC");
    return $result->fetch_all(MYSQLI_ASSOC);
}

function addStream($name, $url, $user_id) {
    $db = Database::getInstance()->getConnection();
    $stmt = $db->prepare("INSERT INTO streams (name, stream_url, created_by) VALUES (?, ?, ?)");
    $stmt->bind_param("ssi", $name, $url, $user_id);
    return $stmt->execute();
}

function getStreamById($id) {
    $db = Database::getInstance()->getConnection();
    $stmt = $db->prepare("SELECT * FROM streams WHERE id = ?");
    $stmt->bind_param('i', $id);
    $stmt->execute();
    return $stmt->get_result()->fetch_assoc();
}

function deleteStream($id) {
    $db = Database::getInstance()->getConnection();
    $stmt = $db->prepare("DELETE FROM streams WHERE id = ?");
    $stmt->bind_param('i', $id);
    return $stmt->execute();
}
EOF

# --- Write M3U parser ---
cat > $WEB_ROOT/src/m3u_parser.php <<'EOF'
<?php
function parseM3U($content) {
    $lines = explode("\n", $content);
    $streams = [];
    $name = '';
    foreach ($lines as $line) {
        $line = trim($line);
        if (strpos($line, '#EXTINF') === 0) {
            $pos = strpos($line, ',');
            $name = $pos !== false ? substr($line, $pos + 1) : '';
        } elseif ($line && substr($line, 0, 1) !== '#') {
            $streams[] = ['name' => $name, 'url' => $line];
            $name = '';
        }
    }
    return $streams;
}
EOF

# --- Write login.php ---
cat > $WEB_ROOT/public/login.php <<'EOF'
<?php
require_once '../src/auth.php';

if (isLoggedIn()) {
    header('Location: dashboard.php');
    exit;
}

$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = $_POST['username'] ?? '';
    $password = $_POST['password'] ?? '';
    if (login($username, $password)) {
        header('Location: dashboard.php');
        exit;
    } else {
        $error = 'Invalid username or password.';
    }
}
?>
<!DOCTYPE html>
<html>
<head>
    <title>Login - IPTV Panel</title>
    <link href="css/bootstrap.min.css" rel="stylesheet">
</head>
<body>
<div class="container mt-5" style="max-width: 400px;">
    <h2>Login</h2>
    <?php if ($error): ?>
        <div class="alert alert-danger"><?=htmlspecialchars($error)?></div>
    <?php endif; ?>
    <form method="post">
        <div class="mb-3">
            <label>Username</label>
            <input name="username" class="form-control" required>
        </div>
        <div class="mb-3">
            <label>Password</label>
            <input name="password" type="password" class="form-control" required>
        </div>
        <button class="btn btn-primary" type="submit">Login</button>
    </form>
</div>
</body>
</html>
EOF

# --- Write logout.php ---
cat > $WEB_ROOT/public/logout.php <<'EOF'
<?php
require_once '../src/auth.php';
logout();
header('Location: login.php');
exit;
EOF

# --- Write dashboard.php ---
cat > $WEB_ROOT/public/dashboard.php <<'EOF'
<?php
require_once '../src/auth.php';
require_once '../src/stream.php';
requireLogin();

$streams = getStreams();
?>
<!DOCTYPE html>
<html>
<head>
    <title>Dashboard - IPTV Panel</title>
    <link href="css/bootstrap.min.css" rel="stylesheet">
</head>
<body>
<div class="container mt-4">
    <h2>Dashboard</h2>
    <p>Welcome, <?=htmlspecialchars($_SESSION['username'])?> | <a href="logout.php">Logout</a></p>
    <a href="add_stream.php" class="btn btn-success mb-3">Add Stream</a>
    <a href="m3u_upload.php" class="btn btn-info mb-3">Import M3U</a>
    <table class="table table-bordered">
        <thead>
            <tr><th>ID</th><th>Name</th><th>URL</th><th>Created By</th><th>Actions</th></tr>
        </thead>
        <tbody>
            <?php foreach ($streams as $stream): ?>
            <tr>
                <td><?= $stream['id'] ?></td>
                <td><?= htmlspecialchars($stream['name']) ?></td>
                <td><a href="<?= htmlspecialchars($stream['stream_url']) ?>" target="_blank">Link</a></td>
                <td><?= htmlspecialchars($stream['created_by_name']) ?></td>
                <td>
                    <a href="player.php?id=<?= $stream['id'] ?>" class="btn btn-primary btn-sm">Play</a>
                    <?php if (isAdmin()): ?>
                    <a href="delete_stream.php?id=<?= $stream['id'] ?>" class="btn btn-danger btn-sm" onclick="return confirm('Delete this stream?')">Delete</a>
                    <?php endif; ?>
                </td>
            </tr>
            <?php endforeach; ?>
            <?php if (empty($streams)): ?>
            <tr><td colspan="5">No streams found.</td></tr>
            <?php endif; ?>
        </tbody>
    </table>
</div>
</body>
</html>
EOF

# --- Write add_stream.php ---
cat > $WEB_ROOT/public/add_stream.php <<'EOF'
<?php
require_once '../src/auth.php';
require_once '../src/stream.php';
requireLogin();
if (!isAdmin()) {
    die("Access denied");
}

$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $name = trim($_POST['name'] ?? '');
    $url = trim($_POST['url'] ?? '');
    if ($name && $url) {
        if (addStream($name, $url, $_SESSION['user_id'])) {
            header('Location: dashboard.php');
            exit;
        } else {
            $error = 'Failed to add stream.';
        }
    } else {
        $error = 'Name and URL are required.';
    }
}
?>
<!DOCTYPE html>
<html>
<head>
    <title>Add Stream - IPTV Panel</title>
    <link href="css/bootstrap.min.css" rel="stylesheet">
</head>
<body>
<div class="container mt-4" style="max-width:600px;">
    <h3>Add Stream</h3>
    <?php if ($error): ?>
        <div class="alert alert-danger"><?=htmlspecialchars($error)?></div>
    <?php endif; ?>
    <form method="post">
        <div class="mb-3">
            <label>Stream Name</label>
            <input name="name" class="form-control" required>
        </div>
        <div class="mb-3">
            <label>Stream URL</label>
            <input name="url" class="form-control" required>
        </div>
        <button class="btn btn-primary" type="submit">Add</button>
        <a href="dashboard.php" class="btn btn-secondary">Back</a>
    </form>
</div>
</body>
</html>
EOF

# --- Write delete_stream.php ---
cat > $WEB_ROOT/public/delete_stream.php <<'EOF'
<?php
require_once '../src/auth.php';
require_once '../src/stream.php';
requireLogin();
if (!isAdmin()) {
    die("Access denied");
}
$id = $_GET['id'] ?? null;
if (!$id) {
    die("Stream ID missing");
}
deleteStream($id);
header('Location: dashboard.php');
exit();
EOF

# --- Write m3u_upload.php ---
cat > $WEB_ROOT/public/m3u_upload.php <<'EOF'
<?php
require_once '../src/auth.php';
require_once '../src/m3u_parser.php';
require_once '../src/stream.php';
requireLogin();
if (!isAdmin()) {
    die("Access denied");
}

$message = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_FILES['m3u_file']) && $_FILES['m3u_file']['error'] === UPLOAD_ERR_OK) {
        $content = file_get_contents($_FILES['m3u_file']['tmp_name']);
        $streams = parseM3U($content);
        $added = 0;
        foreach ($streams as $s) {
            if (addStream($s['name'], $s['url'], $_SESSION['user_id'])) {
                $added++;
            }
        }
        $message = "Imported $added streams from M3U.";
    } else {
        $message = "Failed to upload M3U file.";
    }
}
?>
<!DOCTYPE html>
<html>
<head>
    <title>Import M3U Playlist - IPTV Panel</title>
    <link href="css/bootstrap.min.css" rel="stylesheet">
</head>
<body>
<div class="container mt-4" style="max-width:600px;">
    <h3>Import M3U Playlist</h3>
    <?php if ($message): ?>
        <div class="alert alert-info"><?= htmlspecialchars($message) ?></div>
    <?php endif; ?>
    <form method="POST" enctype="multipart/form-data">
        <div class="mb-3">
            <label>Select M3U File</label>
            <input type="file" name="m3u_file" class="form-control" accept=".m3u,.txt" required>
        </div>
        <button type="submit" class="btn btn-primary">Import</button>
        <a href="dashboard.php" class="btn btn-secondary">Back</a>
    </form>
</div>
</body>
</html>
EOF

# --- Write player.php ---
cat > $WEB_ROOT/public/player.php <<'EOF'
<?php
require_once '../src/auth.php';
require_once '../src/stream.php';
requireLogin();

$stream_id = $_GET['id'] ?? null;
if (!$stream_id) {
    die("Stream ID required.");
}

$stream = getStreamById($stream_id);
if (!$stream) {
    die("Stream not found.");
}
?>
<!DOCTYPE html>
<html>
<head>
    <title>Watch Stream - <?= htmlspecialchars($stream['name']) ?></title>
    <link href="https://vjs.zencdn.net/7.20.3/video-js.css" rel="stylesheet" />
    <style>
      .video-js { width: 100%; height: 500px; }
    </style>
</head>
<body>
<div class="container mt-4" style="max-width:800px;">
    <h3>Watching: <?= htmlspecialchars($stream['name']) ?></h3>
    <video
      id="my-video"
      class="video-js"
      controls
      preload="auto"
      data-setup="{}"
      >
      <source src="<?= htmlspecialchars($stream['stream_url']) ?>" type="application/x-mpegURL" />
      Your browser does not support the video tag.
    </video>
    <p><a href="dashboard.php">Back to Dashboard</a></p>
</div>
<script src="https://vjs.zencdn.net/7.20.3/video.min.js"></script>
</body>
</html>
EOF

# --- Download Bootstrap CSS ---
echo "[8/10] Downloading Bootstrap CSS..."
mkdir -p $WEB_ROOT/public/css
curl -sSL https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css -o $WEB_ROOT/public/css/bootstrap.min.css

# --- Set ownership and permissions ---
echo "[9/10] Setting permissions..."
chown -R www-data:www-data $WEB_ROOT
find $WEB_ROOT -type d -exec chmod 755 {} \;
find $WEB_ROOT -type f -exec chmod 644 {} \;

# --- Enable site and restart Apache ---
echo "[10/10] Configuring Apache site..."

cat > /etc/apache2/sites-available/iptv-panel.conf <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot $WEB_ROOT/public
    <Directory $WEB_ROOT/public>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/iptv-panel_error.log
    CustomLog \${APACHE_LOG_DIR}/iptv-panel_access.log combined
</VirtualHost>
EOF

a2dissite 000-default.conf
a2ensite iptv-panel.conf

systemctl reload apache2

echo "Installation complete!"
echo
echo "You can now open your browser and visit your server IP to see the IPTV panel login page."
echo "Admin credentials:"
echo "  Username: $ADMIN_USER"
echo "  Password: $ADMIN_PASS"

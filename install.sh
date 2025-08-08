#!/bin/bash
set -e

# Config - Change these before running if needed
DB_NAME="iptv_panel"
DB_USER="root"
DB_PASS="your_db_password_here"  # Set your MySQL root password here or use mysql config
ADMIN_USER="admin"
ADMIN_EMAIL="admin@example.com"
ADMIN_PASS="adminpass"

echo "=== IPTV/OTT PHP Panel Auto Installer ==="

# Update & install dependencies
echo "[1/10] Updating system and installing Apache2, PHP, and extensions..."
apt update
apt install -y apache2 php php-mysql php-xml php-mbstring php-curl unzip curl mysql-client

# Enable Apache mods
echo "[2/10] Enabling Apache rewrite module..."
a2enmod rewrite

# Restart Apache to apply changes
systemctl restart apache2

# Create project base directory
BASE_DIR="/var/www/iptv-panel"
echo "[3/10] Creating project directories at $BASE_DIR ..."
mkdir -p $BASE_DIR/{config,src,public/css,public/js,sql}
chown -R www-data:www-data $BASE_DIR
chmod -R 755 $BASE_DIR

# Create config/config.php
cat << EOF > $BASE_DIR/config/config.php
<?php
define('DB_HOST', 'localhost');
define('DB_NAME', '$DB_NAME');
define('DB_USER', '$DB_USER');
define('DB_PASS', '$DB_PASS');

session_start();
EOF

# Create src/db.php
cat << 'EOF' > $BASE_DIR/src/db.php
<?php
class Database {
    private static $instance = null;
    private $conn;

    private function __construct() {
        $this->conn = new mysqli(DB_HOST, DB_USER, DB_PASS, DB_NAME);
        if ($this->conn->connect_error) {
            die("DB Connection failed: " . $this->conn->connect_error);
        }
        $this->conn->set_charset("utf8mb4");
    }

    public static function getInstance() {
        if (!self::$instance) {
            self::$instance = new Database();
        }
        return self::$instance;
    }

    public function getConnection() {
        return $this->conn;
    }
}
EOF

# Create src/auth.php
cat << 'EOF' > $BASE_DIR/src/auth.php
<?php
require_once __DIR__ . '/../config/config.php';
require_once 'db.php';

function login($username, $password) {
    $db = Database::getInstance()->getConnection();
    $stmt = $db->prepare("SELECT id, password, role FROM users WHERE username = ?");
    $stmt->bind_param('s', $username);
    $stmt->execute();
    $stmt->store_result();
    if ($stmt->num_rows == 1) {
        $stmt->bind_result($id, $hashed_password, $role);
        $stmt->fetch();
        if (password_verify($password, $hashed_password)) {
            $_SESSION['user_id'] = $id;
            $_SESSION['username'] = $username;
            $_SESSION['role'] = $role;
            return true;
        }
    }
    return false;
}

function logout() {
    session_unset();
    session_destroy();
}

function isLoggedIn() {
    return isset($_SESSION['user_id']);
}

function requireLogin() {
    if (!isLoggedIn()) {
        header('Location: login.php');
        exit();
    }
}

function isAdmin() {
    return (isset($_SESSION['role']) && $_SESSION['role'] === 'admin');
}

function isReseller() {
    return (isset($_SESSION['role']) && $_SESSION['role'] === 'reseller');
}
EOF

# Create src/helpers.php
cat << 'EOF' > $BASE_DIR/src/helpers.php
<?php
function sanitize($data) {
    return htmlspecialchars(strip_tags(trim($data)));
}
EOF

# Create src/user.php
cat << 'EOF' > $BASE_DIR/src/user.php
<?php
require_once 'db.php';

function createUser($username, $email, $password, $role = 'user') {
    $db = Database::getInstance()->getConnection();

    $hashed = password_hash($password, PASSWORD_DEFAULT);
    $stmt = $db->prepare("INSERT INTO users (username, email, password, role) VALUES (?, ?, ?, ?)");
    $stmt->bind_param('ssss', $username, $email, $hashed, $role);
    return $stmt->execute();
}

function getUserById($id) {
    $db = Database::getInstance()->getConnection();
    $stmt = $db->prepare("SELECT id, username, email, role FROM users WHERE id = ?");
    $stmt->bind_param('i', $id);
    $stmt->execute();
    $result = $stmt->get_result();
    return $result->fetch_assoc();
}

function getAllUsers() {
    $db = Database::getInstance()->getConnection();
    $result = $db->query("SELECT id, username, email, role FROM users ORDER BY id DESC");
    return $result->fetch_all(MYSQLI_ASSOC);
}
EOF

# Create src/stream.php
cat << 'EOF' > $BASE_DIR/src/stream.php
<?php
require_once 'db.php';

function addStream($name, $category, $url, $added_by) {
    $db = Database::getInstance()->getConnection();
    $stmt = $db->prepare("INSERT INTO streams (name, category, stream_url, added_by) VALUES (?, ?, ?, ?)");
    $stmt->bind_param('sssi', $name, $category, $url, $added_by);
    return $stmt->execute();
}

function getStreams() {
    $db = Database::getInstance()->getConnection();
    $result = $db->query("SELECT s.id, s.name, s.category, s.stream_url, u.username as added_by FROM streams s LEFT JOIN users u ON s.added_by = u.id ORDER BY s.id DESC");
    return $result->fetch_all(MYSQLI_ASSOC);
}

function getStreamById($id) {
    $db = Database::getInstance()->getConnection();
    $stmt = $db->prepare("SELECT * FROM streams WHERE id = ?");
    $stmt->bind_param('i', $id);
    $stmt->execute();
    $result = $stmt->get_result();
    return $result->fetch_assoc();
}

function updateStream($id, $name, $category, $url) {
    $db = Database::getInstance()->getConnection();
    $stmt = $db->prepare("UPDATE streams SET name = ?, category = ?, stream_url = ? WHERE id = ?");
    $stmt->bind_param('sssi', $name, $category, $url, $id);
    return $stmt->execute();
}

function deleteStream($id) {
    $db = Database::getInstance()->getConnection();
    $stmt = $db->prepare("DELETE FROM streams WHERE id = ?");
    $stmt->bind_param('i', $id);
    return $stmt->execute();
}
EOF

# Create src/m3u_parser.php
cat << 'EOF' > $BASE_DIR/src/m3u_parser.php
<?php
function parseM3U($m3uContent) {
    $lines = explode("\n", $m3uContent);
    $streams = [];
    $current = [];

    foreach ($lines as $line) {
        $line = trim($line);
        if (empty($line)) continue;

        if (strpos($line, '#EXTINF:') === 0) {
            preg_match('/#EXTINF:-?\d+,(.*)/', $line, $matches);
            $current['name'] = $matches[1] ?? 'Unknown';
        } elseif (strpos($line, '#') !== 0) {
            $current['url'] = $line;
            $streams[] = $current;
            $current = [];
        }
    }
    return $streams;
}
EOF

# Create src/epg_parser.php
cat << 'EOF' > $BASE_DIR/src/epg_parser.php
<?php
function parseXMLTV($filePath) {
    $xml = simplexml_load_file($filePath);
    $programs = [];

    foreach ($xml->programme as $programme) {
        $programs[] = [
            'channel' => (string)$programme['channel'],
            'start' => date('Y-m-d H:i:s', strtotime((string)$programme['start'])),
            'stop' => date('Y-m-d H:i:s', strtotime((string)$programme['stop'])),
            'title' => (string)$programme->title,
            'desc' => (string)$programme->desc,
        ];
    }
    return $programs;
}
EOF

# Create sql/schema.sql
cat << EOF > $BASE_DIR/sql/schema.sql
CREATE DATABASE IF NOT EXISTS $DB_NAME;
USE $DB_NAME;

CREATE TABLE IF NOT EXISTS users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(50) UNIQUE NOT NULL,
  password VARCHAR(255) NOT NULL,
  email VARCHAR(100) UNIQUE NOT NULL,
  role ENUM('admin','reseller','user') DEFAULT 'user',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS streams (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  category VARCHAR(100),
  stream_url TEXT NOT NULL,
  added_by INT,
  FOREIGN KEY (added_by) REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS epg (
  id INT AUTO_INCREMENT PRIMARY KEY,
  channel_name VARCHAR(255),
  start_time DATETIME,
  end_time DATETIME,
  title VARCHAR(255),
  description TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS vod (
  id INT AUTO_INCREMENT PRIMARY KEY,
  title VARCHAR(255),
  description TEXT,
  thumbnail_url TEXT,
  video_url TEXT,
  category VARCHAR(100),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS subscriptions (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT,
  plan_name VARCHAR(100),
  start_date DATE,
  end_date DATE,
  status ENUM('active','expired','cancelled') DEFAULT 'active',
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
EOF

# Create public/.htaccess for Apache mod_rewrite
cat << 'EOF' > $BASE_DIR/public/.htaccess
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule ^(.*)$ index.php [L,QSA]
EOF

# Create public/login.php
cat << 'EOF' > $BASE_DIR/public/login.php
<?php
require_once '../src/auth.php';

$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (login($_POST['username'], $_POST['password'])) {
        header('Location: dashboard.php');
        exit();
    } else {
        $error = 'Invalid username or password.';
    }
}
?>
<!DOCTYPE html>
<html>
<head>
  <title>IPTV Panel Login</title>
  <link rel="stylesheet" href="css/bootstrap.min.css">
</head>
<body class="bg-light">
<div class="container mt-5" style="max-width:400px;">
  <h2 class="mb-4">Login</h2>
  <?php if ($error): ?>
    <div class="alert alert-danger"><?= htmlspecialchars($error) ?></div>
  <?php endif; ?>
  <form method="POST" action="">
    <div class="mb-3">
      <label>Username</label>
      <input type="text" name="username" class="form-control" required autofocus>
    </div>
    <div class="mb-3">
      <label>Password</label>
      <input type="password" name="password" class="form-control" required>
    </div>
    <button class="btn btn-primary w-100" type="submit">Login</button>
  </form>
</div>
</body>
</html>
EOF

# Create public/logout.php
cat << 'EOF' > $BASE_DIR/public/logout.php
<?php
require_once '../src/auth.php';
logout();
header('Location: login.php');
exit();
EOF

# Create public/dashboard.php
cat << 'EOF' > $BASE_DIR/public/dashboard.php
<?php
require_once '../src/auth.php';
requireLogin();

$username = $_SESSION['username'];
$role = $_SESSION['role'];

?>
<!DOCTYPE html>
<html>
<head>
    <title>Dashboard - IPTV Panel</title>
    <link rel="stylesheet" href="css/bootstrap.min.css">
</head>
<body>
<nav class="navbar navbar-expand-lg navbar-dark bg-dark">
  <div class="container-fluid">
    <a class="navbar-brand" href="#">IPTV Panel</a>
    <div class="d-flex">
      <span class="navbar-text text-white me-3">Welcome, <?= htmlspecialchars($username) ?> (<?= $role ?>)</span>
      <a href="logout.php" class="btn btn-outline-light">Logout</a>
    </div>
  </div>
</nav>

<div class="container mt-4">
    <h3>Dashboard</h3>
    <?php if ($role === 'admin'): ?>
      <p><a href="streams.php" class="btn btn-primary">Manage Streams</a></p>
      <p><a href="m3u_upload.php" class="btn btn-secondary">Import M3U Playlist</a></p>
      <p><a href="epg_upload.php" class="btn btn-secondary">Upload EPG (XMLTV)</a></p>
    <?php endif; ?>

    <p><a href="player.php" class="btn btn-success">Watch Streams</a></p>

</div>
</body>
</html>
EOF

# Create public/streams.php
cat << 'EOF' > $BASE_DIR/public/streams.php
<?php
require_once '../src/auth.php';
require_once '../src/stream.php';
requireLogin();
if (!isAdmin()) {
    die("Access denied");
}

$streams = getStreams();
?>
<!DOCTYPE html>
<html>
<head>
    <title>Manage Streams - IPTV Panel</title>
    <link rel="stylesheet" href="css/bootstrap.min.css">
</head>
<body>
<div class="container mt-4">
    <h3>Manage Streams</h3>
    <a href="stream_add.php" class="btn btn-primary mb-3">Add New Stream</a>
    <table class="table table-bordered">
        <thead>
            <tr>
                <th>ID</th><th>Name</th><th>Category</th><th>URL</th><th>Added By</th><th>Actions</th>
            </tr>
        </thead>
        <tbody>
        <?php foreach ($streams as $stream): ?>
            <tr>
                <td><?= $stream['id'] ?></td>
                <td><?= htmlspecialchars($stream['name']) ?></td>
                <td><?= htmlspecialchars($stream['category']) ?></td>
                <td><?= htmlspecialchars($stream['stream_url']) ?></td>
                <td><?= htmlspecialchars($stream['added_by'] ?? 'N/A') ?></td>
                <td>
                    <a href="stream_add.php?id=<?= $stream['id'] ?>" class="btn btn-sm btn-warning">Edit</a>
                    <a href="stream_delete.php?id=<?= $stream['id'] ?>" class="btn btn-sm btn-danger" onclick="return confirm('Delete this stream?')">Delete</a>
                </td>
            </tr>
        <?php endforeach; ?>
        </tbody>
    </table>
    <a href="dashboard.php" class="btn btn-secondary">Back to Dashboard</a>
</div>
</body>
</html>
EOF

# Create public/stream_add.php
cat << 'EOF' > $BASE_DIR/public/stream_add.php
<?php
require_once '../src/auth.php';
require_once '../src/stream.php';
requireLogin();
if (!isAdmin()) {
    die("Access denied");
}

$id = $_GET['id'] ?? null;
$stream = null;
if ($id) {
    $stream = getStreamById($id);
    if (!$stream) die("Stream not found");
}

$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $name = $_POST['name'] ?? '';
    $category = $_POST['category'] ?? '';
    $url = $_POST['url'] ?? '';
    if (!$name || !$url) {
        $error = "Name and URL are required.";
    } else {
        if ($id) {
            updateStream($id, $name, $category, $url);
        } else {
            addStream($name, $category, $url, $_SESSION['user_id']);
        }
        header('Location: streams.php');
        exit();
    }
}

?>
<!DOCTYPE html>
<html>
<head>
    <title><?= $id ? 'Edit' : 'Add' ?> Stream - IPTV Panel</title>
    <link rel="stylesheet" href="css/bootstrap.min.css">
</head>
<body>
<div class="container mt-4" style="max-width:600px;">
    <h3><?= $id ? 'Edit' : 'Add' ?> Stream</h3>
    <?php if ($error): ?>
        <div class="alert alert-danger"><?= htmlspecialchars($error) ?></div>
    <?php endif; ?>
    <form method="POST">
        <div class="mb-3">
            <label>Name *</label>
            <input type="text" name="name" class="form-control" required value="<?= htmlspecialchars($stream['name'] ?? '') ?>">
        </div>
        <div class="mb-3">
            <label>Category</label>
            <input type="text" name="category" class="form-control" value="<?= htmlspecialchars($stream['category'] ?? '') ?>">
        </div>
        <div class="mb-3">
            <label>Stream URL *</label>
            <input type="url" name="url" class="form-control" required value="<?= htmlspecialchars($stream['stream_url'] ?? '') ?>">
        </div>
        <button type="submit" class="btn btn-primary"><?= $id ? 'Update' : 'Add' ?></button>
        <a href="streams.php" class="btn btn-secondary">Cancel</a>
    </form>
</div>
</body>
</html>
EOF

# Create public/stream_delete.php
cat << 'EOF' > $BASE_DIR/public/stream_delete.php
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
header('Location: streams.php');
exit();
EOF

# Create public/m3u_upload.php
cat << 'EOF' > $BASE_DIR/public/m3u_upload.php
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
            if (addStream($s['name'], '', $s['url'], $_SESSION['user_id'])) {
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
    <link rel="stylesheet" href="css/bootstrap.min.css">
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

# Create public/epg_upload.php
cat << 'EOF' > $BASE_DIR/public/epg_upload.php
<?php
require_once '../src/auth.php';
require_once '../src/epg_parser.php';
requireLogin();
if (!isAdmin()) {
    die("Access denied");
}
require_once '../src/db.php';

$message = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_FILES['epg_file']) && $_FILES['epg_file']['error'] === UPLOAD_ERR_OK) {
        $programs = parseXMLTV($_FILES['epg_file']['tmp_name']);
        $db = Database::getInstance()->getConnection();

        // Clear old EPG data
        $db->query("TRUNCATE TABLE epg");

        $stmt = $db->prepare("INSERT INTO epg (channel_name, start_time, end_time, title, description) VALUES (?, ?, ?, ?, ?)");
        foreach ($programs as $p) {
            $stmt->bind_param('sssss', $p['channel'], $p['start'], $p['stop'], $p['title'], $p['desc']);
            $stmt->execute();
        }
        $message = 'EPG imported: ' . count($programs) . ' programs.';
    } else {
        $message = 'Failed to upload EPG XML file.';
    }
}
?>
<!DOCTYPE html>
<html>
<head>
    <title>Upload EPG - IPTV Panel</title>
    <link rel="stylesheet" href="css/bootstrap.min.css">
</head>
<body>
<div class="container mt-4" style="max-width:600px;">
    <h3>Upload XMLTV EPG</h3>
    <?php if ($message): ?>
        <div class="alert alert-info"><?= htmlspecialchars($message) ?></div>
    <?php endif; ?>
    <form method="POST" enctype="multipart/form-data">
        <div class="mb-3">
            <label>Select XMLTV File</label>
            <input type="file" name="epg_file" class="form-control" accept=".xml" required>
        </div>
        <button type="submit" class="btn btn-primary">Upload</button>
        <a href="dashboard.php" class="btn btn-secondary">Back</a>
    </form>
</div>
</body>
</html>
EOF

# Create public/player.php
cat << 'EOF' > $BASE_DIR/public/player.php
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

# Create public/index.php
cat << 'EOF' > $BASE_DIR/public/index.php
<?php
require_once '../src/auth.php';

if (isLoggedIn()) {
    header('Location: dashboard.php');
} else {
    header('Location: login.php');
}
exit();
EOF

# Download bootstrap CSS to public/css/bootstrap.min.css
echo "[9/10] Downloading Bootstrap CSS..."
curl -sSL https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css -o $BASE_DIR/public/css/bootstrap.min.css

# Set permissions
echo "[10/10] Setting ownership and permissions..."
chown -R www-data:www-data $BASE_DIR
find $BASE_DIR -type d -exec chmod 755 {} \;
find $BASE_DIR -type f -exec chmod 644 {} \;

# Setup database and create admin user
echo "Setting up database and creating admin user..."
mysql -u $DB_USER -p$DB_PASS << EOF
SOURCE $BASE_DIR/sql/schema.sql;

INSERT INTO users (username, email, password, role) VALUES (
    '$ADMIN_USER',
    '$ADMIN_EMAIL',
    PASSWORD('$ADMIN_PASS'),
    'admin'
) ON DUPLICATE KEY UPDATE username=username;
EOF

echo
echo "Installation complete!

Access your IPTV Panel at http://your-server-ip/iptv-panel/public/
Login with:
  Username: $ADMIN_USER
  Password: $ADMIN_PASS

Make sure to update 'config/config.php' with your actual MySQL credentials if you changed them.

Apache is configured to allow URL rewriting via .htaccess in the public folder.

Enjoy!"

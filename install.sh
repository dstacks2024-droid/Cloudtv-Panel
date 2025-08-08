#!/bin/bash

set -e

echo "Updating system packages..."
sudo apt update && sudo apt upgrade -y

echo "Installing Apache2, PHP, MySQL..."
sudo apt install -y apache2 mysql-server php php-cli php-common php-mysql php-curl php-mbstring php-xml php-zip php-gd unzip wget

echo "Starting and enabling Apache2 and MySQL..."
sudo systemctl start apache2
sudo systemctl enable apache2
sudo systemctl start mysql
sudo systemctl enable mysql

echo "Securing MySQL and setting root password..."
sudo mysql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'CloudTVpass123';
FLUSH PRIVILEGES;
EOF

echo "Creating CloudTV database and importing schema..."
mysql -uroot -pCloudTVpass123 <<EOF
CREATE DATABASE IF NOT EXISTS cloudtv;
USE cloudtv;

CREATE TABLE IF NOT EXISTS admins (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(50) UNIQUE NOT NULL,
  password VARCHAR(255) NOT NULL
);

INSERT IGNORE INTO admins (username, password) VALUES
('admin', '\$2y\$10\$v4RKL9D.4tTTMbyi8cCLkewGeQ/f9A9R6EWrLO7OhKzSlnHi5zRVO'); -- admin123

CREATE TABLE IF NOT EXISTS users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100),
  username VARCHAR(50) UNIQUE,
  password VARCHAR(255),
  plan VARCHAR(50),
  max_connections INT DEFAULT 1,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS streams (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100),
  url TEXT,
  category VARCHAR(50),
  status ENUM('online','offline') DEFAULT 'online',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS vod (
  id INT AUTO_INCREMENT PRIMARY KEY,
  title VARCHAR(255),
  description TEXT,
  url TEXT,
  cover_image TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS series (
  id INT AUTO_INCREMENT PRIMARY KEY,
  series VARCHAR(255),
  episode VARCHAR(255),
  url TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF

echo "Deploying Cloud TV panel files..."

APPDIR="/var/www/html/cloudtv"
sudo mkdir -p $APPDIR

echo "Creating PHP files..."

# index.html (login page)
sudo tee $APPDIR/index.html > /dev/null <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Cloud TV Admin Login</title>
  <style>
    body {
      margin: 0;
      font-family: Arial, sans-serif;
      background-color: #121212;
      color: #ffffff;
      display: flex;
      justify-content: center;
      align-items: center;
      height: 100vh;
    }
    .login-container {
      background-color: #1f1f1f;
      padding: 30px;
      border-radius: 8px;
      box-shadow: 0 0 15px rgba(0, 0, 0, 0.5);
      width: 300px;
      text-align: center;
    }
    .login-container h2 {
      margin-bottom: 20px;
    }
    .login-container input[type="text"],
    .login-container input[type="password"] {
      width: 100%;
      padding: 10px;
      margin: 10px 0;
      border: none;
      border-radius: 4px;
    }
    .login-container button {
      width: 100%;
      padding: 10px;
      background-color: #2196f3;
      border: none;
      border-radius: 4px;
      color: white;
      font-size: 16px;
      cursor: pointer;
    }
    .login-container button:hover {
      background-color: #1976d2;
    }
    .error {
      color: #f44336;
      margin-top: 10px;
    }
  </style>
</head>
<body>
  <div class="login-container">
    <h2>Cloud TV Admin Panel</h2>
    <form method="POST" action="login.php">
      <input type="text" name="username" placeholder="Username" required />
      <input type="password" name="password" placeholder="Password" required />
      <button type="submit">Login</button>
    </form>
    <?php if (isset($_GET['error'])) echo "<p class='error'>Invalid credentials.</p>"; ?>
  </div>
</body>
</html>
EOF

# login.php
sudo tee $APPDIR/login.php > /dev/null <<'EOF'
<?php
session_start();

$host = 'localhost';
$db   = 'cloudtv';
$user = 'root';
$pass = 'CloudTVpass123';

try {
    $pdo = new PDO("mysql:host=$host;dbname=$db", $user, $pass);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (PDOException $e) {
    die("Database connection failed: " . $e->getMessage());
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = $_POST['username'];
    $password = $_POST['password'];

    $stmt = $pdo->prepare("SELECT * FROM admins WHERE username = ? LIMIT 1");
    $stmt->execute([$username]);
    $admin = $stmt->fetch(PDO::FETCH_ASSOC);

    if ($admin && password_verify($password, $admin['password'])) {
        $_SESSION['admin_logged_in'] = true;
        $_SESSION['admin_user'] = $admin['username'];
        header("Location: dashboard.php");
        exit();
    } else {
        header("Location: index.html?error=1");
        exit();
    }
}
?>
EOF

# dashboard.php
sudo tee $APPDIR/dashboard.php > /dev/null <<'EOF'
<?php
session_start();
if (!isset($_SESSION['admin_logged_in'])) {
    header("Location: index.html");
    exit();
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Cloud TV Dashboard</title>
  <style>
    body {
      background-color: #121212;
      color: #fff;
      font-family: Arial, sans-serif;
      margin: 0;
    }
    header {
      background-color: #1f1f1f;
      padding: 20px;
      text-align: center;
      font-size: 24px;
      font-weight: bold;
      border-bottom: 1px solid #333;
    }
    nav {
      background-color: #1a1a1a;
      padding: 15px;
    }
    nav a {
      color: #bbb;
      margin-right: 15px;
      text-decoration: none;
    }
    nav a:hover {
      color: #fff;
    }
    .content {
      padding: 20px;
    }
  </style>
</head>
<body>
  <header>Cloud TV Admin Dashboard</header>
  <nav>
    <a href="dashboard.php">Dashboard</a>
    <a href="users.php">Users</a>
    <a href="streams.php">Streams</a>
    <a href="vod.php">VOD</a>
    <a href="series.php">Series</a>
    <a href="logout.php">Logout</a>
  </nav>
  <div class="content">
    <h2>Welcome, <?php echo htmlspecialchars($_SESSION['admin_user']); ?>!</h2>
    <p>This is the Cloud TV backend dashboard.</p>
  </div>
</body>
</html>
EOF

# logout.php
sudo tee $APPDIR/logout.php > /dev/null <<'EOF'
<?php
session_start();
session_destroy();
header("Location: index.html");
exit();
?>
EOF

# users.php
sudo tee $APPDIR/users.php > /dev/null <<'EOF'
<?php
session_start();
if (!isset($_SESSION['admin_logged_in'])) {
    header("Location: index.html");
    exit();
}

$pdo = new PDO("mysql:host=localhost;dbname=cloudtv", 'root', 'CloudTVpass123');
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $name = $_POST['name'];
    $username = $_POST['username'];
    $password = password_hash($_POST['password'], PASSWORD_DEFAULT);
    $plan = $_POST['plan'];
    $max_connections = (int)$_POST['max_connections'];

    $stmt = $pdo->prepare("INSERT INTO users (name, username, password, plan, max_connections) VALUES (?, ?, ?, ?, ?)");
    $stmt->execute([$name, $username, $password, $plan, $max_connections]);
    header("Location: users.php");
    exit();
}

$users = $pdo->query("SELECT * FROM users ORDER BY created_at DESC")->fetchAll(PDO::FETCH_ASSOC);
?>
<!DOCTYPE html>
<html>
<head>
    <title>Cloud TV - Users</title>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css">
    <style>
        body { background-color: #121212; color: #fff; }
        .container { margin-top: 50px; }
        .table-dark td, .table-dark th { color: #fff; }
        .form-control, .btn { border-radius: 0; }
    </style>
</head>
<body>
    <div class="container">
        <h2>Users</h2>
        <form method="POST" class="row g-3 mb-4">
            <div class="col-md-3">
                <input type="text" name="name" placeholder="Name" class="form-control" required>
            </div>
            <div class="col-md-2">
                <input type="text" name="username" placeholder="Username" class="form-control" required>
            </div>
            <div class="col-md-2">
                <input type="text" name="password" placeholder="Password" class="form-control" required>
            </div>
            <div class="col-md-2">
                <input type="text" name="plan" placeholder="Plan" class="form-control">
            </div>
            <div class="col-md-1">
                <input type="number" name="max_connections" placeholder="Max" class="form-control" min="1">
            </div>
            <div class="col-md-2">
                <button type="submit" class="btn btn-primary w-100">Add User</button>
            </div>
        </form>

        <table class="table table-dark table-striped">
            <thead>
                <tr>
                    <th>ID</th>
                    <th>Name</th>
                    <th>Username</th>
                    <th>Plan</th>
                    <th>Max</th>
                    <th>Created</th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($users as $user): ?>
                    <tr>
                        <td><?= $user['id'] ?></td>
                        <td><?= htmlspecialchars($user['name']) ?></td>
                        <td><?= htmlspecialchars($user['username']) ?></td>
                        <td><?= htmlspecialchars($user['plan']) ?></td>
                        <td><?= $user['max_connections'] ?></td>
                        <td><?= $user['created_at'] ?></td>
                    </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
    </div>
</body>
</html>
EOF

# streams.php
sudo tee $APPDIR/streams.php > /dev/null <<'EOF'
<?php
session_start();
if (!isset($_SESSION['admin_logged_in'])) {
    header("Location: index.html");
    exit();
}

$host = 'localhost';
$db = 'cloudtv';
$user = 'root';
$pass = 'CloudTVpass123';
$pdo = new PDO("mysql:host=$host;dbname=$db", $user, $pass);

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $name = $_POST['name'];
    $url = $_POST['url'];
    $category = $_POST['category'];
    $stmt = $pdo->prepare("INSERT INTO streams (name, url, category) VALUES (?, ?, ?)");
    $stmt->execute([$name, $url, $category]);
    header("Location: streams.php");
    exit();
}

$streams = $pdo->query("SELECT * FROM streams ORDER BY id DESC")->fetchAll(PDO::FETCH_ASSOC);
?>
<!DOCTYPE html>
<html>
<head>
    <title>Cloud TV - Streams</title>
    <style>
        body { background: #111; color: #fff; font-family: Arial; }
        .container { width: 80%; margin: auto; padding-top: 50px; }
        table { width: 100%; border-collapse: collapse; background: #222; }
        th, td { padding: 10px; border: 1px solid #444; }
        th { background: #333; }
        input, select { padding: 8px; width: 100%; background: #222; color: #fff; border: 1px solid #555; }
        form { margin-bottom: 20px; }
        button { background: #2196f3; border: none; padding: 10px 15px; color: white; cursor: pointer; }
        button:hover { background: #1976d2; }
    </style>
</head>
<body>
<div class="container">
    <h2>Live Streams</h2>
    <form method="POST">
        <input type="text" name="name" placeholder="Stream Name" required>
        <input type="text" name="url" placeholder="Stream URL" required>
        <input type="text" name="category" placeholder="Category">
        <button type="submit">Add Stream</button>
    </form>

    <table>
        <tr>
            <th>ID</th><th>Name</th><th>URL</th><th>Category</th><th>Status</th>
        </tr>
        <?php foreach ($streams as $stream): ?>
        <tr>
            <td><?= $stream['id'] ?></td>
            <td><?= htmlspecialchars($stream['name']) ?></td>
            <td><?= htmlspecialchars($stream['url']) ?></td>
            <td><?= htmlspecialchars($stream['category']) ?></td>
            <td><?= $stream['status'] ?></td>
        </tr>
        <?php endforeach; ?>
    </table>
</div>
</body>
</html>
EOF

# vod.php
sudo tee $APPDIR/vod.php > /dev/null <<'EOF'
<?php
session_start();
if (!isset($_SESSION['admin_logged_in'])) {
    header("Location: index.html");
    exit();
}

$host = 'localhost';
$db = 'cloudtv';
$user = 'root';
$pass = 'CloudTVpass123';
$pdo = new PDO("mysql:host=$host;dbname=$db", $user, $pass);

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $title = $_POST['title'];
    $url = $_POST['url'];
    $description = $_POST['description'] ?? '';
    $cover_image = $_POST['cover_image'] ?? '';
    $stmt = $pdo->prepare("INSERT INTO vod (title, description, url, cover_image) VALUES (?, ?, ?, ?)");
    $stmt->execute([$title, $description, $url, $cover_image]);
    header("Location: vod.php");
    exit();
}

$vodList = $pdo->query("SELECT * FROM vod ORDER BY id DESC")->fetchAll(PDO::FETCH_ASSOC);
?>
<!DOCTYPE html>
<html>
<head>
    <title>Cloud TV - VOD</title>
    <style>
        body { background: #111; color: #fff; font-family: Arial; }
        .container { width: 80%; margin: auto; padding-top: 50px; }
        table { width: 100%; border-collapse: collapse; background: #222; }
        th, td { padding: 10px; border: 1px solid #444; }
        th { background: #333; }
        input { padding: 8px; width: 100%; background: #222; color: #fff; border: 1px solid #555; margin-bottom: 10px;}
        form { margin-bottom: 20px; }
        button { background: #2196f3; border: none; padding: 10px 15px; color: white; cursor: pointer; }
        button:hover { background: #1976d2; }
    </style>
</head>
<body>
<div class="container">
    <h2>Video On Demand (Movies)</h2>
    <form method="POST">
        <input type="text" name="title" placeholder="Movie Title" required>
        <input type="text" name="description" placeholder="Description">
        <input type="text" name="url" placeholder="Video URL" required>
        <input type="text" name="cover_image" placeholder="Cover Image URL">
        <button type="submit">Add Movie</button>
    </form>

    <table>
        <tr>
            <th>ID</th><th>Title</th><th>Description</th><th>URL</th><th>Cover</th>
        </tr>
        <?php foreach ($vodList as $vod): ?>
        <tr>
            <td><?= $vod['id'] ?></td>
            <td><?= htmlspecialchars($vod['title']) ?></td>
            <td><?= htmlspecialchars($vod['description']) ?></td>
            <td><?= htmlspecialchars($vod['url']) ?></td>
            <td><?= htmlspecialchars($vod['cover_image']) ?></td>
        </tr>
        <?php endforeach; ?>
    </table>
</div>
</body>
</html>
EOF

# series.php
sudo tee $APPDIR/series.php > /dev/null <<'EOF'
<?php
session_start();
if (!isset($_SESSION['admin_logged_in'])) {
    header("Location: index.html");
    exit();
}

$host = 'localhost';
$db = 'cloudtv';
$user = 'root';
$pass = 'CloudTVpass123';
$pdo = new PDO("mysql:host=$host;dbname=$db", $user, $pass);

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $series = $_POST['series'];
    $episode = $_POST['episode'];
    $url = $_POST['url'];
    $stmt = $pdo->prepare("INSERT INTO series (series, episode, url) VALUES (?, ?, ?)");
    $stmt->execute([$series, $episode, $url]);
    header("Location: series.php");
    exit();
}

$seriesList = $pdo->query("SELECT * FROM series ORDER BY id DESC")->fetchAll(PDO::FETCH_ASSOC);
?>
<!DOCTYPE html>
<html>
<head>
    <title>Cloud TV - Series</title>
    <style>
        body { background: #111; color: #fff; font-family: Arial; }
        .container { width: 80%; margin: auto; padding-top: 50px; }
        table { width: 100%; border-collapse: collapse; background: #222; }
        th, td { padding: 10px; border: 1px solid #444; }
        th { background: #333; }
        input { padding: 8px; width: 100%; background: #222; color: #fff; border: 1px solid #555; margin-bottom: 10px;}
        form { margin-bottom: 20px; }
        button { background: #2196f3; border: none; padding: 10px 15px; color: white; cursor: pointer; }
        button:hover { background: #1976d2; }
    </style>
</head>
<body>
<div class="container">
    <h2>TV Series (Episodes)</h2>
    <form method="POST">
        <input type="text" name="series" placeholder="Series Title" required>
        <input type="text" name="episode" placeholder="Episode Title" required>
        <input type="text" name="url" placeholder="Video URL" required>
        <button type="submit">Add Episode</button>
    </form>

    <table>
        <tr>
            <th>ID</th><th>Series</th><th>Episode</th><th>URL</th>
        </tr>
        <?php foreach ($seriesList as $row): ?>
        <tr>
            <td><?= $row['id'] ?></td>
            <td><?= htmlspecialchars($row['series']) ?></td>
            <td><?= htmlspecialchars($row['episode']) ?></td>
            <td><?= htmlspecialchars($row['url']) ?></td>
        </tr>
        <?php endforeach; ?>
    </table>
</div>
</body>
</html>
EOF

echo "Setting permissions..."
sudo chown -R www-data:www-data $APPDIR
sudo chmod -R 755 $APPDIR

echo "Enabling Apache rewrite module and allowing .htaccess overrides..."
sudo a2enmod rewrite
sudo sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf

echo "Restarting Apache..."
sudo systemctl restart apache2

echo "Installation complete!"
echo "Open your browser and visit: http://localhost/cloudtv"
echo "Login with username: admin and password: admin123"


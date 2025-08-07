#!/bin/bash
set -e

APP_NAME="cloud-tv-dashboard"
echo "Setting up Cloud TV Dashboard React app..."

# Create project directory
mkdir -p $APP_NAME
cd $APP_NAME

# Initialize package.json
cat > package.json <<EOF
{
  "name": "cloud-tv-dashboard",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-icons": "^4.8.0",
    "react-router-dom": "^6.14.2",
    "react-scripts": "5.0.1"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build"
  }
}
EOF

# Create folder structure
mkdir -p public src/components src/pages

# Write public/index.html
cat > public/index.html <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Cloud TV</title>
  <meta name="description" content="Cloud TV" />
</head>
<body>
  <div id="root"></div>
</body>
</html>
EOF

# Write public/cloud-tv-logo.svg
cat > public/cloud-tv-logo.svg <<'EOF'
<svg width="160" height="60" viewBox="0 0 320 120" xmlns="http://www.w3.org/2000/svg" fill="none">
  <defs>
    <linearGradient id="grad" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#00d4ff"/>
      <stop offset="100%" stop-color="#8a44ff"/>
    </linearGradient>
    <filter id="glow" x="-50%" y="-50%" width="200%" height="200%" color-interpolation-filters="sRGB">
      <feDropShadow dx="0" dy="0" stdDeviation="4" flood-color="#00d4ff" flood-opacity="0.7"/>
    </filter>
  </defs>
  <path filter="url(#glow)" fill="url(#grad)" d="M80 80c-22 0-40-18-40-40 0-17 12-32 29-37 7-18 26-30 47-26 22 4 38 23 38 45 0 22-17 40-39 40H80z"/>
  <text x="150" y="85" font-family="'Exo 2', sans-serif" font-weight="700" font-size="60" fill="url(#grad)" filter="url(#glow)">
    Cloud TV
  </text>
</svg>
EOF

# Write src/index.css
cat > src/index.css <<'EOF'
@import url('https://fonts.googleapis.com/css2?family=Exo+2:wght@400;700&display=swap');

:root {
  --bg-color: #0a0f30;
  --primary-color: #00d4ff;
  --secondary-color: #8a44ff;
  --text-light: #e0e6f8;
  --text-white: #ffffff;
  --cloud-gradient: linear-gradient(135deg, #00cfff 0%, #88d9ff 100%);
  --shadow-glow: 0 0 10px var(--primary-color);
  --padding-main: 25px;
  --card-margin: 25px;
}

* {
  box-sizing: border-box;
}

body {
  margin: 0;
  background: var(--bg-color);
  color: var(--text-light);
  font-family: 'Exo 2', sans-serif;
  overflow-x: hidden;
}

h1, h2, h3, h4, h5 {
  color: var(--text-white);
  margin: 0;
}

.neon-text {
  color: var(--primary-color);
  text-shadow:
    0 0 5px var(--primary-color),
    0 0 10px var(--primary-color),
    0 0 20px var(--primary-color);
}

button {
  background: var(--primary-color);
  color: var(--text-white);
  border: none;
  border-radius: 8px;
  padding: 10px 20px;
  box-shadow: var(--shadow-glow);
  cursor: pointer;
  transition: background 0.3s ease;
  font-weight: 600;
}

button:hover {
  background: var(--secondary-color);
  box-shadow: 0 0 20px var(--secondary-color);
}

.container {
  max-width: 1200px;
  margin: 0 auto;
  padding: var(--padding-main);
}

.card {
  background: linear-gradient(145deg, #0e143d, #121740);
  border-radius: 15px;
  box-shadow:
    0 0 20px rgba(0, 212, 255, 0.3),
    inset 0 0 10px rgba(255, 255, 255, 0.1);
  padding: 25px;
  margin-bottom: var(--card-margin);
  color: var(--text-white);
  display: flex;
  align-items: center;
  gap: 15px;
}

.sidebar {
  width: 250px;
  background: linear-gradient(180deg, #00142e 0%, #051935 100%);
  height: 100vh;
  color: var(--text-light);
  padding: 30px 20px;
  box-shadow: inset -3px 0 10px rgba(0, 212, 255, 0.3);
  position: fixed;
  top: 0;
  left: 0;
}

.sidebar a, .sidebar .active-link {
  display: block;
  padding: 15px 10px;
  color: var(--text-light);
  text-decoration: none;
  font-weight: 600;
  border-radius: 8px;
  margin-bottom: 10px;
  transition: background 0.3s ease;
}

.sidebar .active-link, .sidebar a:hover {
  background: var(--primary-color);
  color: var(--text-white);
  box-shadow: 0 0 10px var(--primary-color);
}

main.container {
  margin-left: 270px;
  padding-top: 20px;
  padding-bottom: 40px;
}

::-webkit-scrollbar {
  width: 8px;
}

::-webkit-scrollbar-track {
  background: #0a0f30;
}

::-webkit-scrollbar-thumb {
  background: var(--primary-color);
  border-radius: 4px;
}

@keyframes moveClouds {
  0% { background-position: 0 0; }
  100% { background-position: 1000px 0; }
}

body {
  background-image: url('https://assets.codepen.io/13471/clouds.svg');
  background-repeat: repeat-x;
  animation: moveClouds 60s linear infinite;
}
EOF

# Write src/index.js
cat > src/index.js <<'EOF'
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import './index.css';

ReactDOM.createRoot(document.getElementById('root')).render(<App />);
EOF

# Write src/App.jsx
cat > src/App.jsx <<'EOF'
import React from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import DashboardHeader from './components/DashboardHeader';
import Sidebar from './components/Sidebar';
import DashboardPage from './pages/DashboardPage';
import UsersPage from './pages/UsersPage';
import SubscriptionsPage from './pages/SubscriptionsPage';
import VodPage from './pages/VodPage';
import BillingPage from './pages/BillingPage';
import SettingsPage from './pages/SettingsPage';

export default function App() {
  return (
    <Router>
      <div style={{ display: 'flex', height: '100vh', fontFamily: "'Exo 2', sans-serif" }}>
        <Sidebar />
        <div style={{ flexGrow: 1, backgroundColor: 'var(--bg-color)', overflowY: 'auto' }}>
          <DashboardHeader />
          <main className="container">
            <Routes>
              <Route path="/" element={<DashboardPage />} />
              <Route path="/users" element={<UsersPage />} />
              <Route path="/subscriptions" element={<SubscriptionsPage />} />
              <Route path="/vod" element={<VodPage />} />
              <Route path="/billing" element={<BillingPage />} />
              <Route path="/settings" element={<SettingsPage />} />
            </Routes>
          </main>
        </div>
      </div>
    </Router>
  );
}
EOF

# Write components/DashboardHeader.jsx
cat > src/components/DashboardHeader.jsx <<'EOF'
import React from 'react';

export default function DashboardHeader() {
  return (
    <header style={{
      background: 'var(--cloud-gradient)',
      padding: '20px',
      borderRadius: '0 0 20px 20px',
      boxShadow: '0 4px 20px rgba(0, 212, 255, 0.4)',
      color: 'var(--text-white)',
      fontWeight: '700',
      fontSize: '2rem',
      textAlign: 'center',
      letterSpacing: '2px',
      userSelect: 'none',
      marginBottom: '30px'
    }}>
      Cloud TV Dashboard
    </header>
  );
}
EOF

# Write components/Sidebar.jsx
cat > src/components/Sidebar.jsx <<'EOF'
import React from 'react';
import { NavLink } from 'react-router-dom';

export default function Sidebar() {
  return (
    <nav className="sidebar">
      <img src="/cloud-tv-logo.svg" alt="Cloud TV Logo" style={{ width: '150px', marginBottom: '40px' }} />
      <NavLink to="/" end className={({ isActive }) => (isActive ? 'active-link' : '')}>Dashboard</NavLink>
      <NavLink to="/users" className={({ isActive }) => (isActive ? 'active-link' : '')}>Users</NavLink>
      <NavLink to="/subscriptions" className={({ isActive }) => (isActive ? 'active-link' : '')}>Subscriptions</NavLink>
      <NavLink to="/vod" className={({ isActive }) => (isActive ? 'active-link' : '')}>VOD / Series</NavLink>
      <NavLink to="/billing" className={({ isActive }) => (isActive ? 'active-link' : '')}>Billing</NavLink>
      <NavLink to="/settings" className={({ isActive }) => (isActive ? 'active-link' : '')}>Settings</NavLink>
    </nav>
  );
}
EOF

# Write components/StatsCard.jsx
cat > src/components/StatsCard.jsx <<'EOF'
import React from 'react';

export default function StatsCard({ title, value, icon }) {
  return (
    <div className="card">
      <div style={{ fontSize: '2.5rem', color: 'var(--primary-color)' }}>{icon}</div>
      <div>
        <h3 className="neon-text" style={{ margin: 0 }}>{value}</h3>
        <p style={{ margin: 0, opacity: 0.7 }}>{title}</p>
      </div>
    </div>
  );
}
EOF

# Write pages/DashboardPage.jsx
cat > src/pages/DashboardPage.jsx <<'EOF'
import React from 'react';
import StatsCard from '../components/StatsCard';
import { FiUsers, FiTv, FiVideo, FiActivity } from 'react-icons/fi';

export default function DashboardPage() {
  return (
    <>
      <h2 className="neon-text">Welcome to Cloud TV</h2>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(280px,1fr))', gap: 20 }}>
        <StatsCard icon={<FiUsers />} title="Active Users" value="1,243" />
        <StatsCard icon={<FiTv />} title="Live Channels" value="86" />
        <StatsCard icon={<FiVideo />} title="VOD Titles" value="512" />
        <StatsCard icon={<FiActivity />} title="Bandwidth Usage" value="2.4 TB" />
      </div>
    </>
  );
}
EOF

# Write placeholder pages for other routes (UsersPage, SubscriptionsPage, VodPage, BillingPage, SettingsPage)
for page in UsersPage SubscriptionsPage VodPage BillingPage SettingsPage; do
  cat > src/pages/$page.jsx <<EOF
import React from 'react';

export default function $page() {
  return <h2 style={{ color: 'var(--text-white)' }}>$page (coming soon)</h2>;
}
EOF
done

echo "Installing npm packages..."
npm install

echo "Setup complete! Run your app with:"
echo "  cd $APP_NAME"
echo "  npm start"

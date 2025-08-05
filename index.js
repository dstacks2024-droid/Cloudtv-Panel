
// CloudTV Backend Entry Point
const express = require('express');
const app = express();
const port = 3000;

app.get('/', (req, res) => res.send('CloudTV Backend Running'));
app.listen(port, () => console.log(`Backend live on port ${port}`));

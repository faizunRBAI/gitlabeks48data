const express = require('express');
const requestLogger = require('./middleware/requestLogger');
const errorHandler  = require('./middleware/errorHandler');
const routes        = require('./routes');

const db = require('./config/database');
db.connect();

const app = express();

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(requestLogger);

// Serve static files if public/ directory exists
const fs   = require('fs');
const path = require('path');
const pub  = path.join(__dirname, '..', 'public');
if (fs.existsSync(pub)) app.use(express.static(pub));

app.use('/', routes);
app.use(errorHandler);

module.exports = app;

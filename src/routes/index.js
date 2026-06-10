const router  = require('express').Router();
const health  = require('./health');
const api     = require('./api');

router.use('/health', health);
router.use('/api',    api);

// Catch-all — serve index.html for SPA or return 200
const fs   = require('fs');
const path = require('path');
router.get('/{*path}', (_req, res) => {
  const idx = path.join(__dirname, '..', '..', 'public', 'index.html');
  return fs.existsSync(idx)
    ? res.sendFile(idx)
    : res.status(200).send('App is running');
});

module.exports = router;

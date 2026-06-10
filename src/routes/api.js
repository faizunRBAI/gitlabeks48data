const router = require('express').Router();

// GET /api/info
router.get('/info', (_req, res) => {
  const dbStatus = process.env.DATABASE_URL ? 'connected' : 'not-configured';
  res.json({
    app:     'node-express',
    version: process.env.npm_package_version || '1.0.0',
    db:      dbStatus,
    env:     process.env.NODE_ENV || 'development',
  });
});

// Add your own routes below this line
// router.get('/users', userController.list);

module.exports = router;

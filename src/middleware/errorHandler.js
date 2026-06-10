// eslint-disable-next-line no-unused-vars
module.exports = (err, _req, res, _next) => {
  const status = err.status || 500;
  console.error(`[ERROR] ${status}:`, err.message);
  res.status(status).json({
    error:   err.message || 'Internal Server Error',
    status,
  });
};

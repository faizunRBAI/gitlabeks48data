const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
});

module.exports = {
  connect: async () => {
    try {
      await pool.query('SELECT 1');
      console.log('PostgreSQL connected');
    } catch (err) {
      console.error('PostgreSQL connection failed:', err.message);
    }
  },
  query: (text, params) => pool.query(text, params),
};

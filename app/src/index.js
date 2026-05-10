const express = require('express');
const todosRouter = require('./routes/todos');
const { pool, initDb } = require('./db');

const app = express();
app.use(express.json());

// Liveness: process is up
app.get('/healthz', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

// Readiness: dependencies (DB) are reachable
app.get('/readyz', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.status(200).json({ status: 'ready' });
  } catch (err) {
    console.error('Readiness check failed:', err.message);
    res.status(503).json({ status: 'not_ready', error: err.message });
  }
});

app.use('/api/todos', todosRouter);

// Centralized error handler — logs to stdout so CloudWatch picks it up
app.use((err, req, res, next) => {
  console.error(JSON.stringify({
    level: 'error',
    message: err.message,
    stack: err.stack,
    path: req.path,
    method: req.method,
  }));
  res.status(err.status || 500).json({ error: err.message || 'Internal server error' });
});

const PORT = process.env.PORT || 3000;

// Don't start the server during tests — supertest spins up its own
if (require.main === module) {
  initDb()
    .then(() => {
      app.listen(PORT, () => {
        console.log(`Todo API listening on port ${PORT}`);
      });
    })
    .catch((err) => {
      console.error('Failed to initialize database:', err);
      process.exit(1);
    });
}

module.exports = app;

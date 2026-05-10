// Mock the db module BEFORE requiring the app — so tests don't need a real DB.
jest.mock('../src/db', () => ({
  pool: { query: jest.fn().mockResolvedValue({ rows: [], rowCount: 0 }) },
  initDb: jest.fn().mockResolvedValue(),
}));

const request = require('supertest');
const app = require('../src/index');
const { pool } = require('../src/db');

describe('Todo API', () => {
  beforeEach(() => {
    pool.query.mockClear();
  });

  test('GET /healthz returns 200', async () => {
    const res = await request(app).get('/healthz');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
  });

  test('GET /readyz returns 200 when DB is reachable', async () => {
    pool.query.mockResolvedValueOnce({ rows: [{ '?column?': 1 }] });
    const res = await request(app).get('/readyz');
    expect(res.status).toBe(200);
  });

  test('GET /readyz returns 503 when DB query fails', async () => {
    pool.query.mockRejectedValueOnce(new Error('connection refused'));
    const res = await request(app).get('/readyz');
    expect(res.status).toBe(503);
  });

  test('POST /api/todos rejects missing title', async () => {
    const res = await request(app).post('/api/todos').send({});
    expect(res.status).toBe(400);
  });

  test('POST /api/todos creates a todo', async () => {
    pool.query.mockResolvedValueOnce({
      rows: [{ id: 1, title: 'buy milk', completed: false, created_at: new Date().toISOString() }],
      rowCount: 1,
    });
    const res = await request(app).post('/api/todos').send({ title: 'buy milk' });
    expect(res.status).toBe(201);
    expect(res.body.title).toBe('buy milk');
  });

  test('GET /api/todos returns list', async () => {
    pool.query.mockResolvedValueOnce({ rows: [], rowCount: 0 });
    const res = await request(app).get('/api/todos');
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
  });
});

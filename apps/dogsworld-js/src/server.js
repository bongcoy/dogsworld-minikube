const express = require('express');
const { Pool, types } = require('pg');
const swaggerUi = require('swagger-ui-express');
const openapi = require('./openapi.json');

// Kolom `timestamp` (tanpa zona waktu) dibaca sebagai UTC supaya birthDate stabil di semua mesin.
types.setTypeParser(1114, (value) => new Date(value.replace(' ', 'T') + 'Z'));

const pool = new Pool({
  host: process.env.DB_HOST || 'postgres',
  port: parseInt(process.env.DB_PORT || '5432', 10),
  user: process.env.DB_USER || 'dogsworld',
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME || 'dogs',
  max: 10,
  idleTimeoutMillis: 30000,
});

const app = express();
app.use(express.json());

app.get('/swagger/index.html', (req, res) => res.redirect('/swagger/'));
app.use('/swagger', swaggerUi.serve, swaggerUi.setup(openapi));

const COLUMNS = '"Id", "Name", "Breed", "Age", "BirthDate", "HasOwner"';

function toDog(row) {
  return {
    id: row.Id,
    name: row.Name,
    breed: row.Breed,
    age: row.Age,
    birthDate: row.BirthDate,
    hasOwner: row.HasOwner,
  };
}

function parseId(value) {
  return /^\d+$/.test(value) ? parseInt(value, 10) : null;
}

function dogParams(dog) {
  return [
    dog.name ?? null,
    dog.breed ?? null,
    dog.age ?? 0,
    new Date(dog.birthDate ?? '0001-01-01T00:00:00Z').toISOString(),
    dog.hasOwner ?? false,
  ];
}

const wrap = (fn) => (req, res, next) => fn(req, res, next).catch(next);

app.get('/api/dogs', wrap(async (req, res) => {
  const result = await pool.query(`SELECT ${COLUMNS} FROM "Dog" ORDER BY "Id"`);
  res.json(result.rows.map(toDog));
}));

app.get('/api/dogs/:id', wrap(async (req, res) => {
  const id = parseId(req.params.id);
  if (id === null) return res.sendStatus(400);
  const result = await pool.query(`SELECT ${COLUMNS} FROM "Dog" WHERE "Id" = $1`, [id]);
  if (result.rows.length === 0) return res.sendStatus(404);
  res.json(toDog(result.rows[0]));
}));

app.post('/api/dogs', wrap(async (req, res) => {
  const result = await pool.query(
    `INSERT INTO "Dog" ("Name", "Breed", "Age", "BirthDate", "HasOwner")
     VALUES ($1, $2, $3, $4, $5)
     RETURNING ${COLUMNS}`,
    dogParams(req.body)
  );
  const dog = toDog(result.rows[0]);
  res.status(201).location(`/api/dogs/${dog.id}`).json(dog);
}));

app.put('/api/dogs/:id', wrap(async (req, res) => {
  const id = parseId(req.params.id);
  if (id === null || req.body.id !== id) return res.sendStatus(400);
  const result = await pool.query(
    `UPDATE "Dog"
     SET "Name" = $1, "Breed" = $2, "Age" = $3, "BirthDate" = $4, "HasOwner" = $5
     WHERE "Id" = $6`,
    [...dogParams(req.body), id]
  );
  if (result.rowCount === 0) return res.sendStatus(404);
  res.sendStatus(204);
}));

app.delete('/api/dogs/:id', wrap(async (req, res) => {
  const id = parseId(req.params.id);
  if (id === null) return res.sendStatus(400);
  const result = await pool.query(`DELETE FROM "Dog" WHERE "Id" = $1 RETURNING ${COLUMNS}`, [id]);
  if (result.rows.length === 0) return res.sendStatus(404);
  res.json(toDog(result.rows[0]));
}));

app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ error: 'internal error' });
});

const port = parseInt(process.env.PORT || '8080', 10);
app.listen(port, () => console.log(`dogsworld-js listening on ${port}`));

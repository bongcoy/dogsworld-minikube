const express = require('express');
const sql = require('mssql');
const swaggerUi = require('swagger-ui-express');
const openapi = require('./openapi.json');

const config = {
  server: process.env.DB_HOST || 'sqlserver',
  port: parseInt(process.env.DB_PORT || '1433', 10),
  user: process.env.DB_USER || 'sa',
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME || 'Dogs',
  options: { encrypt: false, trustServerCertificate: true },
  pool: { max: 10, min: 0, idleTimeoutMillis: 30000 },
};

const app = express();
app.use(express.json());

app.get('/swagger/index.html', (req, res) => res.redirect('/swagger/'));
app.use('/swagger', swaggerUi.serve, swaggerUi.setup(openapi));

let poolPromise;
function getPool() {
  if (!poolPromise) {
    poolPromise = new sql.ConnectionPool(config).connect().catch((err) => {
      poolPromise = undefined;
      throw err;
    });
  }
  return poolPromise;
}

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

function bindDog(request, dog) {
  return request
    .input('name', sql.NVarChar(sql.MAX), dog.name ?? null)
    .input('breed', sql.NVarChar(sql.MAX), dog.breed ?? null)
    .input('age', sql.Int, dog.age ?? 0)
    .input('birthDate', sql.DateTime2, new Date(dog.birthDate ?? '0001-01-01T00:00:00Z'))
    .input('hasOwner', sql.Bit, dog.hasOwner ?? false);
}

const wrap = (fn) => (req, res, next) => fn(req, res, next).catch(next);

app.get('/api/dogs', wrap(async (req, res) => {
  const pool = await getPool();
  const result = await pool.request().query('SELECT Id, Name, Breed, Age, BirthDate, HasOwner FROM dbo.Dog');
  res.json(result.recordset.map(toDog));
}));

app.get('/api/dogs/:id', wrap(async (req, res) => {
  const id = parseId(req.params.id);
  if (id === null) return res.sendStatus(400);
  const pool = await getPool();
  const result = await pool.request()
    .input('id', sql.Int, id)
    .query('SELECT Id, Name, Breed, Age, BirthDate, HasOwner FROM dbo.Dog WHERE Id = @id');
  if (result.recordset.length === 0) return res.sendStatus(404);
  res.json(toDog(result.recordset[0]));
}));

app.post('/api/dogs', wrap(async (req, res) => {
  const pool = await getPool();
  const result = await bindDog(pool.request(), req.body).query(
    `INSERT INTO dbo.Dog (Name, Breed, Age, BirthDate, HasOwner)
     OUTPUT INSERTED.Id, INSERTED.Name, INSERTED.Breed, INSERTED.Age, INSERTED.BirthDate, INSERTED.HasOwner
     VALUES (@name, @breed, @age, @birthDate, @hasOwner)`
  );
  const dog = toDog(result.recordset[0]);
  res.status(201).location(`/api/dogs/${dog.id}`).json(dog);
}));

app.put('/api/dogs/:id', wrap(async (req, res) => {
  const id = parseId(req.params.id);
  if (id === null || req.body.id !== id) return res.sendStatus(400);
  const pool = await getPool();
  const result = await bindDog(pool.request().input('id', sql.Int, id), req.body).query(
    `UPDATE dbo.Dog
     SET Name = @name, Breed = @breed, Age = @age, BirthDate = @birthDate, HasOwner = @hasOwner
     WHERE Id = @id`
  );
  if (result.rowsAffected[0] === 0) return res.sendStatus(404);
  res.sendStatus(204);
}));

app.delete('/api/dogs/:id', wrap(async (req, res) => {
  const id = parseId(req.params.id);
  if (id === null) return res.sendStatus(400);
  const pool = await getPool();
  const result = await pool.request()
    .input('id', sql.Int, id)
    .query(
      `DELETE FROM dbo.Dog
       OUTPUT DELETED.Id, DELETED.Name, DELETED.Breed, DELETED.Age, DELETED.BirthDate, DELETED.HasOwner
       WHERE Id = @id`
    );
  if (result.recordset.length === 0) return res.sendStatus(404);
  res.json(toDog(result.recordset[0]));
}));

app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ error: 'internal error' });
});

const port = parseInt(process.env.PORT || '8080', 10);
app.listen(port, () => console.log(`dogsworld-js listening on ${port}`));

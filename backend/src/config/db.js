const mongoose = require('mongoose');
const env = require('./env');

let memoryServer = null;

async function connectDb() {
  let uri = env.mongoUri;
  if (env.useMemoryDb) {
    // Zero-setup development database. Data is lost when the server stops.
    const { MongoMemoryServer } = require('mongodb-memory-server');
    memoryServer = await MongoMemoryServer.create();
    uri = memoryServer.getUri('mindbridge');
    console.log('[db] using in-memory MongoDB (data resets on restart)');
  }
  mongoose.set('strictQuery', true);
  await mongoose.connect(uri);
  console.log(`[db] connected to ${uri.replace(/\/\/[^@]+@/, '//***@')}`);
  return mongoose.connection;
}

async function disconnectDb() {
  await mongoose.disconnect();
  if (memoryServer) await memoryServer.stop();
}

module.exports = { connectDb, disconnectDb, isMemory: () => !!memoryServer };

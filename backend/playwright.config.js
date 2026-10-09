const { defineConfig } = require('@playwright/test');
const path = require('path');

// Ensure S:\temp is used on Windows to prevent C: drive disk space issues
const tempDir = process.env.TEMP || 'S:\\temp';
process.env.TEMP = tempDir;
process.env.TMP = tempDir;

module.exports = defineConfig({
  testDir: './e2e-playwright',
  timeout: 30000,
  expect: {
    timeout: 5000,
  },
  fullyParallel: false,
  workers: 1,
  retries: 0,
  reporter: [
    ['list'],
    ['html', { outputFolder: 'playwright-report', open: 'never' }],
  ],
  use: {
    baseURL: 'http://127.0.0.1:4000',
    extraHTTPHeaders: {
      'Content-Type': 'application/json',
    },
  },
  webServer: {
    command: 'node src/server.js --memory-db',
    url: 'http://127.0.0.1:4000/api/health',
    reuseExistingServer: false,
    timeout: 120000,
    env: {
      TEMP: tempDir,
      TMP: tempDir,
      USE_MEMORY_DB: 'true',
      NODE_ENV: 'test',
      PORT: '4000',
      CLOUDINARY_URL: '',
      GEMINI_API_KEY: '',
    },
  },
});

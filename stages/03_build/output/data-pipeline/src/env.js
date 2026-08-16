/**
 * Environment variable loading, Node/JS equivalent of the Python
 * python-dotenv pattern: load `.env` once, read secrets from
 * `process.env`, never hardcode them in source.
 *
 * Usage:
 *   import { requireEnv, optionalEnv } from './env.js';
 *   const apiKey = requireEnv('OUTSCRAPER_API_KEY'); // throws if missing
 *   const dbUrl = optionalEnv('SUPABASE_DB_URL');     // undefined if missing
 *
 * `.env` (gitignored, see .env.example for the expected shape) is loaded
 * automatically the moment this module — or anything that imports it — runs,
 * via the `dotenv/config` import below.
 */

import 'dotenv/config';

export function requireEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(
      `Missing required environment variable '${name}'. Set it in data-pipeline/.env (see .env.example) or your shell environment.`
    );
  }
  return value;
}

export function optionalEnv(name) {
  return process.env[name] || undefined;
}

#!/usr/bin/env node
// Builds the cafequiet marketing site: copies src/ to dist/ and injects the
// Supabase config from the environment.
//
// Node standard library only, no dependencies — per ICM's convention that a
// workspace shouldn't need an install step to run its own scripts.
//
//   SUPABASE_URL=... SUPABASE_ANON_KEY=... node build.js
//
// On Cloudflare Pages, set both as build environment variables and use
// `node build.js` as the build command with `dist` as the output directory.

'use strict';

const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, 'src');
const DIST = path.join(__dirname, 'dist');

const url = process.env.SUPABASE_URL;
const anonKey = process.env.SUPABASE_ANON_KEY;

// Fail loudly rather than shipping a page whose signup form silently does
// nothing. A build that "succeeds" into a dead form is the worse outcome.
if (!url || !anonKey) {
  console.error(
    'build failed: SUPABASE_URL and SUPABASE_ANON_KEY must both be set.\n' +
    '  SUPABASE_URL      ' + (url ? 'ok' : 'MISSING') + '\n' +
    '  SUPABASE_ANON_KEY ' + (anonKey ? 'ok' : 'MISSING')
  );
  process.exit(1);
}

fs.rmSync(DIST, { recursive: true, force: true });
fs.mkdirSync(DIST, { recursive: true });

let copied = 0;
for (const entry of fs.readdirSync(SRC)) {
  // The template becomes config.js below; it is not itself shipped.
  if (entry === 'config.template.js') continue;
  fs.copyFileSync(path.join(SRC, entry), path.join(DIST, entry));
  copied++;
}

const config = fs
  .readFileSync(path.join(SRC, 'config.template.js'), 'utf8')
  .replace('__SUPABASE_URL__', url)
  .replace('__SUPABASE_ANON_KEY__', anonKey);

fs.writeFileSync(path.join(DIST, 'config.js'), config);

console.log('built dist/ — ' + copied + ' file(s) copied, config.js generated');

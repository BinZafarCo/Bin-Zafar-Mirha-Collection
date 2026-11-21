import fs from 'node:fs';
import vm from 'node:vm';

let failed = false;
const ok = (msg) => console.log('PASS -', msg);
const err = (msg) => { console.error('FAIL -', msg); failed = true; };

function checkJs(code, label) {
  try {
    new vm.Script(code, { filename: label });
    ok(`JS syntax valid: ${label}`);
  } catch (e) {
    err(`JS syntax error in ${label}: ${e.message}`);
  }
}

for (const file of ['shared.js', 'supabase-config.js']) {
  if (!fs.existsSync(file)) err(`Missing ${file}`);
  else checkJs(fs.readFileSync(file, 'utf8'), file);
}

for (const html of ['index.html', 'customer.html', 'admin.html']) {
  if (!fs.existsSync(html)) { err(`Missing ${html}`); continue; }
  const content = fs.readFileSync(html, 'utf8');
  const scripts = [...content.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi)];
  scripts.forEach((m, i) => checkJs(m[1], `${html}#inline-${i + 1}`));
}

for (const cfFile of ['_redirects', '_headers', '404.html']) {
  if (fs.existsSync(cfFile)) ok(`Cloudflare Pages file present: ${cfFile}`);
  else err(`Missing ${cfFile}`);
}

const sqlPath = 'supabase/migrations/20261121000000_mirha_secure.sql';
if (!fs.existsSync(sqlPath)) {
  err(`Missing ${sqlPath}`);
} else {
  const sql = fs.readFileSync(sqlPath, 'utf8');
  if (/^\s*BEGIN;/m.test(sql) && /^\s*COMMIT;\s*$/m.test(sql)) ok('SQL wrapped in BEGIN/COMMIT');
  else err('SQL missing explicit BEGIN/COMMIT');

  const tables = [
    'roles', 'profiles', 'categories', 'tags', 'products', 'order_statuses',
    'orders', 'order_items', 'suppliers', 'supplier_payments', 'wishlists',
    'otps', 'settings', 'audit_logs', 'sessions', 'login_attempts'
  ];
  for (const t of tables) {
    if (sql.includes(`alter table public.${t} enable row level security`)) ok(`RLS enabled: ${t}`);
    else err(`RLS missing on table: ${t}`);
  }
  for (const fn of ['create_order', 'get_my_orders', 'track_order', 'has_role']) {
    if (sql.includes(`function public.${fn}(`)) ok(`SQL function present: ${fn}`);
    else err(`SQL function missing: ${fn}`);
  }
  if (sql.includes("tablename = any(array[")) ok('Policy cleanup scoped to MIRHA tables');
  else err('Policy cleanup not scoped to MIRHA tables');
}

const fnPath = 'supabase/functions/admin-suppliers/index.ts';
if (!fs.existsSync(fnPath)) {
  err(`Missing ${fnPath}`);
} else {
  const fn = fs.readFileSync(fnPath, 'utf8');
  if (fn.includes('APP_ORIGIN') && fn.includes("role !== 'admin'") && fn.includes('auth.getUser()')) {
    ok('admin-suppliers security guards present');
  } else {
    err('admin-suppliers missing APP_ORIGIN or JWT/admin checks');
  }
}

if (failed) process.exit(1);
console.log('\nAll static checks passed.');

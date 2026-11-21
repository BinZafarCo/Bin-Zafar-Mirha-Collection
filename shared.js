// MIRHA COLLECTION - Shared JS
let _mirhaSbClient = null;

function sharedEsc(s) {
  if (s == null) return '';
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function sharedClean(s, maxLen = 120) {
  if (!s) return '';
  return String(s)
    .replace(/<[^>]*>/g, '')
    .replace(/javascript:/gi, '')
    .trim()
    .slice(0, maxLen);
}

function sharedSafeJSON(k, fallback = []) {
  try {
    const v = localStorage.getItem(k);
    if (!v) return fallback;
    const parsed = JSON.parse(v);
    if (Array.isArray(fallback) && !Array.isArray(parsed)) return fallback;
    if (!Array.isArray(fallback) && (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed))) return fallback;
    return parsed;
  } catch (e) {
    return fallback;
  }
}

function sharedNormalizePhone(p) {
  const digits = String(p || '').replace(/[^\d+]/g, '').trim();
  if (/^\+923\d{9}$/.test(digits)) return '0' + digits.slice(3);
  if (/^923\d{9}$/.test(digits)) return '0' + digits.slice(2);
  if (/^03\d{9}$/.test(digits)) return digits;
  return String(p || '').trim();
}

function sharedIsValidPhone(p) {
  return /^03[0-9]{9}$/.test(sharedNormalizePhone(p));
}

function sharedToE164(p) {
  const local = sharedNormalizePhone(p);
  if (!sharedIsValidPhone(local)) throw new Error('Phone sahi likho - 03xxxxxxxxx');
  return '+92' + local.slice(1);
}

function sharedFormatPrice(n) {
  return 'Rs.' + Number(n || 0).toLocaleString('en-PK');
}

function sharedWaLink(num, msg) {
  let n = String(num || '03427349881').replace(/\D/g, '');
  if (n.startsWith('03')) n = '92' + n.slice(1);
  return 'https://wa.me/' + n + '?text=' + encodeURIComponent(msg || 'Salam Mirha Collection!');
}

function sharedGetWA() {
  return '03427349881';
}

function sharedToast(msg) {
  const d = document.createElement('div');
  d.textContent = msg;
  d.style.cssText = 'position:fixed;bottom:90px;left:50%;transform:translateX(-50%);background:#C9A227;color:#000;padding:10px 18px;border-radius:20px;font-weight:800;z-index:999;max-width:90%;text-align:center';
  document.body.appendChild(d);
  setTimeout(() => d.remove(), 2500);
}

function sharedSupabase() {
  if (_mirhaSbClient) return _mirhaSbClient;
  const cfg = window.MIRHA_SUPABASE_CONFIG || {};
  const url = String(cfg.url || '').trim();
  const key = String(cfg.anonKey || '').trim();
  if (!url || !key || url.includes('YOUR_PROJECT_REF') || key.includes('YOUR_SUPABASE')) {
    throw new Error('Supabase configuration required in supabase-config.js');
  }
  if (!/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(url)) {
    throw new Error('Invalid Supabase project URL');
  }
  if (!window.supabase || typeof window.supabase.createClient !== 'function') {
    throw new Error('Supabase JS library failed to load');
  }
  _mirhaSbClient = window.supabase.createClient(url, key, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
  });
  return _mirhaSbClient;
}
```
---

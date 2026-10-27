const cfg = require('../config');
const SESSION_KEY = 'duoduo-supabase-session';

function friendlyNetworkError(err) {
  const msg = String(err?.errMsg || err?.message || '网络请求失败');
  const lower = msg.toLowerCase();
  if (lower.includes('domain') || lower.includes('url not in domain list') || lower.includes('合法域名')) {
    return new Error('Supabase 域名还没有加入微信 request 合法域名。开发工具可先关闭域名校验，真机前再到小程序后台配置。');
  }
  if (lower.includes('timeout')) return new Error('网络请求超时，请检查网络后再试');
  if (lower.includes('ssl') || lower.includes('tls')) return new Error('HTTPS/TLS 连接失败，请检查小程序服务器域名配置');
  return new Error(msg.replace(/^request:fail\s*/i, '') || '网络请求失败');
}

function request(options) {
  return new Promise((resolve, reject) => {
    wx.request({
      ...options,
      success(res) {
        if (res.statusCode >= 200 && res.statusCode < 300) resolve(res.data);
        else reject(new Error((res.data && (res.data.msg || res.data.message || res.data.error_description || res.data.error)) || `请求失败 ${res.statusCode}`));
      },
      fail(err) { reject(friendlyNetworkError(err)); }
    });
  });
}

function restoreSession() { return wx.getStorageSync(SESSION_KEY) || null; }
function clearSession() { wx.removeStorageSync(SESSION_KEY); }
function saveSession(raw) {
  const session = {
    access_token: raw.access_token,
    refresh_token: raw.refresh_token,
    expires_at: Math.floor(Date.now() / 1000) + Number(raw.expires_in || 3600),
    user: raw.user
  };
  wx.setStorageSync(SESSION_KEY, session);
  return session;
}

async function signIn(email, password) {
  const data = await request({
    url: `${cfg.supabaseUrl}/auth/v1/token?grant_type=password`, method: 'POST',
    header: { apikey: cfg.supabaseKey, 'Content-Type': 'application/json' },
    data: { email, password }
  });
  return saveSession(data);
}

async function refreshSession(session) {
  if (!session?.refresh_token) return null;
  const data = await request({
    url: `${cfg.supabaseUrl}/auth/v1/token?grant_type=refresh_token`, method: 'POST',
    header: { apikey: cfg.supabaseKey, 'Content-Type': 'application/json' },
    data: { refresh_token: session.refresh_token }
  });
  return saveSession(data);
}

async function session() {
  let s = restoreSession();
  if (!s) return null;
  if (Number(s.expires_at || 0) < Math.floor(Date.now() / 1000) + 90) {
    try { s = await refreshSession(s); } catch (_) { clearSession(); return null; }
  }
  return s;
}

async function authHeaders(extra = {}) {
  const s = await session();
  if (!s) throw new Error('NOT_SIGNED_IN');
  return { apikey: cfg.supabaseKey, Authorization: `Bearer ${s.access_token}`, ...extra };
}

async function getSnapshot() {
  const s = await session();
  if (!s) throw new Error('NOT_SIGNED_IN');
  const rows = await request({
    url: `${cfg.supabaseUrl}/rest/v1/fitness_snapshots?select=payload&user_id=eq.${encodeURIComponent(s.user.id)}`,
    header: await authHeaders({ Accept: 'application/json' })
  });
  return rows?.[0]?.payload || {};
}

async function saveSnapshot(payload) {
  const s = await session();
  if (!s) throw new Error('NOT_SIGNED_IN');
  return request({
    url: `${cfg.supabaseUrl}/rest/v1/fitness_snapshots?on_conflict=user_id`, method: 'POST',
    header: await authHeaders({
      'Content-Type': 'application/json',
      Prefer: 'resolution=merge-duplicates,return=minimal'
    }),
    data: { user_id: s.user.id, payload, schema_version: 1 }
  });
}

async function analyzeFood(imageBase64, context = '') {
  return request({
    url: `${cfg.supabaseUrl}/functions/v1/analyze-food`, method: 'POST',
    header: await authHeaders({ 'Content-Type': 'application/json' }),
    data: { imageBase64, context }
  });
}

module.exports = { request, restoreSession, clearSession, signIn, session, getSnapshot, saveSnapshot, analyzeFood };

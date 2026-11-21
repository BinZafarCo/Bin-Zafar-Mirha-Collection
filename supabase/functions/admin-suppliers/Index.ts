import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'

const allowedOrigins = (Deno.env.get('APP_ORIGIN') ?? '')
  .split(',')
  .map((o) => o.trim().replace(/\/+$/, ''))
  .filter(Boolean)

function corsHeaders(req: Request) {
  const reqOrigin = (req.headers.get('Origin') ?? '').replace(/\/+$/, '')
  const origin = allowedOrigins.includes(reqOrigin)
    ? reqOrigin
    : (allowedOrigins[0] || 'null')
  return {
    'Access-Control-Allow-Origin': origin,
    'Vary': 'Origin',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
  }
}

const isPositiveInt = (v: unknown) =>
  (typeof v === 'number' && Number.isInteger(v) && v > 0) ||
  (typeof v === 'string' && /^\d+$/.test(v) && Number(v) > 0)

const INVALID = Symbol('invalid')
const parseCost = (v: unknown): number | null | typeof INVALID => {
  if (v === null || v === undefined || v === '') return null
  const n = typeof v === 'number' ? v : Number(String(v).trim())
  return Number.isInteger(n) && n >= 0 && n <= 100000000 ? n : INVALID
}

const validStatus = (v: unknown) => ['Active', 'Inactive', 'Pending Payment'].includes(String(v))
const validBankLast4 = (v: unknown) => v == null || v === '' || /^\d{4}$/.test(String(v).trim())
const cleanOptStr = (v: unknown, max: number) =>
  v == null || String(v).trim() === '' ? null : String(v).trim().slice(0, max)

Deno.serve(async (req) => {
  const cors = corsHeaders(req)
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (!allowedOrigins.length) return json({ error: 'APP_ORIGIN must be configured before deployment' }, 500)
  if (!['GET', 'POST'].includes(req.method)) return json({ error: 'Method not allowed' }, 405)

  const url = Deno.env.get('SUPABASE_URL')!
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

  const auth = req.headers.get('Authorization')
  if (!auth?.startsWith('Bearer ')) return json({ error: 'Authentication required' }, 401)

  const userClient = createClient(url, anon, { global: { headers: { Authorization: auth } } })
  const { data: { user }, error: userError } = await userClient.auth.getUser()
  if (userError || !user) return json({ error: 'Invalid session' }, 401)

  const admin = createClient(url, service)
  const { data: profile, error: profileError } = await admin
    .from('profiles')
    .select('role')
    .eq('id', user.id)
    .maybeSingle()

  if (profileError || profile?.role !== 'admin') {
    return json({ error: 'Admin access required' }, 403)
  }

  if (req.method === 'GET') {
    const { data, error } = await admin.from('suppliers').select('*').order('created_at', { ascending: false })
    if (error) return json({ error: 'Could not load suppliers' }, 500)
    return json({ suppliers: data })
  }

  const body = await req.json().catch(() => null)
  if (!body || typeof body !== 'object' || !['create', 'update', 'delete'].includes(body.action)) {
    return json({ error: 'Invalid action' }, 400)
  }

  if (body.action === 'create') {
    const name = typeof body.name === 'string' ? body.name.trim() : ''
    const phone = typeof body.phone === 'string' ? body.phone.trim() : ''
    const cost = parseCost(body.cost)
    const status = body.status || 'Active'

    if (name.length < 2 || name.length > 80 || !/^03\d{9}$/.test(phone)) {
      return json({ error: 'Name (2-80 chars) or phone (03xxxxxxxxx) invalid' }, 400)
    }
    if (cost === INVALID || !validBankLast4(body.bank_last4) || !validStatus(status)) {
      return json({ error: 'Cost, bank last 4 digits, or status invalid' }, 400)
    }

    const { data, error } = await admin
      .from('suppliers')
      .insert({
        name,
        phone,
        product: cleanOptStr(body.product, 120),
        cost,
        bank_name: cleanOptStr(body.bank_name, 60),
        bank_last4: cleanOptStr(body.bank_last4, 4),
        status
      })
      .select('*')
      .single()

    if (error) return json({ error: 'Supplier could not be saved' }, 400)
    await admin.from('audit_logs').insert({
      user_id: user.id,
      action: 'Supplier created',
      table_name: 'suppliers',
      record_id: String(data.id)
    })
    return json({ supplier: data }, 201)
  }

  if (!isPositiveInt(body.id)) return json({ error: 'Invalid supplier id' }, 400)
  const id = Number(body.id)

  if (body.action === 'update') {
    const allowed = ['name', 'phone', 'product', 'cost', 'bank_name', 'bank_last4', 'status']
    const patch: Record<string, unknown> = {}

    for (const k of allowed) {
      if (k in body) patch[k] = body[k]
    }
    if ('name' in patch) {
      if (typeof patch.name !== 'string' || patch.name.trim().length < 2 || patch.name.trim().length > 80) {
        return json({ error: 'Name invalid' }, 400)
      }
      patch.name = patch.name.trim()
    }
    if ('phone' in patch && (typeof patch.phone !== 'string' || !/^03\d{9}$/.test(patch.phone.trim()))) {
      return json({ error: 'Phone invalid' }, 400)
    }
    if ('phone' in patch) patch.phone = String(patch.phone).trim()

    if ('cost' in patch) {
      const parsed = parseCost(patch.cost)
      if (parsed === INVALID) return json({ error: 'Cost invalid' }, 400)
      patch.cost = parsed
    }
    if ('bank_last4' in patch) {
      if (!validBankLast4(patch.bank_last4)) return json({ error: 'Bank last four digits invalid' }, 400)
      patch.bank_last4 = cleanOptStr(patch.bank_last4, 4)
    }
    if ('product' in patch) patch.product = cleanOptStr(patch.product, 120)
    if ('bank_name' in patch) patch.bank_name = cleanOptStr(patch.bank_name, 60)
    if ('status' in patch && !validStatus(patch.status)) return json({ error: 'Status invalid' }, 400)

    if (!Object.keys(patch).length) return json({ error: 'No valid fields supplied' }, 400)

    const { data, error } = await admin.from('suppliers').update(patch).eq('id', id).select('*').single()
    if (error) return json({ error: 'Supplier could not be updated' }, 400)

    await admin.from('audit_logs').insert({
      user_id: user.id,
      action: 'Supplier updated',
      table_name: 'suppliers',
      record_id: String(data.id)
    })
    return json({ supplier: data })
  }

  const { error } = await admin.from('suppliers').delete().eq('id', id)
  if (error) return json({ error: 'Supplier could not be deleted' }, 400)
  await admin.from('audit_logs').insert({
    user_id: user.id,
    action: 'Supplier deleted',
    table_name: 'suppliers',
    record_id: String(id)
  })
  return json({ success: true })
})

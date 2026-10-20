import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

function json(status:number, body:unknown){
  return new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json; charset=utf-8'}})
}

async function sha256(text:string){
  const bytes=new TextEncoder().encode(text)
  const digest=await crypto.subtle.digest('SHA-256',bytes)
  return [...new Uint8Array(digest)].map(b=>b.toString(16).padStart(2,'0')).join('')
}

function pick(obj:any, keys:string[]){
  for(const k of keys){
    const v=obj?.[k]
    if(v!==undefined && v!==null && v!=='') return v
  }
  return null
}

function asIso(value:any){
  if(!value) return null
  const d=new Date(value)
  return Number.isNaN(d.getTime())?null:d.toISOString()
}

Deno.serve(async(req:Request)=>{
  if(req.method!=='POST') return json(405,{error:'method_not_allowed'})
  try{
    const auth=req.headers.get('authorization')||''
    const headerToken=req.headers.get('x-health-token')||''
    const token=auth.toLowerCase().startsWith('bearer ')?auth.slice(7).trim():headerToken.trim()
    if(!token || token.length<20) return json(401,{error:'invalid_token'})

    const supabaseUrl=Deno.env.get('SUPABASE_URL')||''
    const serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||''
    if(!supabaseUrl||!serviceKey) return json(500,{error:'server_not_configured'})
    const admin=createClient(supabaseUrl,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}})

    const tokenHash=await sha256(token)
    const {data:tokenRow,error:tokenError}=await admin
      .from('health_import_tokens')
      .select('user_id, revoked_at')
      .eq('token_hash',tokenHash)
      .maybeSingle()
    if(tokenError) throw tokenError
    if(!tokenRow || tokenRow.revoked_at) return json(401,{error:'invalid_token'})

    const length=Number(req.headers.get('content-length')||0)
    if(length>8_000_000) return json(413,{error:'payload_too_large'})
    const raw=await req.json().catch(()=>null)
    if(!raw || typeof raw!=='object') return json(400,{error:'invalid_json'})

    const eventType=String(pick(raw,['type','name','metric','dataType','workoutType','activityType'])||'health-export').slice(0,120)
    const startAt=asIso(pick(raw,['start','startDate','start_date','date','timestamp']))
    const endAt=asIso(pick(raw,['end','endDate','end_date']))
    const stableId=pick(raw,['id','uuid','workoutId','identifier'])
    const uniqueKey=stableId?`${eventType}:${String(stableId).slice(0,220)}`:null

    const {error:insertError}=await admin.from('health_import_events').insert({
      user_id:tokenRow.user_id,
      source:'health-auto-export',
      event_type:eventType,
      start_at:startAt,
      end_at:endAt,
      raw,
      unique_key:uniqueKey
    })
    if(insertError){
      if((insertError as any).code==='23505') return json(200,{ok:true,duplicate:true})
      throw insertError
    }
    return json(200,{ok:true})
  }catch(error){
    console.error(error)
    return json(500,{error:'import_failed'})
  }
})

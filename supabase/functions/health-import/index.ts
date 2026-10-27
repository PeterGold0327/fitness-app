import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

function json(status:number, body:unknown){return new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json; charset=utf-8'}})}
async function sha256(text:string){const bytes=new TextEncoder().encode(text);const digest=await crypto.subtle.digest('SHA-256',bytes);return [...new Uint8Array(digest)].map(b=>b.toString(16).padStart(2,'0')).join('')}
function pick(obj:any, keys:string[]){for(const k of keys){const v=obj?.[k];if(v!==undefined&&v!==null&&v!=='')return v}return null}
function asIso(value:any){if(!value)return null;const d=new Date(value);return Number.isNaN(d.getTime())?null:d.toISOString()}
function localDate(value:any){const text=String(value||'').trim();const m=text.match(/^(\d{4}-\d{2}-\d{2})/);if(m)return m[1];const d=new Date(text);return Number.isNaN(d.getTime())?null:d.toISOString().slice(0,10)}
function num(value:any){const n=Number(value);return Number.isFinite(n)?n:null}
function ensureDay(days:Record<string,any>,date:string){if(!days[date])days[date]={};return days[date]}
function add(day:any,key:string,value:any){const n=num(value);if(n===null)return;day[key]=(Number(day[key])||0)+n}
function average(list:number[]){return list.length?list.reduce((a,b)=>a+b,0)/list.length:null}
function isFunctionalStrength(w:any){const type=String(w?.activityType||'').toLowerCase();const name=String(w?.name||'').trim();return type==='functional_strength_training'||name==='功能性力量训练'}

function normalizeMetrics(raw:any){
  const metrics=Array.isArray(raw?.data?.metrics)?raw.data.metrics:[]
  const days:Record<string,any>={}
  const heartBuckets:Record<string,{avg:number[],min:number[],max:number[]}>= {}
  const restingBuckets:Record<string,number[]>= {}
  const wristBuckets:Record<string,number[]>= {}
  const weightBuckets:Record<string,number[]>= {}
  for(const metric of metrics){
    const name=String(metric?.name||'');const rows=Array.isArray(metric?.data)?metric.data:[]
    for(const row of rows){
      const date=localDate(row?.date||row?.start||row?.timestamp);if(!date)continue
      const day=ensureDay(days,date)
      if(name==='active_energy')add(day,'activeEnergyKj',row?.qty)
      else if(name==='basal_energy_burned')add(day,'basalEnergyKj',row?.qty)
      else if(name==='apple_exercise_time')add(day,'exerciseMinutes',row?.qty)
      else if(name==='apple_stand_time')add(day,'standMinutes',row?.qty)
      else if(name==='apple_stand_hour')add(day,'standHours',row?.qty)
      else if(name==='step_count')add(day,'steps',row?.qty)
      else if(name==='walking_running_distance')add(day,'distanceKm',row?.qty)
      else if(name==='sleep_analysis'){
        const total=num(row?.totalSleep)
        if(total!==null){day.sleepHours=total;day.sleepDeepHours=num(row?.deep)||0;day.sleepCoreHours=num(row?.core)||0;day.sleepRemHours=num(row?.rem)||0;day.sleepAwakeHours=num(row?.awake)||0;day.sleepStart=row?.sleepStart||row?.inBedStart||null;day.sleepEnd=row?.sleepEnd||row?.inBedEnd||null}
      }else if(name==='heart_rate'){
        const bucket=heartBuckets[date]||(heartBuckets[date]={avg:[],min:[],max:[]});const a=num(row?.Avg??row?.avg??row?.qty),mi=num(row?.Min??row?.min),ma=num(row?.Max??row?.max);if(a!==null)bucket.avg.push(a);if(mi!==null)bucket.min.push(mi);if(ma!==null)bucket.max.push(ma)
      }else if(name==='resting_heart_rate'){const v=num(row?.qty);if(v!==null)(restingBuckets[date]||(restingBuckets[date]=[])).push(v)}
      else if(name==='apple_sleeping_wrist_temperature'){const v=num(row?.qty);if(v!==null)(wristBuckets[date]||(wristBuckets[date]=[])).push(v)}
      else if(['weight','body_mass','body_weight'].includes(name)){const v=num(row?.qty);if(v!==null)(weightBuckets[date]||(weightBuckets[date]=[])).push(v)}
    }
  }
  for(const [date,b] of Object.entries(heartBuckets)){const day=ensureDay(days,date),avg=average(b.avg);if(avg!==null)day.heartRateAvg=avg;if(b.min.length)day.heartRateMin=Math.min(...b.min);if(b.max.length)day.heartRateMax=Math.max(...b.max)}
  for(const [date,b] of Object.entries(restingBuckets)){const v=average(b);if(v!==null)ensureDay(days,date).restingHeartRate=v}
  for(const [date,b] of Object.entries(wristBuckets)){const v=average(b);if(v!==null)ensureDay(days,date).wristTemperature=v}
  for(const [date,b] of Object.entries(weightBuckets)){const v=average(b);if(v!==null)ensureDay(days,date).weightKg=v}
  for(const day of Object.values(days)){if(Number.isFinite(day.activeEnergyKj))day.activeEnergyKcal=day.activeEnergyKj/4.184;if(Number.isFinite(day.basalEnergyKj))day.basalEnergyKcal=day.basalEnergyKj/4.184;for(const k of Object.keys(day))if(typeof day[k]==='number')day[k]=Math.round(day[k]*10)/10}
  return days
}

function normalizeWorkouts(raw:any){
  const rows=Array.isArray(raw?.data?.workouts)?raw.data.workouts:[]
  return rows.map((w:any)=>{
    const activity=Array.isArray(w?.activities)?w.activities[0]:null
    const active=num(activity?.metrics?.activeEnergy?.qty)??num(w?.activeEnergyBurned?.qty)
    const activeUnits=String(activity?.metrics?.activeEnergy?.units||w?.activeEnergyBurned?.units||'')
    const calories=active===null?null:(activeUnits.toLowerCase()==='kj'?active/4.184:active)
    const seconds=num(w?.duration)??num(activity?.duration)??0
    const hrAvg=num(w?.heartRate?.avg?.qty)??num(w?.avgHeartRate?.qty)??num(activity?.metrics?.heartRateAverage?.qty)
    const hrMin=num(w?.heartRate?.min?.qty)??num(activity?.metrics?.heartRateMinimum?.qty)
    const hrMax=num(w?.heartRate?.max?.qty)??num(w?.maxHeartRate?.qty)??num(activity?.metrics?.heartRateMaximum?.qty)
    return {
      id:String(w?.id||activity?.id||crypto.randomUUID()),
      date:localDate(w?.start||activity?.start),
      name:String(w?.name||activity?.activityType||'Apple Watch 训练'),
      activityType:String(activity?.activityType||''),
      start:w?.start||activity?.start||null,
      end:w?.end||activity?.end||null,
      minutes:Math.round((seconds/60)*10)/10,
      calories:calories===null?null:Math.round(calories*10)/10,
      heartRateAvg:hrAvg===null?null:Math.round(hrAvg*10)/10,
      heartRateMin:hrMin,
      heartRateMax:hrMax,
      source:'apple-health'
    }
  }).filter((w:any)=>w.date)
}

function mergeFunctionalStrength(payload:any, healthWorkouts:any[]){
  const gym=Array.isArray(payload.workouts)?[...payload.workouts]:[]
  const strength=healthWorkouts.filter(isFunctionalStrength)
  for(const watch of strength){
    const watchId=String(watch?.id||'')
    let index=gym.findIndex((x:any)=>String(x?.watchWorkoutId||'')===watchId)
    if(index<0)index=gym.findIndex((x:any)=>x?.date===watch.date&&x?.source==='apple-health-strength')
    if(index<0)index=gym.findIndex((x:any)=>x?.date===watch.date&&x?.source!=='apple-health-strength'&&!x?.watchWorkoutId&&Array.isArray(x?.exercises)&&x.exercises.length>0)
    if(index<0)index=gym.findIndex((x:any)=>x?.date===watch.date&&x?.source!=='apple-health-strength'&&!x?.watchWorkoutId)

    const watchFields:any={
      watchWorkoutId:watchId,
      watchStart:watch.start||null,
      watchEnd:watch.end||null,
      watchHeartRateAvg:watch.heartRateAvg??null,
      watchHeartRateMin:watch.heartRateMin??null,
      watchHeartRateMax:watch.heartRateMax??null,
      metricsSource:'apple-watch'
    }
    if(num(watch.minutes)!==null)watchFields.minutes=num(watch.minutes)
    if(num(watch.calories)!==null)watchFields.calories=num(watch.calories)

    if(index>=0){
      gym[index]={...gym[index],...watchFields}
    }else{
      gym.push({
        id:`watch-strength-${watchId||crypto.randomUUID()}`,
        date:watch.date,
        name:'健身',
        split:'健身',
        source:'apple-health-strength',
        exercises:[],
        ...watchFields
      })
    }
  }
  payload.workouts=gym
  return healthWorkouts.filter((w:any)=>!isFunctionalStrength(w))
}

Deno.serve(async(req:Request)=>{
  if(req.method!=='POST')return json(405,{error:'method_not_allowed'})
  try{
    const auth=req.headers.get('authorization')||'';const headerToken=req.headers.get('x-health-token')||'';const token=auth.toLowerCase().startsWith('bearer ')?auth.slice(7).trim():headerToken.trim()
    if(!token||token.length<20)return json(401,{error:'invalid_token'})
    const supabaseUrl=Deno.env.get('SUPABASE_URL')||'';const serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||''
    if(!supabaseUrl||!serviceKey)return json(500,{error:'server_not_configured'})
    const admin=createClient(supabaseUrl,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}})
    const tokenHash=await sha256(token)
    const {data:tokenRow,error:tokenError}=await admin.from('health_import_tokens').select('user_id, revoked_at').eq('token_hash',tokenHash).maybeSingle()
    if(tokenError)throw tokenError;if(!tokenRow||tokenRow.revoked_at)return json(401,{error:'invalid_token'})
    const length=Number(req.headers.get('content-length')||0);if(length>8_000_000)return json(413,{error:'payload_too_large'})
    const raw=await req.json().catch(()=>null);if(!raw||typeof raw!=='object')return json(400,{error:'invalid_json'})
    const eventType=String(pick(raw,['type','name','metric','dataType','workoutType','activityType'])||'health-export').slice(0,120)
    const startAt=asIso(pick(raw,['start','startDate','start_date','date','timestamp']));const endAt=asIso(pick(raw,['end','endDate','end_date']));const stableId=pick(raw,['id','uuid','workoutId','identifier']);const uniqueKey=stableId?`${eventType}:${String(stableId).slice(0,220)}`:null
    const {error:insertError}=await admin.from('health_import_events').insert({user_id:tokenRow.user_id,source:'health-auto-export',event_type:eventType,start_at:startAt,end_at:endAt,raw,unique_key:uniqueKey})
    if(insertError&&(insertError as any).code!=='23505')throw insertError

    const normalizedDays=normalizeMetrics(raw);const normalizedWorkouts=normalizeWorkouts(raw)
    if(Object.keys(normalizedDays).length||normalizedWorkouts.length){
      const {data:snapshot,error:snapshotError}=await admin.from('fitness_snapshots').select('payload').eq('user_id',tokenRow.user_id).maybeSingle();if(snapshotError)throw snapshotError
      const payload=snapshot?.payload&&typeof snapshot.payload==='object'?snapshot.payload:{}
      const health=payload.health&&typeof payload.health==='object'?payload.health:{}
      const daily=health.daily&&typeof health.daily==='object'?health.daily:{}
      const existing=Array.isArray(health.workouts)?health.workouts:[]
      const byId=new Map(existing.map((w:any)=>[String(w?.id||''),w]));for(const w of normalizedWorkouts)byId.set(String(w.id),w)
      const visibleHealthWorkouts=mergeFunctionalStrength(payload,[...byId.values()])
      payload.health={...health,source:'health-auto-export',updatedAt:new Date().toISOString(),daily:{...daily,...normalizedDays},workouts:visibleHealthWorkouts}
      const {error:updateError}=await admin.from('fitness_snapshots').upsert({user_id:tokenRow.user_id,payload,schema_version:1},{onConflict:'user_id'});if(updateError)throw updateError
    }
    return json(200,{ok:true,normalizedDays:Object.keys(normalizedDays).length,normalizedWorkouts:normalizedWorkouts.length})
  }catch(error){console.error(error);return json(500,{error:'import_failed'})}
})

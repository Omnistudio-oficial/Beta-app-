import { FLUTTER_FCM_APP_ID, isAllowedFlutterPushRecipient, isValidDevice } from "./push-routing.ts";
const corsHeaders = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info", "Access-Control-Allow-Methods": "POST, OPTIONS", "Content-Type": "application/json" };
const FIREBASE_PROJECT_ID = "omnistudio-caaf5";
const FIREBASE_IDENTITY_LOOKUP_URL = "https://identitytoolkit.googleapis.com/v1/accounts:lookup";
const GOOGLE_OAUTH_TOKEN_URL = "https://oauth2.googleapis.com/token";
const GOOGLE_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const MAX_ID_TOKEN_LENGTH = 4096;
type Identity = { uid: string; email: string };
type ServiceAccount = { client_email: string; private_key: string; project_id: string };
type DeviceRow = { uid: string; fcm_token: string; platform: "android" | "ios"; token_hash: string };
type PushInput = { recipientUid?: unknown; title?: unknown; body?: unknown; data?: unknown };
function jsonResponse(body: Record<string, unknown>, status = 200): Response { return new Response(JSON.stringify(body), { status, headers: corsHeaders }); }
function text(v: unknown): string { return typeof v === "string" ? v.trim() : ""; }
function validUid(v: unknown): v is string { return typeof v === "string" && v.length > 0 && v.length <= 128 && /^[A-Za-z0-9_-]+$/.test(v); }
function validData(v: unknown): Record<string,string> | null {
  if (v == null) return {};
  if (typeof v !== "object" || Array.isArray(v)) return null;
  const entries = Object.entries(v as Record<string,unknown>); if (entries.length > 20) return null;
  const result: Record<string,string> = {};
  for (const [key,value] of entries) { if (!/^[A-Za-z][A-Za-z0-9_]{0,39}$/.test(key) || typeof value !== "string" || value.length > 512) return null; result[key]=value; }
  return result;
}
function decodePrivateKey(pem: string): ArrayBuffer {
  const clean=pem.replace(/-----BEGIN PRIVATE KEY-----/g,"").replace(/-----END PRIVATE KEY-----/g,"").replace(/\\n/g,"\n").replace(/\s/g,"");
  const raw=atob(clean), buffer=new ArrayBuffer(raw.length), bytes=new Uint8Array(buffer); for(let i=0;i<raw.length;i++)bytes[i]=raw.charCodeAt(i); return buffer;
}
function b64url(bytes: Uint8Array): string { let s="";for(const b of bytes)s+=String.fromCharCode(b);return btoa(s).replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/g,""); }
async function googleAccessToken(sa: ServiceAccount): Promise<string> {
  const now=Math.floor(Date.now()/1000), header=b64url(new TextEncoder().encode(JSON.stringify({alg:"RS256",typ:"JWT"}))), claims=b64url(new TextEncoder().encode(JSON.stringify({iss:sa.client_email,scope:GOOGLE_SCOPE,aud:GOOGLE_OAUTH_TOKEN_URL,iat:now,exp:now+3600}))), unsigned=`${header}.${claims}`;
  const key=await crypto.subtle.importKey("pkcs8",decodePrivateKey(sa.private_key),{name:"RSASSA-PKCS1-v1_5",hash:"SHA-256"},false,["sign"]);
  const sig=new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5",key,new TextEncoder().encode(unsigned)));
  const response=await fetch(GOOGLE_OAUTH_TOKEN_URL,{method:"POST",headers:{"content-type":"application/x-www-form-urlencoded"},body:new URLSearchParams({grant_type:"urn:ietf:params:oauth:grant-type:jwt-bearer",assertion:`${unsigned}.${b64url(sig)}`})});
  if(!response.ok)throw new Error(`Google OAuth failed (${response.status})`);const result=await response.json() as {access_token?:string};if(!result.access_token)throw new Error("No Google access token");return result.access_token;
}
async function verifyFirebase(idToken:string,apiKey:string):Promise<Identity|null>{
 const r=await fetch(`${FIREBASE_IDENTITY_LOOKUP_URL}?key=${encodeURIComponent(apiKey)}`,{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({idToken})});if(!r.ok)return null;const j=await r.json() as {users?:Array<{localId?:string;email?:string;disabled?:boolean}>};const u=j.users?.length===1?j.users[0]:undefined;const uid=text(u?.localId),email=text(u?.email).toLowerCase();if(!validUid(uid)||!email||u?.disabled===true)return null;return{uid,email};
}
async function readDevices(url:string,key:string,uid:string):Promise<DeviceRow[]>{
 const q=new URLSearchParams({select:"uid,fcm_token,platform,token_hash",uid:`eq.${uid}`,app_id:`eq.${FLUTTER_FCM_APP_ID}`});const r=await fetch(`${url.replace(/\/$/,"")}/rest/v1/fcm_device_tokens?${q}`,{headers:{apikey:key,authorization:`Bearer ${key}`,accept:"application/json"}});if(!r.ok)throw new Error(`Private token registry read failed (${r.status})`);const rows=await r.json() as DeviceRow[];return rows.filter(row=>isValidDevice({uid:row.uid,appId:FLUTTER_FCM_APP_ID,platform:row.platform,token:row.fcm_token,tokenHash:row.token_hash}));
}
async function removeStale(url:string,key:string,row:DeviceRow):Promise<void>{
 const q=new URLSearchParams({uid:`eq.${row.uid}`,app_id:`eq.${FLUTTER_FCM_APP_ID}`,platform:`eq.${row.platform}`,token_hash:`eq.${row.token_hash}`});const r=await fetch(`${url.replace(/\/$/,"")}/rest/v1/fcm_device_tokens?${q}`,{method:"DELETE",headers:{apikey:key,authorization:`Bearer ${key}`}});if(!r.ok)console.warn("Could not remove stale FCM token",{platform:row.platform,status:r.status});
}
async function send(token:string,platform:"android"|"ios",title:string,body:string,data:Record<string,string>,accessToken:string):Promise<Response>{
 return await fetch(`https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`,{method:"POST",headers:{authorization:`Bearer ${accessToken}`,"content-type":"application/json"},body:JSON.stringify({message:{token,notification:{title,body},data,...(platform==="android"?{android:{priority:"HIGH"}}:{apns:{headers:{"apns-priority":"10"},payload:{aps:{sound:"default"}}})}})});
}
Deno.serve(async request=>{
 if(request.method==="OPTIONS")return new Response("ok",{headers:corsHeaders});if(request.method!=="POST")return jsonResponse({error:"Method not allowed"},405);
 const idToken=/^Bearer\s+(\S+)$/i.exec(request.headers.get("authorization")??"")?.[1]??"";if(!idToken||idToken.length>MAX_ID_TOKEN_LENGTH)return jsonResponse({error:"Firebase authentication required"},401);
 const apiKey=Deno.env.get("FIREBASE_WEB_API_KEY"),saJson=Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON"),url=Deno.env.get("SUPABASE_URL"),serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");if(!apiKey||!saJson||!url||!serviceKey)return jsonResponse({error:"Push sender is not configured"},503);
 const identity=await verifyFirebase(idToken,apiKey).catch(()=>null);if(!identity)return jsonResponse({error:"Firebase token verification failed"},401);
 let input:PushInput;try{input=await request.json() as PushInput;}catch{return jsonResponse({error:"Invalid JSON body"},400);}
 const recipientUid=text(input.recipientUid),title=text(input.title),body=text(input.body),data=validData(input.data);
 if(!validUid(recipientUid)||!title||title.length>120||!body||body.length>500||data===null)return jsonResponse({error:"Invalid notification request"},400);
 if(!isAllowedFlutterPushRecipient(identity.uid,recipientUid))return jsonResponse({error:"Only authenticated self-test sends are enabled"},403);
 let sa:ServiceAccount;try{sa=JSON.parse(saJson) as ServiceAccount;}catch{return jsonResponse({error:"Push service credentials are invalid"},503);}if(sa.project_id!==FIREBASE_PROJECT_ID||!sa.client_email||!sa.private_key)return jsonResponse({error:"Push credentials do not match Firebase project"},503);
 try{const [devices,accessToken]=await Promise.all([readDevices(url,serviceKey,recipientUid),googleAccessToken(sa)]);let sent=0;for(const device of devices){const response=await send(device.fcm_token,device.platform,title,body,data,accessToken);if(response.ok){sent++;continue;}const errorBody=await response.json().catch(()=>({})) as {error?:{details?:Array<{errorCode?:string}>}};const codes=errorBody.error?.details?.map(detail=>detail.errorCode)??[];if(response.status===404||codes.includes("UNREGISTERED"))await removeStale(url,serviceKey,device);else console.warn("FCM rejected registered device",{platform:device.platform,status:response.status});}return jsonResponse({accepted:true,sent,deviceCount:devices.length});}catch(error){console.error("Flutter FCM send failed",{message:error instanceof Error?error.message:"Unknown error"});return jsonResponse({error:"Push send failed"},502);}
});

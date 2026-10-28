import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS", "Content-Type": "application/json" };
const reply = (body: unknown, status=200) => new Response(JSON.stringify(body), { status, headers: cors });
const esc = (v: unknown) => String(v ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]!));

Deno.serve(async req => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply({error:"Method not allowed"},405);
  const url=Deno.env.get("SUPABASE_URL")!, anon=Deno.env.get("SUPABASE_ANON_KEY")!, service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const resend=Deno.env.get("RESEND_API_KEY"), from=Deno.env.get("EMAIL_FROM") || Deno.env.get("TRANSFER_EMAIL_FROM"), adminNotify=Deno.env.get("ADMIN_NOTIFY_EMAIL");
  if(!url||!anon||!service||!resend||!from) return reply({error:"Email service is not configured. Set RESEND_API_KEY and TRANSFER_EMAIL_FROM secrets."},503);
  const auth=req.headers.get("Authorization")||""; if(!auth.startsWith("Bearer ")) return reply({error:"Authentication required"},401);
  const userClient=createClient(url,anon,{global:{headers:{Authorization:auth}}});
  const {data:{user},error:userErr}=await userClient.auth.getUser(); if(userErr||!user) return reply({error:"Invalid session"},401);
  const db=createClient(url,service,{auth:{persistSession:false}});
  let body:any; try{body=await req.json()}catch{return reply({error:"Invalid JSON"},400)}
  const action=String(body.action||"");
  const {data:admin}=await db.from("admin_users").select("user_id").eq("user_id",user.id).maybeSingle();
  const adminOnly=["topup_reviewed","wallet_assigned","withdrawal_reviewed","admin_custom_email"];
  if(adminOnly.includes(action)&&!admin) return reply({error:"Administrator access required"},403);
  let to:string|undefined, subject="", textBody="", htmlBody="";
  if(action==="topup_created"){
    const {data:p}=await db.from("profiles").select("email").eq("id",user.id).maybeSingle(); if(!p?.email)return reply({error:"User email not found"},404);
    to=p.email; subject="MicroWallet credit request received"; textBody=`Your ${String(body.assetCode||"asset")} credit request for $${Number(body.usdAmount||0).toFixed(2)} has been received and is pending administrator review.`;
  } else if(action==="topup_reviewed"){
    const {data:r,error}=await db.from("topup_requests").select("id,user_id,asset_code,usd_amount,amount,status,admin_note,asset_quantity").eq("id",body.requestId).maybeSingle(); if(error||!r)return reply({error:"Credit request not found"},404);
    const {data:p}=await db.from("profiles").select("email").eq("id",r.user_id).maybeSingle(); to=p?.email; if(!to)return reply({error:"User email not found"},404);
    subject=`MicroWallet credit request ${r.status}`; textBody=`Your ${r.asset_code} credit request for $${Number(r.usd_amount??r.amount).toFixed(2)} is ${r.status}.${r.admin_note?` Administrator note: ${r.admin_note}`:""}${r.asset_quantity!=null?` Credited quantity: ${r.asset_quantity} ${r.asset_code}.`:""}`;
  } else if(action==="wallet_assigned"){
    const email=String(body.userEmail||"").trim().toLowerCase(); if(!email||email.length>254)return reply({error:"Valid user email required"},400);
    const {data:p}=await db.from("profiles").select("id,email").eq("email",email).maybeSingle(); if(!p)return reply({error:"User not found"},404);
    const {data:w}=await db.from("wallet_addresses").select("asset_code,network,address").eq("user_id",p.id).eq("asset_code",String(body.assetCode||"")).eq("network",String(body.network||"")).maybeSingle(); if(!w)return reply({error:"Registered wallet address not found"},404);
    to=p.email; subject="A wallet address was assigned to your MicroWallet account"; textBody=`A wallet address has been assigned to your account. Asset: ${w.asset_code}; Network: ${w.network}; Address: ${w.address}. Always verify the network before sending funds.`;
  } else if(action==="withdrawal_created"||action==="withdrawal_reviewed"){
    const {data:r,error}=await db.from("withdrawal_requests").select("id,user_id,asset_code,amount,destination_address,status,requested_at,available_after,admin_note,payout_reference").eq("id",body.requestId).maybeSingle(); if(error||!r)return reply({error:"Withdrawal request not found"},404);
    if(action==="withdrawal_created"&&r.user_id!==user.id)return reply({error:"Forbidden"},403);
    const {data:p}=await db.from("profiles").select("email").eq("id",r.user_id).maybeSingle(); if(!p?.email)return reply({error:"User email not found"},404);
    to=p.email; subject=action==="withdrawal_created"?"MicroWallet withdrawal request received":`MicroWallet withdrawal ${r.status}`;
    textBody=action==="withdrawal_created"?`Your withdrawal request has been recorded. Amount: ${r.amount} ${r.asset_code}; destination: ${r.destination_address}; status: ${r.status}; available after: ${r.available_after||"pending"}. This email does not mean a blockchain payment has been sent.`:`Your withdrawal request for ${r.amount} ${r.asset_code} is now ${r.status}.${r.admin_note?` Administrator note: ${r.admin_note}`:""}${r.payout_reference?` Payout reference: ${r.payout_reference}`:""} A status of paid is an administrator record and does not independently verify an on-chain transaction.`;
  } else if(action==="admin_custom_email"){
    if(!admin)return reply({error:"Administrator access required"},403);
    const audience=String(body.audience||"single"), subj=String(body.subject||"").trim(), message=String(body.message||"").trim();
    if(!subj||subj.length>180||!message||message.length>12000)return reply({error:"Subject (1-180 chars) and message (1-12000 chars) are required"},400);
    let recipients:string[]=[];
    if(audience==="single"){
      const email=String(body.recipient||"").trim().toLowerCase();
      if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||email.length>254)return reply({error:"A valid recipient email is required"},400);
      const {data:profile}=await db.from("profiles").select("email").eq("email",email).maybeSingle();
      if(!profile?.email)return reply({error:"No registered user found for that email"},404);
      recipients=[profile.email];
    } else if(audience==="all"){
      const {data:profiles,error}=await db.from("profiles").select("email").not("email","is",null).limit(5000);
      if(error)return reply({error:"Could not load user recipients"},500);
      recipients=[...new Set((profiles||[]).map((x:any)=>String(x.email||"").trim()).filter((x:string)=>/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(x)))];
      if(!recipients.length)return reply({error:"No registered user emails found"},404);
    } else return reply({error:"Invalid audience"},400);
    let sentCount=0,failedCount=0;
    for(let i=0;i<recipients.length;i+=10){
      const batch=recipients.slice(i,i+10);
      const results=await Promise.all(batch.map(async recipient=>{
        const h=`<div style="font-family:Arial,sans-serif;max-width:600px;margin:auto;padding:24px;color:#17243a"><img src="https://microwallet-repaired-20261025.nabisanadgoal0311.workers.dev/microwallet-logo.png" alt="MicroWallet" style="width:150px;max-height:100px;object-fit:contain"><h2>${esc(subj)}</h2><div style="white-space:pre-wrap;line-height:1.6">${esc(message)}</div><p style="font-size:12px;color:#718096">MicroWallet account notification.</p></div>`;
        const response=await fetch("https://api.resend.com/emails",{method:"POST",headers:{Authorization:`Bearer ${resend}`,"Content-Type":"application/json"},body:JSON.stringify({from,to:[recipient],subject:subj,text:message,html:h})});
        return response.ok;
      }));
      sentCount+=results.filter(Boolean).length;failedCount+=results.filter(x=>!x).length;
    }
    return reply({ok:failedCount===0,sent:sentCount,failed:failedCount,message:`Accepted ${sentCount}; failed ${failedCount}`});
  } else return reply({error:"Unsupported notification action"},400);
  const html=`<div style="font-family:Arial,sans-serif;max-width:600px;margin:auto;padding:24px;color:#17243a"><img src="https://microwallet-repaired-20261025.nabisanadgoal0311.workers.dev/microwallet-logo.png" alt="MicroWallet" style="width:150px;max-height:100px;object-fit:contain"><h2>MicroWallet notification</h2><p>${esc(textBody)}</p><p style="font-size:12px;color:#718096">MicroWallet account notification. Do not reply with passwords or verification codes.</p></div>`;
  const send=async(recipient:string,subj:string,txt:string,htmlText:string)=>fetch("https://api.resend.com/emails",{method:"POST",headers:{Authorization:`Bearer ${resend}`,"Content-Type":"application/json"},body:JSON.stringify({from,to:[recipient],subject:subj,text:txt,html:htmlText})});
  const sent=await send(to,subject,textBody,html); if(!sent.ok){const err=await sent.text();console.error("Resend failed",sent.status,err);return reply({error:"Email provider rejected the message. Check sender verification and Resend logs."},502);}
  if(action==="withdrawal_created"&&adminNotify){const adminText=`New withdrawal request ${body.requestId} from ${to}. Review it in MicroWallet admin. Amount and address are available in the admin panel.`;const adminHtml=`<p>${esc(adminText)}</p>`;const adminSent=await send(adminNotify,"MicroWallet: new withdrawal request",adminText,adminHtml);if(!adminSent.ok)console.error("Admin notification failed",await adminSent.text());}
  return reply({ok:true,message:"Email sent"});
});

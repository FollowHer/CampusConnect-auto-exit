const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const path=require('node:path');
const {pathToFileURL}=require('node:url');
const fs=require('node:fs/promises');

(async()=>{
 const browser=await chromium.launch(process.env.CAMPUS_CHROME_PATH ? {executablePath:process.env.CAMPUS_CHROME_PATH,headless:true} : {headless:true});
 try {
  const page=await browser.newPage({viewport:{width:1060,height:760}});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.addInitScript(()=>{window.commands=[];window.chrome={webview:{postMessage:m=>commands.push(m),addEventListener:()=>{}}};});
  await page.goto(pathToFileURL(path.resolve(__dirname,'../source/Desktop.html')).href);
  const result=await page.evaluate(async()=>{
   const assert=(condition,label)=>{if(!condition)throw Error(label);};
   const nextFrame=()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
   const state={target:'HNPI-STU',currentSsid:'HNPI-STU',campusConnected:true,connectionTitle:'已连接',automatic:false,busy:false,diagnosing:false,permissionNeeded:false,lastScan:'12:30',status:'就绪',portalStatus:'认证状态',portalAddress:'',report:'诊断结果',
    networks:Array.from({length:40},(_,i)=>({ssid:i===0?'HNPI-STU':'Network '+i,signal:100-i,secure:false})),
    logs:Array.from({length:120},(_,i)=>({time:'12:30:01',text:'Log '+i}))};
   const update=s=>campus.receive({kind:'state',state:s});
   const go=name=>document.querySelector('[data-page="'+name+'"]').click();
   update(state);
   const firstNetwork=document.querySelector('.network-row');
   update({...state,busy:true,status:'正在扫描'});
   assert(document.querySelector('.network-row')===firstNetwork,'unchanged networks were rebuilt');
   assert(document.querySelector('.network-row button').disabled,'busy flag was not updated');
   update(state);
   assert(!document.querySelector('.network-row button').disabled,'button did not recover after scan');
   go('settings');
   document.getElementById('username').value='unsaved-draft';
   await nextFrame();commands.length=0;
   const counts={networks:0};
   const observer=new MutationObserver(records=>{
    for(const r of records){if(r.target.id==='networks')counts.networks++;}
   });
   observer.observe(document.getElementById('networks'),{childList:true});
   const begin=performance.now();
   for(let i=0;i<200;i++)update({...state,busy:i%2===0,status:'状态 '+i,networks:state.networks.map(n=>({...n,signal:i%100})),logs:[{time:'12:31',text:'最新记录 '+i},...state.logs.slice(0,119)],report:'最新报告 '+i});
   const updatesMs=performance.now()-begin;
   await nextFrame();observer.disconnect();
   assert(counts.networks===0,'hidden pages rebuilt during state updates');
   assert(!commands.some(m=>m.command==='portalBounds'),'non-portal page posted browser bounds');
   assert(document.getElementById('username').value==='unsaved-draft','unsaved settings lost');
   go('dashboard');assert(document.querySelector('.network-subtitle').textContent.includes('99%'),'deferred networks are stale');
   go('portal');await nextFrame();
   commands.length=0;for(let i=0;i<20;i++)update({...state,status:'认证 '+i});
   await nextFrame();
   assert(commands.filter(m=>m.command==='portalBounds').length===0,'unchanged portal bounds were sent repeatedly');
   const oldWidth=document.getElementById('portal-slot').getBoundingClientRect().width;
   commands.length=0;
   return {updatesMs:Number(updatesMs.toFixed(2)),hiddenPageRebuilds:counts,boundsRequestsForUnchangedState:commands.filter(m=>m.command==='portalBounds').length,oldWidth};
  });
  await page.setViewportSize({width:980,height:700});
  await page.waitForFunction(()=>commands.some(m=>m.command==='portalBounds'&&m.width>0));
  const width=await page.locator('#portal-slot').evaluate(e=>e.getBoundingClientRect().width);
  assert(width<result.oldWidth);
  assert.deepEqual(errors,[]);
  console.log('PASS: unchanged nodes preserved, busy controls updated, hidden pages deferred, latest data shown on navigation, draft retained, portal bounds coalesced and resize handled.');
  console.log(JSON.stringify(result));
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});

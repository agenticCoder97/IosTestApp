// Source-scoped DOM extraction in WKWebView. JSON is parsed as data, never evaluated.
const failure = error => JSON.stringify({error});
const controller = new AbortController();
globalThis.__astralComicImportAbort = controller;
function challenge(doc) { return doc.querySelector('#challenge-form,#cf-challenge-running') || /just a moment|attention required|verify you are human/i.test(doc.title); }
async function getPage(url) {
    if (url.origin !== location.origin) throw Error('Open the source page in Add before importing.');
    if (url.pathname.replace(/\/$/,'') === location.pathname.replace(/\/$/,'')) return document;
    const timer = setTimeout(()=>controller.abort(),45000);
    try {
        const r = await fetch(url.href,{credentials:'same-origin',signal:controller.signal});
        if(r.status===429) throw Error('The source is limiting requests. Wait before retrying.');
        if(r.status===403 || r.headers.get('cf-mitigated')==='challenge') throw Error('Open this source in Add and complete its browser verification, then retry.');
        if(!r.ok) throw Error(`The source returned HTTP ${r.status}. Your saved copy was retained.`);
        if(new URL(r.url).origin!==location.origin) throw Error('The source moved. Open its current page in Add.');
        return new DOMParser().parseFromString(await r.text(),'text/html');
    } finally {clearTimeout(timer);}
}
const safe = value => {try {const u=new URL(String(value).trim(),targetURL);return u.protocol==='https:'?u.href:null;}catch{return null;}};
function objectAt(script, marker) {
    const start=script.indexOf(marker); if(start<0)return null;
    let begin=script.indexOf('{',start+marker.length), depth=0, quoted=false, escape=false;
    if(begin<0)return null;
    for(let i=begin;i<script.length;i++) {const c=script[i];if(quoted){if(escape)escape=false;else if(c==='\\')escape=true;else if(c==='"')quoted=false;}else if(c==='"')quoted=true;else if(c==='{')depth++;else if(c==='}'&&--depth===0){try{return JSON.parse(script.slice(begin,i+1));}catch{return null;}}}
    return null;
}
try {
 const url=new URL(targetURL); const doc=await getPage(url);
 if(challenge(doc)) throw Error('Open this source in Add and complete its browser verification, then retry.');
 const text=q=>doc.querySelector(q)?.textContent.trim()||'';
 let gallery=null;
 if(sourceKey==='nhentai') {
   for(const node of doc.querySelectorAll('script')) {const m=node.textContent.match(/window\._gallery\s*=\s*JSON\.parse\(("(?:[^"\\]|\\.)*")\)/);if(m){gallery=JSON.parse(JSON.parse(m[1]));break;}gallery=objectAt(node.textContent,'window._gallery =')||gallery;}
   if(!gallery?.media_id || !gallery.images?.pages?.length) throw Error('Gallery data was not found. Open an accessible gallery page in Add.');
 }
 function images() {
   if(gallery) {const ext={j:'jpg',p:'png',g:'gif',w:'webp'};return gallery.images.pages.map((p,i)=>`https://i1.nhentai.net/galleries/${gallery.media_id}/${i+1}.${ext[p.t]||'jpg'}`);}
   for(const script of doc.querySelectorAll('script')) {const data=objectAt(script.textContent,'ts_reader.run(');const urls=data?.sources?.find(s=>s.images?.length)?.images?.map(safe).filter(Boolean);if(urls?.length)return urls;}
   return [...doc.querySelectorAll('.reading-content img,.page-break img,#readerarea img')].map(n=>safe(n.getAttribute('data-src')||n.getAttribute('data-lazy-src')||n.getAttribute('data-original')||n.getAttribute('src'))).filter(Boolean);
 }
 if(mode==='pages') {const pages=images();if(!pages.length)throw Error('No chapter images were found. Open this chapter in Add, then retry.');return JSON.stringify({pages});}
 if(gallery) {
   const pages=images();const tags=gallery.tags||[];
   return JSON.stringify({work:{title:gallery.title.english||gallery.title.pretty||gallery.title.japanese,description:'',authors:tags.filter(t=>t.type==='artist').map(t=>t.name),tags:tags.map(t=>({name:t.name,tag_type:t.type})),cover:`https://t.nhentai.net/galleries/${gallery.media_id}/cover.${({j:'jpg',p:'png',g:'gif',w:'webp'})[gallery.images.cover?.t]||'jpg'}`,chapters:[{url:url.href,number:1,title:'Gallery',pages}]}});
 }
 let anchors=[...doc.querySelectorAll('.wp-manga-chapter a[href],a[href*="-chapter-"]')];
 if(!anchors.length && sourceKey==='toongod') {
   const ajax=new URL(url.href.replace(/\/$/,'')+'/ajax/chapters/');
   const timer=setTimeout(()=>controller.abort(),30000);
   try {const r=await fetch(ajax,{method:'POST',credentials:'same-origin',signal:controller.signal});if(r.status===429)throw Error('The source is limiting requests.');if(r.ok)anchors=[...new DOMParser().parseFromString(await r.text(),'text/html').querySelectorAll('.wp-manga-chapter a[href]')];}finally{clearTimeout(timer);}
 }
 const slug=url.pathname.split('/').filter(Boolean)[1]; const seen=new Set();const chapters=[];
 for(const a of anchors){const href=safe(a.getAttribute('href'));if(!href||seen.has(href))continue;const u=new URL(href);if(u.origin!==url.origin||href.includes('{{'))continue;
   if(sourceKey==='hentai20' && !u.pathname.startsWith('/'+slug+'-chapter-'))continue;
   if(sourceKey==='toongod' && !u.pathname.startsWith(url.pathname.replace(/\/$/,'')+'/'))continue;
   const label=a.textContent.replace(/\s+/g,' ').trim();const match=label.match(/(?:Chapter|Ch\.?)\s*(\d+(?:\.\d+)?)/i)||u.pathname.match(/chapter[-/](\d+(?:\.\d+)?)/i);if(!match)continue;
   seen.add(href);chapters.push({url:href,number:Number(match[1]),title:label||`Chapter ${match[1]}`,pages:[]});}
 chapters.sort((a,b)=>a.number-b.number);
 const title=text('.post-title h1,h1.entry-title,h1');
 if(!title||!chapters.length)throw Error('The series title or chapter list was not found. Open the series page in Add and wait for its chapter list to load.');
 const cover=safe(doc.querySelector('meta[property="og:image"]')?.content||doc.querySelector('.summary_image img')?.getAttribute('data-src')||doc.querySelector('.summary_image img')?.getAttribute('src'));
 return JSON.stringify({work:{title,description:text('.summary__content,.description,.entry-content > p'),authors:[...doc.querySelectorAll('.author-content a,i[itemprop="name"]')].map(n=>n.textContent.trim()),tags:[...doc.querySelectorAll('.genres-content a,a[rel="tag"]')].map(n=>({name:n.textContent.trim(),tag_type:'genre'})),cover,chapters}});
} catch(error) {return failure(controller.signal.aborted?'Import cancelled or timed out. Your saved copy was retained.':error.message);}
finally {globalThis.__astralComicImportAbort=null;}

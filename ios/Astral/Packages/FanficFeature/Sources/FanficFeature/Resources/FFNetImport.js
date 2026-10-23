// Extract one fully parsed chapter; Swift paces navigation in a hidden page that shares the browser session.
const fail = error => JSON.stringify({error});
const id = new URL(workURL).pathname.match(/^\/s\/(\d+)/)?.[1];
if (!id || !/(^|\.)fanfiction\.net$/.test(location.hostname) || location.pathname.match(/^\/s\/(\d+)/)?.[1] !== id) return fail('wrongPage');
if (document.querySelector('#challenge-form, #cf-challenge-running') || /just a moment|verify you are human|attention required/i.test(document.title)) return fail('verification');
const body = document.querySelector('#storytext,#storycontent,.storycontent,#story_content');
if (!body) return fail('incomplete');
const current = Number(location.pathname.split('/')[3] || 1);
const profile = document.querySelector('#profile_top');
const title = profile?.querySelector('b.xcontrast_txt,b')?.textContent.trim() || document.querySelector('b.xcontrast_txt,b')?.textContent.trim() || (typeof fallbackTitle !== 'undefined' ? fallbackTitle : '');
if (!title) return fail('invalidWork');
function chapterNumber(value) {
    if (/^\d+$/.test(value.trim())) return Number(value);
    try { const url = new URL(value, location.href); if (!/(^|\.)fanfiction\.net$/.test(url.hostname)) return 0; return url.pathname.match(new RegExp(`^/s/${id}/(\\d+)(?:/|$)`)) ? Number(url.pathname.split('/')[3]) : 0; } catch { return 0; }
}
const selects = [...document.querySelectorAll('select')];
const select = selects.find(s => s.id === 'chap_select' || /chap/i.test(s.name || s.id)) || selects.find(s => [...s.options].filter(o => /^(?:Chapter\s*)?\d+[.: ]/i.test(o.textContent.trim())).length > 1);
const options = [...(select?.options || [])];
const optionNumbers = options.map(o => chapterNumber(o.value) || Number(o.textContent.trim().match(/^(?:Chapter\s*)?(\d+)/i)?.[1]) || 0);
const text = document.body.textContent;
const stated = Number(text.match(/Chapters:\s*([\d,]+)/i)?.[1]?.replace(/,/g,'')) || Number(text.match(/(?:Chapter|Ch)\s+\d+\s*(?:of|\/)\s*(\d+)/i)?.[1]) || 0;
const destinations = [...document.querySelectorAll('a[href],button[onclick],input[onclick]')].flatMap(node => {
    const href = node.getAttribute('href');
    const onclick = node.getAttribute('onclick') || '';
    return [href ? chapterNumber(href) : 0, ...[...onclick.matchAll(new RegExp(`/s/${id}/(\\d+)(?:/|["'])`, 'g'))].map(m => Number(m[1]))];
}).filter(n => n > 0);
const nextChapter = destinations.includes(current + 1) ? current + 1 : null;
const lastLink = [...document.querySelectorAll('a[href]')].find(a => /\blast\b/i.test(a.textContent) && chapterNumber(a.getAttribute('href')) > current);
let count = Math.max(stated, ...optionNumbers, lastLink ? chapterNumber(lastLink.getAttribute('href')) : 0);
if (!count && typeof expectedCount !== 'undefined' && expectedCount > 0) count = expectedCount;
// A desktop one-shot has a real metadata block and no chapter navigation. A mobile
// layout without that evidence must supply a Next chain or fail, never default to one.
if (!count && !nextChapter && !(current === 1 && profile?.querySelector('a[href^="/u/"]') && /Words:\s*[\d,]+/i.test(profile.textContent) && destinations.every(n => n === 1))) {
    if (current === 1) return fail('chapterList');
} else if (!count && !nextChapter && current === 1) count = 1;
if (count > 2000 || current > 2000) return fail('tooLarge');
if (count && (count < current || (nextChapter && nextChapter > count))) return fail('incomplete');
const copy = body.cloneNode(true);
copy.querySelectorAll('script,style').forEach(n => n.remove());
// Private-use marks carry italics, bold and centring to the reader (FanficTextMarks).
copy.querySelectorAll('em,i,cite').forEach(n => { n.prepend('\uE000'); n.append('\uE001'); });
copy.querySelectorAll('strong,b').forEach(n => { n.prepend('\uE002'); n.append('\uE003'); });
copy.querySelectorAll('p,h1,h2,h3,h4,h5,h6').forEach(n => { if (n.closest('[align="center" i],[style*="text-align: center" i],[style*="text-align:center" i],center')) n.prepend('\uE004'); });
copy.querySelectorAll('li').forEach(n => n.prepend('• '));
copy.querySelectorAll('br').forEach(n => n.replaceWith('\n'));
copy.querySelectorAll('hr').forEach(n => n.replaceWith('\n\n***\n\n'));
copy.querySelectorAll('p,div,blockquote,li,pre').forEach(n => n.append('\n\n'));
const content = copy.textContent.replace(/\u00a0/g,' ').replace(/[ \t]+\n/g,'\n').replace(/\n{3,}/g,'\n\n').trim();
if (!content) return fail('incomplete');
const stats = profile?.querySelector('.xgray')?.textContent || text;
const value = name => Number(stats.match(new RegExp(name + ':\\s*([\\d,]+)', 'i'))?.[1]?.replace(/,/g,'')) || null;
const date = name => { const stamp = [...(profile || document).querySelectorAll('[data-xutime]')].find(n => n.previousSibling?.textContent?.includes(name))?.getAttribute('data-xutime'); return stamp ? new Date(Number(stamp)*1000).toISOString().slice(0,10) : ''; };
const cover = profile?.querySelector('img.cimage,img[src*="/image/"]') || document.querySelector('img.cimage');
let thumbnailURL = null;
try { if (!cover) throw Error('noCover'); const url = new URL(cover.getAttribute('data-original') || cover.getAttribute('src'), location.href); if (url.protocol === 'https:' && /(^|\.)fanfiction\.net$/.test(url.hostname)) thumbnailURL = url.href; } catch {}
const selected = options.find((o,i) => optionNumbers[i] === current);
// Mobile pages omit #pre_story_links but keep the source category breadcrumb.
const mobileFandoms = [...document.querySelectorAll('a[href]')].filter(a => {
    try {
        const url = new URL(a.getAttribute('href'), location.href);
        return /(^|\.)fanfiction\.net$/.test(url.hostname) && /^\/(?:anime|book|cartoon|comic|game|misc|movie|play|tv)\/[^/]+\/?$/i.test(url.pathname);
    } catch { return false; }
}).map(a => a.textContent.trim()).filter(Boolean);
const fandom = document.querySelector('#pre_story_links a:last-of-type')?.textContent.trim() || [...new Set(mobileFandoms)].join(', ');
return JSON.stringify({expectedChapters:count,nextChapter,work:{title,authors:[...(profile || document).querySelectorAll('a[href^="/u/"]')].map(n=>n.textContent.trim()),summary:profile?.querySelector('div.xcontrast_txt')?.textContent.trim() || '',fandom,rating:stats.match(/Rated:\s*(?:Fiction\s*)?([A-Z+]+)/i)?.[1] || 'NR',characters:'',pairing:'',warnings:'',freeformTags:'',wordCount:value('Words'),complete:/Status:\s*Complete/i.test(stats),publishedAt:date('Published'),updatedAt:date('Updated'),hits:null,kudos:null,commentsCount:value('Reviews'),bookmarksCount:value('Favs'),thumbnailURL,chapters:[{sourceID:`${id}:${current}`,number:current,title:selected?.textContent.trim().replace(/^\d+[.:]\s*/, '') || `Chapter ${current}`,content}]}});

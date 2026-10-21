// Runs in the user's FFNet browser session. No proxy, archive service or server worker.
const fail = error => JSON.stringify({error});
const id = new URL(workURL).pathname.match(/^\/s\/(\d+)/)?.[1];
if (!id || !/(^|\.)fanfiction\.net$/.test(location.hostname) || location.pathname.match(/^\/s\/(\d+)/)?.[1] !== id) return fail('wrongPage');
const controller = new AbortController();
globalThis.__astralAO3ImportAbort = controller;
function checked(page) {
    if (page.querySelector('#challenge-form, #cf-challenge-running') || /just a moment|verify you are human|attention required/i.test(page.title)) throw Error('verification');
    if (!page.querySelector('#storytext,#storycontent,.storycontent,#story_content')) throw Error('incomplete');
    return page;
}
async function chapterPage(number) {
    if (Number(location.pathname.split('/')[3] || 1) === number) return checked(document);
    await new Promise(resolve => setTimeout(resolve, 1000));
    const timer = setTimeout(() => controller.abort(), 45000);
    try {
        const response = await fetch(new URL(`/s/${id}/${number}/`, location.origin), {credentials:'same-origin', signal:controller.signal});
        if (response.status === 429) throw Error('rateLimited');
        if (response.status === 403 || response.headers.get('cf-mitigated') === 'challenge') throw Error('verification');
        if (response.status === 404) throw Error('notFound');
        if (!response.ok) throw Error('unavailable');
        const url = new URL(response.url);
        if (url.origin !== location.origin || url.pathname.match(/^\/s\/(\d+)/)?.[1] !== id || Number(url.pathname.split('/')[3]) !== number) throw Error('incomplete');
        return checked(new DOMParser().parseFromString(await response.text(), 'text/html'));
    } finally { clearTimeout(timer); }
}
function bodyText(root) {
    const copy = root.cloneNode(true);
    copy.querySelectorAll('script,style').forEach(n=>n.remove());
    copy.querySelectorAll('br').forEach(n=>n.replaceWith('\n'));
    copy.querySelectorAll('hr').forEach(n=>n.replaceWith('\n\n***\n\n'));
    copy.querySelectorAll('p,div,blockquote,li,pre').forEach(n=>n.append('\n\n'));
    return copy.textContent.replace(/\u00a0/g,' ').replace(/[ \t]+\n/g,'\n').replace(/\n{3,}/g,'\n\n').trim();
}
try {
    const currentNumber = Number(location.pathname.split('/')[3] || 1);
    const first = typeof singleChapter !== 'undefined' && singleChapter ? checked(document) : await chapterPage(1);
    const profile = first.querySelector('#profile_top') || first.body;
    const title = profile?.querySelector('b.xcontrast_txt, b')?.textContent.trim() || (typeof fallbackTitle !== 'undefined' ? fallbackTitle : '');
    if (!title) return fail('invalidWork');
    const select = first.querySelector('#chap_select') || [...first.querySelectorAll('select')].find(s=>[...s.options].some(o=>/^(?:Chapter\s*)?\d+[.: ]/i.test(o.textContent.trim())));
    const options = [...(select?.querySelectorAll('option') || [])];
    const count = options.length || Number(first.body.textContent.match(/Chapters:\s*(\d+)/i)?.[1]) || (typeof expectedCount !== 'undefined' ? expectedCount : 0) || 1;
    if (count > 2000) return fail('tooLarge');
    const chapters = []; let bytes = 0;
    const start = typeof singleChapter !== 'undefined' && singleChapter ? currentNumber : 1;
    const end = typeof singleChapter !== 'undefined' && singleChapter ? currentNumber : count;
    for (let n=start; n<=end; n++) {
        if (controller.signal.aborted) throw Error('cancelled');
        const page = n === start ? first : await chapterPage(n);
        const content = bodyText(page.querySelector('#storytext,#storycontent,.storycontent,#story_content'));
        if (!content) throw Error('incomplete');
        bytes += new TextEncoder().encode(content).length;
        if (bytes > 50*1024*1024) throw Error('tooLarge');
        chapters.push({sourceID:`${id}:${n}`,number:n,title:options[n-1]?.textContent.trim().replace(/^\d+[.:]\s*/, '') || `Chapter ${n}`,content});
    }
    const stats = profile.querySelector('.xgray')?.textContent || '';
    const value = name => Number(stats.match(new RegExp(name + ':\\s*([\\d,]+)', 'i'))?.[1]?.replace(/,/g,'')) || null;
    const date = name => { const stamp = [...profile.querySelectorAll('[data-xutime]')].find(n=>n.previousSibling?.textContent?.includes(name))?.getAttribute('data-xutime'); return stamp ? new Date(Number(stamp)*1000).toISOString().slice(0,10) : ''; };
    return JSON.stringify({expectedChapters:count,work:{title,authors:[...profile.querySelectorAll('a[href^="/u/"]')].map(n=>n.textContent.trim()),summary:profile.querySelector('div.xcontrast_txt')?.textContent.trim() || '',fandom:first.querySelector('#pre_story_links')?.textContent.trim() || '',rating:stats.match(/Rated:\s*(?:Fiction\s*)?([A-Z+]+)/i)?.[1] || 'NR',characters:'',pairing:'',warnings:'',freeformTags:'',wordCount:value('Words'),complete:/Status:\s*Complete/i.test(stats),publishedAt:date('Published'),updatedAt:date('Updated'),hits:null,kudos:null,commentsCount:value('Reviews'),bookmarksCount:value('Favs'),chapters}});
} catch (error) {
    return fail(controller.signal.aborted ? 'timeout' : error.message || 'network');
} finally { globalThis.__astralAO3ImportAbort = null; }

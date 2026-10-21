// Executed inside WKWebView so requests keep the user's AO3 browser session.
// workURL is supplied as a WebKit argument, never interpolated into JavaScript.
const fail = (error) => JSON.stringify({ error });
const requested = new URL(workURL);
if (location.origin !== requested.origin) return fail("wrongPage");

let page = document;
const currentWork = location.pathname.match(/^\/works\/(\d+)(?:\/|$)/)?.[1];
const requestedWork = requested.pathname.split("/")[2];
const postedHere = parseInt(document.querySelector("dd.chapters")?.textContent, 10);
const fullWorkIsOpen = currentWork === requestedWork &&
    (new URL(location.href).searchParams.get("view_full_work") === "true" || postedHere === 1);

if (!fullWorkIsOpen) {
    const controller = new AbortController();
    globalThis.__astralAO3ImportAbort = controller;
    const timeout = setTimeout(() => controller.abort(), 45000);
    try {
        const response = await fetch(requested.href, {
            credentials: "same-origin", signal: controller.signal
        });
        if (response.status === 429) return fail("rateLimited");
        if (response.status === 403 || response.headers.get("cf-mitigated") === "challenge") {
            return fail("verification");
        }
        if (response.status === 404) return fail("notFound");
        if (!response.ok) return fail("unavailable");
        if (new URL(response.url).origin !== requested.origin) return fail("wrongPage");
        if (new URL(response.url).pathname.startsWith("/users/login")) return fail("login");
        page = new DOMParser().parseFromString(await response.text(), "text/html");
    } catch (error) {
        return fail(error.name === "AbortError" ? "timeout" : "network");
    } finally {
        clearTimeout(timeout);
        globalThis.__astralAO3ImportAbort = null;
    }
}

const text = (selector, root = page) => root.querySelector(selector)?.textContent.trim() || "";
const tags = (selector) => Array.from(page.querySelectorAll(selector), node => node.textContent.trim());
const number = (selector) => {
    const value = text(selector).replace(/,/g, "");
    return /^\d+$/.test(value) ? Number(value) : null;
};
const chapterStats = text("dd.chapters").split("/");
const posted = parseInt(chapterStats[0], 10);
const expected = parseInt(chapterStats[1], 10);
const title = text("h2.title.heading");
if (!title || !page.querySelector("#chapters")) {
    if (page.querySelector("#challenge-form, #cf-challenge-running") || /just a moment|verify you are human/i.test(page.title)) {
        return fail("verification");
    }
    if (page.querySelector("form#new_user") || /log in|registered users/i.test(page.querySelector(".flash, .notice")?.textContent || "")) {
        return fail("login");
    }
    return fail("invalidWork");
}

function bodyText(element) {
    const copy = element.cloneNode(true);
    copy.querySelectorAll("h3.landmark, script, style, .end-notes").forEach(node => node.remove());
    copy.querySelectorAll("br").forEach(node => node.replaceWith("\n"));
    copy.querySelectorAll("hr").forEach(node => node.replaceWith("\n\n***\n\n"));
    copy.querySelectorAll("p, div, blockquote, li, h1, h2, h3, h4, h5, h6, pre").forEach(node => node.append("\n\n"));
    return copy.textContent.replace(/\u00a0/g, " ").replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
}

const containers = Array.from(page.querySelectorAll("#chapters > div.chapter"));
const roots = containers.length ? containers : [page.querySelector("#chapters")];
const chapters = roots.map((root, index) => {
    const body = root.querySelector("div.userstuff[role='article']");
    return {
        sourceID: root.querySelector("h3.title a[href*='/chapters/']")?.getAttribute("href")?.match(/\/chapters\/(\d+)/)?.[1] || null,
        number: index + 1,
        title: text("h3.title", root).replace(/^\s*Chapter\s+\d+\s*:?\s*/i, "").trim() || `Chapter ${index + 1}`,
        content: body ? bodyText(body) : ""
    };
});
// Never persist an age gate, summary, or a subset of a multi-chapter work.
if (!Number.isInteger(posted) || posted < 1 || chapters.length !== posted || chapters.some(chapter => !chapter.content)) {
    return fail("incomplete");
}

return JSON.stringify({
    work: {
        title,
        authors: tags("h3.byline a[rel='author']"),
        summary: text("#workskin > .preface .summary blockquote"),
        fandom: tags("dd.fandom.tags a").join(", "),
        rating: text("dd.rating.tags a"),
        characters: tags("dd.character.tags a").join(", "),
        pairing: tags("dd.relationship.tags a").join(", "),
        warnings: tags("dd.warning.tags a").join(", "),
        freeformTags: tags("dd.freeform.tags a").join(", "),
        wordCount: number("dd.words"),
        complete: Number.isFinite(expected) && posted === expected,
        publishedAt: text("dd.published"),
        updatedAt: text("dd.status") || text("dd.published"),
        hits: number("dd.hits"), kudos: number("dd.kudos"),
        commentsCount: number("dd.comments"), bookmarksCount: number("dd.bookmarks"),
        chapters
    }
});

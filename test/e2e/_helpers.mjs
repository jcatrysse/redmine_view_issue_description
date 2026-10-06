// Shared by the scenarios of this plugin: REST calls with basic auth (the API
// ignores the browser session), issue ids looked up by subject (they differ
// between a fresh and a reused database), and a page that shows an API answer
// so it can be screenshotted.
export const P = 'e2e-project';
export const PASSWORD = process.env.RMP_USER_PASSWORD || process.env.RMP_ADMIN_PASSWORD || 'Redmine7Test!';

export function auth(login) {
  return { Authorization: 'Basic ' + Buffer.from(`${login}:${PASSWORD}`).toString('base64') };
}

export async function api(t, login, path) {
  const res = await t.page.request.get(t.BASE + path, { headers: auth(login), failOnStatusCode: false });
  const text = await res.text();
  let json = null;
  try { json = JSON.parse(text); } catch { /* xml, csv or an error page */ }
  return { status: res.status(), text, json };
}

const ids = {};
export async function issueId(t, subject) {
  if (!ids[subject]) {
    const { json } = await api(t, 'admin', `/issues.json?status_id=*&limit=100&subject=${encodeURIComponent(subject)}`);
    const issue = json && json.issues.find(i => i.subject === subject);
    if (!issue) throw new Error(`no issue "${subject}"`);
    ids[subject] = issue.id;
  }
  return ids[subject];
}

// Renders an API answer as a page (request, HTTP status, body) for a screenshot.
export async function showApi(t, title, request, status, body) {
  const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
  await t.page.setContent(`<html><body style="font:13px monospace;margin:16px">
    <h3 style="font-family:sans-serif">${esc(title)}</h3>
    <p><b>${esc(request)}</b> &rarr; HTTP ${status}</p>
    <pre style="white-space:pre-wrap;background:#f6f6f6;padding:8px;border:1px solid #ddd">${esc(body)}</pre>
  </body></html>`);
}

// POST/DELETE from the logged-in page, with Redmine's CSRF token.
export async function pageFetch(t, method, path, form = {}) {
  return t.page.evaluate(async ([method, path, form]) => {
    const token = document.querySelector('meta[name=csrf-token]').content;
    const body = new URLSearchParams(form);
    const res = await fetch(path, { method, body, headers: { 'X-CSRF-Token': token, 'X-Requested-With': 'XMLHttpRequest', 'Accept': 'text/javascript' } });
    return res.status;
  }, [method, path, form]);
}

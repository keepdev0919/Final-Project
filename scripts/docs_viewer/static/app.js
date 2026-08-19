/* 놀멍봅서 문서 뷰어 — 화면 동작
 *
 * 문서는 열 때마다 서버에서 새로 받아온다. 브라우저에 캐시해두지 않는다.
 * 이 뷰어의 존재 이유가 "항상 최신"이라, 속도를 위해 그걸 깎지 않는다.
 */

const $sidebar = document.getElementById('sidebar');
const $content = document.getElementById('content');
const $search = document.getElementById('search');
const $theme = document.getElementById('theme-toggle');

let treeData = null;
let currentPath = null;

// ── 마크다운 변환 설정 ──────────────────────────────────────

marked.setOptions({ gfm: true, breaks: false });

function renderMarkdown(md) {
  const html = marked.parse(md);
  const wrap = document.createElement('div');
  wrap.className = 'doc-body';
  wrap.innerHTML = html;

  // 표는 좁은 화면에서 가로로 넘칠 수 있으니 각각 스크롤 상자에 넣는다.
  wrap.querySelectorAll('table').forEach((table) => {
    const box = document.createElement('div');
    box.className = 'table-wrap';
    table.parentNode.insertBefore(box, table);
    box.appendChild(table);
  });

  // 문서끼리 걸린 상대경로 링크(예: docs/기획/…md)를 뷰어 안에서 열리게 바꾼다.
  wrap.querySelectorAll('a[href]').forEach((a) => {
    const href = a.getAttribute('href');
    if (/^(https?:|mailto:|#)/.test(href)) {
      if (href.startsWith('http')) { a.target = '_blank'; a.rel = 'noopener'; }
      return;
    }
    if (href.endsWith('.md')) {
      const target = resolveRelative(href);
      a.setAttribute('href', '#' + encodeURIComponent(target));
    }
  });

  return wrap;
}

/** 문서 안의 상대 링크를 프로젝트 루트 기준 경로로 편다. */
function resolveRelative(href) {
  const clean = href.replace(/^\.\//, '');
  if (!clean.startsWith('../') && currentPath && currentPath.includes('/')) {
    // 같은 폴더 안의 문서를 가리키는 경우
    const dir = currentPath.slice(0, currentPath.lastIndexOf('/'));
    const sameDir = dir + '/' + clean;
    if (treeHas(sameDir)) return sameDir;
  }
  if (treeHas(clean)) return clean;
  // ../ 를 포함한 경우는 브라우저 URL 정규화에 맡긴다.
  try {
    const base = new URL(currentPath || '', 'file:///');
    return decodeURIComponent(new URL(clean, base).pathname.replace(/^\//, ''));
  } catch {
    return clean;
  }
}

function treeHas(path) {
  if (!treeData) return false;
  return treeData.groups.some((g) => g.items.some((i) => i.path === path));
}

// ── 사이드바 ────────────────────────────────────────────────

async function loadTree() {
  const res = await fetch('/api/tree');
  treeData = await res.json();
  renderSidebar();
}

function renderSidebar() {
  $sidebar.textContent = '';

  const groups = [
    { group: '최근 수정', items: treeData.recent, recent: true },
    ...treeData.groups,
  ];

  for (const g of groups) {
    if (!g.items.length) continue;
    const box = document.createElement('div');
    box.className = 'nav-group' + (g.recent ? ' recent' : '');

    const title = document.createElement('div');
    title.className = 'nav-group-title';
    title.textContent = g.group;
    box.appendChild(title);

    for (const item of g.items) {
      const btn = document.createElement('button');
      btn.className = 'nav-item';
      btn.dataset.path = item.path;
      btn.textContent = item.title;
      if (g.recent) {
        const stamp = document.createElement('span');
        stamp.className = 'stamp';
        stamp.textContent = item.mtimeText;
        btn.appendChild(stamp);
      }
      btn.addEventListener('click', () => {
        location.hash = encodeURIComponent(item.path);
      });
      box.appendChild(btn);
    }
    $sidebar.appendChild(box);
  }
  markActive();
}

function markActive() {
  $sidebar.querySelectorAll('.nav-item').forEach((el) => {
    el.classList.toggle('active', el.dataset.path === currentPath);
  });
}

// ── 문서 열기 ───────────────────────────────────────────────

async function openDoc(path) {
  try {
    const res = await fetch('/api/doc?path=' + encodeURIComponent(path));
    if (!res.ok) {
      const err = await res.json().catch(() => ({ error: '알 수 없는 오류' }));
      showError('문서를 열지 못했어요', err.error + '\n' + path);
      return;
    }
    const doc = await res.json();
    currentPath = doc.path;

    $content.textContent = '';

    const head = document.createElement('div');
    head.className = 'doc-head';

    const h1 = document.createElement('h1');
    h1.textContent = doc.title;
    head.appendChild(h1);

    const meta = document.createElement('div');
    meta.className = 'doc-meta';
    meta.appendChild(badge('path', doc.path));
    meta.appendChild(badge('edited', '수정 ' + doc.mtimeText));
    head.appendChild(meta);

    $content.appendChild(head);
    $content.appendChild(renderMarkdown(doc.markdown));

    document.title = doc.title + ' — 놀멍봅서 문서';
    markActive();
    document.querySelector('.main').scrollTop = 0;
  } catch (e) {
    showError('서버에 연결하지 못했어요', String(e));
  }
}

function badge(kind, text) {
  const el = document.createElement('span');
  el.className = 'badge ' + kind;
  el.textContent = text;
  return el;
}

function showHome() {
  currentPath = null;
  document.title = '놀멍봅서 문서';
  $content.textContent = '';

  const head = document.createElement('div');
  head.className = 'doc-head';
  const h1 = document.createElement('h1');
  h1.textContent = '놀멍봅서 문서';
  head.appendChild(h1);
  const meta = document.createElement('div');
  meta.className = 'doc-meta';
  meta.appendChild(badge('count', '문서 ' + (treeData ? treeData.count : 0) + '개'));
  head.appendChild(meta);
  $content.appendChild(head);

  const body = document.createElement('div');
  body.className = 'doc-body';
  const p = document.createElement('p');
  p.textContent = '왼쪽에서 문서를 고르거나, 위 검색창에 두 글자 이상 입력하세요.';
  body.appendChild(p);

  if (treeData && treeData.recent.length) {
    const h2 = document.createElement('h2');
    h2.textContent = '최근 고친 문서';
    body.appendChild(h2);
    const ul = document.createElement('ul');
    for (const item of treeData.recent) {
      const li = document.createElement('li');
      const a = document.createElement('a');
      a.href = '#' + encodeURIComponent(item.path);
      a.textContent = item.title;
      li.appendChild(a);
      li.appendChild(document.createTextNode(' — ' + item.mtimeText));
      ul.appendChild(li);
    }
    body.appendChild(ul);
  }
  $content.appendChild(body);
  markActive();
}

function showError(title, detail) {
  $content.textContent = '';
  const box = document.createElement('div');
  box.className = 'error-box';
  const h2 = document.createElement('h2');
  h2.textContent = title;
  const pre = document.createElement('pre');
  pre.textContent = detail;
  box.appendChild(h2);
  box.appendChild(pre);
  $content.appendChild(box);
}

// ── 검색 ────────────────────────────────────────────────────

let searchTimer = null;

$search.addEventListener('input', () => {
  clearTimeout(searchTimer);
  const q = $search.value.trim();
  if (q.length < 2) {
    if (q.length === 0 && location.hash) { route(); }
    return;
  }
  searchTimer = setTimeout(() => runSearch(q), 180);
});

async function runSearch(q) {
  const res = await fetch('/api/search?q=' + encodeURIComponent(q));
  const { results } = await res.json();

  $content.textContent = '';
  const head = document.createElement('div');
  head.className = 'doc-head';
  const h1 = document.createElement('h1');
  h1.textContent = '검색: ' + q;
  head.appendChild(h1);
  const meta = document.createElement('div');
  meta.className = 'doc-meta';
  meta.appendChild(badge('count', results.length + '개 문서'));
  head.appendChild(meta);
  $content.appendChild(head);

  if (!results.length) {
    const empty = document.createElement('p');
    empty.className = 'empty';
    empty.textContent = '찾은 게 없어요.';
    $content.appendChild(empty);
    return;
  }

  for (const r of results) {
    const btn = document.createElement('button');
    btn.className = 'result';

    const t = document.createElement('span');
    t.className = 'r-title';
    t.textContent = r.title;
    btn.appendChild(t);

    const p = document.createElement('span');
    p.className = 'r-path';
    p.textContent = r.path;
    btn.appendChild(p);

    for (const hit of r.hits) {
      const s = document.createElement('span');
      s.className = 'r-snippet';
      appendHighlighted(s, hit.snippet, q);
      btn.appendChild(s);
    }

    btn.addEventListener('click', () => {
      $search.value = '';
      location.hash = encodeURIComponent(r.path);
    });
    $content.appendChild(btn);
  }
}

/** 검색어에 해당하는 부분만 <mark>로 감싼다. innerHTML을 쓰지 않는다. */
function appendHighlighted(parent, text, q) {
  const low = text.toLowerCase();
  const needle = q.toLowerCase();
  let i = 0;
  while (i < text.length) {
    const at = low.indexOf(needle, i);
    if (at === -1) {
      parent.appendChild(document.createTextNode(text.slice(i)));
      break;
    }
    if (at > i) parent.appendChild(document.createTextNode(text.slice(i, at)));
    const mark = document.createElement('mark');
    mark.textContent = text.slice(at, at + needle.length);
    parent.appendChild(mark);
    i = at + needle.length;
  }
}

// ── 밝게 / 어둡게 ───────────────────────────────────────────

const THEMES = ['시스템', '밝게', '어둡게'];

function applyTheme(name) {
  if (name === '밝게') document.documentElement.setAttribute('data-theme', 'light');
  else if (name === '어둡게') document.documentElement.setAttribute('data-theme', 'dark');
  else document.documentElement.removeAttribute('data-theme');
  $theme.textContent = name;
  localStorage.setItem('docsviewer-theme', name);
}

$theme.addEventListener('click', () => {
  const now = localStorage.getItem('docsviewer-theme') || '시스템';
  applyTheme(THEMES[(THEMES.indexOf(now) + 1) % THEMES.length]);
});

applyTheme(localStorage.getItem('docsviewer-theme') || '시스템');

// ── 라우팅 ──────────────────────────────────────────────────

function route() {
  const hash = location.hash.slice(1);
  if (!hash) { showHome(); return; }
  // #?q=검색어 — 자주 찾는 검색을 즐겨찾기해둘 수 있게.
  if (hash.startsWith('?q=')) {
    const q = decodeURIComponent(hash.slice(3));
    $search.value = q;
    runSearch(q);
    return;
  }
  openDoc(decodeURIComponent(hash));
}

window.addEventListener('hashchange', route);

document.addEventListener('keydown', (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
    e.preventDefault();
    $search.focus();
    $search.select();
  }
  if (e.key === 'Escape' && document.activeElement === $search) {
    $search.value = '';
    $search.blur();
    route();
  }
});

// 문서 목록을 먼저 받아야 상대 링크를 제대로 풀 수 있다.
loadTree().then(route).catch((e) => showError('서버에 연결하지 못했어요', String(e)));

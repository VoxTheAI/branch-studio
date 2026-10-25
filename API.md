# Branch Studio — extension & harness API

One file app, no build step: `index.html` (~2.6 MB, everything inlined). Anything that can run
JavaScript against a page can build on top of it. Four surfaces, pick the one that fits:

| Surface | Use it for |
|---|---|
| `window.BS` | scripting the live app from the console, Playwright, or another page |
| `?ext=file.js` | shipping an extension alongside the app without editing `index.html` |
| localStorage / IndexedDB JSON | reading or writing documents offline, migrations, bulk edits |
| `motion-test.html` + `run-harness.js` | automated regression checks |

Run it: `cd branch-studio && python3 -m http.server 8787` → `http://127.0.0.1:8787/index.html`.
Never serve from the app-bundle copy — the port is part of the origin, so notes "disappear".

---

## 1. `window.BS` — the stable handle

Defined at the end of the main script, right after `init()`. Every entry is a direct alias of the
real function, so `BS.addChild()` is exactly `addChild()` from inside the app.

```js
BS.doc().title                 // active document
BS.tree()[0].children.length  // root-level nodes
BS.runCommand('splitView')     // any command id
BS.forceToast('hello', 1500)   // toast that ignores the feedback toggle
```

**State** — `BS.state` is a live getter (not a copy); mutate then call `saveState()`.

| Group | Keys |
|---|---|
| state & storage | `state`, `STORAGE_KEY`, `IDB_NAME`, `IDB_STORE`, `saveState`, `flushSave`, `adoptState`, `normalizeState`, `setSaveStatus` |
| documents | `doc`, `tree`, `locate`, `uid`, `makeDocument`, `newDocument`, `snapshot`, `openDocuments` |
| node edits | `addNode(parentId)`, `addChild`, `addSibling`, `deleteNode`, `moveVertical(dir)`, `indentNode`, `outdentNode` |
| navigation | `navigate(dir)`, `selectNode(id,{focus})`, `focusNodeEditor(id,atEnd)` |
| rendering | `renderAll`, `renderWorkspace`, `renderVaultRail`, `applySidebar` |
| commands | `runCommand`, `COMMANDS`, `registerCommands`, `cmdItem`, `openPalette`, `openSettings`, `openShortcutSheet` |
| view & theme | `setMode('branch'\|'split'\|'read')`, `zenSet(on)`, `applyAppearance`, `applyThemePreset(id,save)`, `THEME_PRESETS`, `DEFAULT_APPEARANCE` |
| sound | `SOUND`, `DEFAULT_SOUND`, `MOTION`, `motionOn`, `enterEl`, `exitEl` |
| feedback | `toast`, `forceToast`, `toastAction(msg,label,fn,ms)` |
| io | `exportMarkdown`, `exportDiagram`, `exportBackup`, `importBackup`, `openImporter(src)`, `downloadFile` |
| icons | `icon(name,cls)`, `setIcon(el,name,label)`, `BOOTSTRAP_ICONS` |
| onboarding & vaults | `welcomeTree`, `openWelcomeDoc`, `connectFolder` |
| plugin layer | `PX`, `pxDialog`, `askDialog`, `pxSelect`, `pxRerender`, `pxChange`, `pxAllNodes`, `pxTitle`, `pxEsc` |
| chrome | `openMenu`, `closeMenu`, `UI`, `IS_MAC`, `IS_IPAD`, `plainText`, `richToMarkdown` |

Mutation rule of thumb: change the tree, call `BS.saveState()`, then `BS.renderAll()`.
Structural edits already do this internally — and every one pushes an undo snapshot, so "one undo"
reverts a whole paste or import.

### Document shape

```js
{ id:'d…', title, vaultId, folderId, createdAt, updatedAt,
  mode:'branch'|'split'|'read', selectedId, tree:[node…], wordTarget? }
```

### Node shape

```js
{ id:'n…', text:'<rich html or plain text>', children:[node…],
  images:[{name,src}]?, status?:'done'|'draft', refs?:[…] }
```

`text` is rich HTML (bold/lists/headings/`math-field` markup). Convert with `plainText(text)` and
`richToMarkdown(text)`. The welcome doc's content lives in `welcomeTree()`.

---

## 2. `?ext=` — load external code

```
http://127.0.0.1:8787/index.html?ext=my-plugin.js,other.js
```

Scripts load after `init()`, so `window.BS` and the DOM are ready. Relative to the served directory
or absolute URLs. Nothing is requested when the param is absent, which keeps the harness console clean.

```js
// my-plugin.js — a command, a menu entry, a note chip, a status readout
BS.registerCommands({
  wordCount: { label:'Word count', bi:'translation', pc:'Alt+Shift+W', apple:'Ctrl+Meta+W',
               run: () => BS.forceToast(BS.plainText(BS.tree().map(n=>n.text).join(' ')).split(/\s+/).length + ' words', 1600) }
});
BS.PX.topItems.push(() => [
  { icon:'info', label:'My plugin', run: () => BS.pxDialog({title:'Hi', body:'<p>from ext</p>'}) }
]);
```

`registerCommands(defs)` wires everything at once: it adds to `COMMANDS`, maps a Bootstrap icon name
through `BOOTSTRAP_ICONS[id] = bi`, stores the runner in `PX.run[id]`, and registers default
shortcuts for **both** platforms (`pc` and `apple`, falling back to `pc`). New commands never
overwrite a shortcut the user already reassigned.

---

## 3. Commands & keyboard

Every command lives in `BS.COMMANDS` (`{label, icon}`, ~75 after the built-in personas register
theirs). Run any of them with `BS.runCommand(id)`; list them with `Object.keys(BS.COMMANDS)`.
Shortcut tables: `PC_SHORTCUTS` / `APPLE_SHORTCUTS`, current user bindings in `state.shortcuts`.

Key semantics (as declared by the app):

- **`Ctrl` is the literal Control key on every platform** — the app's one super modifier.
- **`Meta` is ⌘ on Apple**, the Windows key elsewhere.
- `Alt` is never paired with a letter (it composes characters on Mac/iPad).
- Defaults are per-platform; `shortcutsVersion` (currently 6) drives migration of stored bindings.

Core commands: `newDocument addTopic addSibling addChild deleteNode moveUp moveDown indent outdent
image math navUp navDown navParent navChild branchView splitView readView undo redo settings
documents exportMd exportDiagram shortcutsHelp copyNote cutNote pasteNote zen palette table`.

App-level chords also exist outside `COMMANDS` (formatting, quick jump, search, focus mode).

---

## 4. Persistence

- **localStorage key**: `branch-studio-v1` → `JSON.stringify(state)`.
- **IndexedDB**: database `branch-studio`, store `kv`, same key (cross-tab sync + fallback).
  Read with `idbGet(STORAGE_KEY)`, write with `saveState()` (250 ms debounce) or `flushSave()` (now).
- Recovery copies are written to `branch-studio-v1-recovery-<ts>` if parsing fails.
- `branch-studio-input-mode` stores pointer/touch/keyboard input mode.
- **Backup format**: `exportBackup()` → `{app:'branch-studio', format:1, exportedAt, state}`.
  Restore with `importBackup()` (merges, re-ids collisions) or feed `normalizeState()` yourself.

Offline writes: set the field on `BS.state`, then `BS.saveState()`.

---

## 5. Theming

`state.appearance` (defaults in `DEFAULT_APPEARANCE`):

```
animations cardRadius uiRadius buttonRadius cardGap columnWidth cardPadding fontSize lineHeight
inactiveOpacity viewerOpacity borderWidth blur readWidth
accent accent2 bg panel text muted line danger
glow fx fxDensity fxSpeed fxParallax fxOpacity fontNote fontChrome theme
```

- `THEME_PRESETS` — 7 presets: `solitude nebula paper terminal solar frost rosewood`.
  `applyThemePreset('terminal')` writes every token (nothing is left half-themed).
- `applyAppearance()` pushes everything to the root as CSS custom properties. The main names are
  `--bg --panel --panel-2 --panel-3 --text --muted --line --accent --accent-2 --accent-soft
  --accent-fg --danger --card-radius --ui-radius --button-radius --card-gap --column-width
  --card-padding --font-size --line-height --border-width --glass-* --sol-* --glow*`.
- **`--tk-*` duplicates** (`--tk-text --tk-muted --tk-line --tk-panel-2 --tk-panel-3
  --tk-accent-soft --tk-danger --tk-card-radius --tk-ui-radius --tk-glass-bar/sheet/tip/card`) exist
  because the glass layer pins a dozen declarations with `!important`; those pins read the parallel
  `--tk-*` names. If you write a theme hook, set both families or the glass layer keeps graphite.
- `state.customCSS` — raw CSS injected into `#custom-style`, persisted, editable in Settings → CSS.
- Particle field: `fx:'off'|'stars'|'dust'|'grid'|'orbs'` plus density/speed/parallax/opacity.

---

## 6. Sound

Synthesised — no assets. `SOUND` methods map 1:1 to classes:

```
typing deletion creation movement remove select drop tab open success error notify menu close toggle click
```

- Master switch is `SOUND.s.enabled` (**not** `SOUND.enabled`), per-class gates are
  `state.sound.<class>`, volume `state.sound.volume`, kit `state.sound.theme`.
- Every method is safe to call before an AudioContext exists (context is created on first user
  gesture); calls are throttled by `SOUND_*_GAP` constants so a run of keys never machine-guns.
- Two classes are deliberately distinct from typing: `deletion` (backspace within a word) and
  `remove` (a note is destroyed). Never make two classes share a cue.
- A theme re-tunes the event kits only (`SOUND_THEMES`).

---

## 7. Menus, dialogs, toasts

```js
BS.openMenu(anchorEl, [
  {icon:'file', label:'Open', hint:'⌘O', run:()=>{}},
  {sep:1},
  {icon:'trash', label:'Delete', danger:true, run:()=>{}}
], {title:'Vaults'});

const name = await BS.askDialog('Rename', {value:'Draft', label:'Title', ok:'Rename'});
const dl   = BS.pxDialog({title:'Stats', body:'<p>…</p>', onClose:()=>{}});

BS.toast('quiet (respects Show feedback)')          // 1.2 s
BS.forceToast('loud', 1600)                          // always
BS.toastAction('Note deleted', 'Undo', ()=>BS.runCommand('undo'), 6000);
```

**`PX` extension points** (used by built-in personas; all optional):

| Hook | Signature | Purpose |
|---|---|---|
| `PX.topItems` | `fn() → item[]` | entries appended to the More menu |
| `PX.noteItems` | `fn() → item[]` | items in the note context menu |
| `PX.providers` | `(node, {ctx,depth}) → html` | chips/meta rows under a note |
| `PX.classers` | `(el, node, ctx) → void` | extra classes on rendered notes |
| `PX.actions` | `id → fn` | handlers for `data-px` buttons |
| `PX.stat` | `fn() → string` | extra segments in the status bar |
| `PX.run` / `PX.keys` | `id → fn` / `id → shortcut` | command dispatch and default keys |

Helpers for plugins: `pxAllNodes()` (flattened walk with depth), `pxTitle(node)`, `pxSelect(id,{edit})`,
`pxRerender()`, `pxChange()`, `pxEsc()`, `cmdItem(id, extra)`.

---

## 8. Icons — never generate them

The app uses **Bootstrap Icons only**, mapped through a name table.

```js
BS.icon('file')            // '<i class="bi bi-file" aria-hidden="true"></i>'
BS.setIcon(btn,'x','Close') // fills the element and sets aria-label
BS.BOOTSTRAP_ICONS.myThing = 'file-earmark-pdf'   // register a name → bi class
```

Unresolvable names fall back to `bi-circle`. Do not ship inline SVG/emoji icons; add a table entry.

---

## 9. Import / export

- `openImporter(src)` — the import dialog. `src` is `{html, text}` or `null`; split by
  headings/bullets/both, max depth 1–4, join paragraphs, per-row promote/demote/merge/rename before
  committing. One undo removes the whole import.
- File button inside it accepts `.txt .md .markdown .docx .pdf` (docx = zip+XML pass, pdf = pdf.js).
- PDFs: `openPdf` → `pdfPagePicker` pages → text → same importer. Stored in IndexedDB as `pdf:<id>`.
- `exportMarkdown()` (current doc), `exportBackup()` (all state), `importBackup()`.
- **`exportDiagram()`** — trail-of-thought export: the current doc's tree as a standalone themed
  SVG. Depth → columns (left-to-right), tidy-tree vertical layout, elbow connectors, numbered step
  badges in pre-order, `done`/`draft` status styling, wrapped text per box. Colors and font are
  baked from the live theme (`--bg/--panel/--text/--line/--accent/--accent-soft/--font-note`), so
  the file matches what the user sees. Zero deps, no canvas. Empty tree → error toast, no file.
  Shortcut: `Alt+Shift+G` (PC) / `Ctrl+Meta+G` (Apple). Builder is internal (`diagramSVG()`).
- Declared losses are shown in the UI before anything is converted — keep them declared.

---

## 10. Vault sidebar

- State: `state.vaults[]` (`{id,name}`), `state.folders[]` (`{id,name,vaultId,parentId,open}`),
  per-document `vaultId` / `folderId`.
- `renderVaultRail()` redraws the tree; `vaultOpenDoc(id)` opens a note **and focuses its editor**;
  `toggleFolder(id)`; `connectFolder()` uses the File System Access API (`showDirectoryPicker`).
- `state.behavior.showSidebar` drives `applySidebar()`. `Esc` closes it, `#sidebarToggleBtn` in the
  top bar (and More ▸ Toggle file sidebar) reopens it. Default open on desktop.
- Keyboard in the tree: arrows move, `Enter` open, `F2` rename, `Delete`, `Ctrl+N` new note.

---

## 11. Harness

### Fast check first, harness second

```bash
cd branch-studio && ./check.sh      # ~1 s: extracts the last <script> block, node --check
```

A broken edit shows up as `Unexpected end of input` / `missing )` here long before the harness
spends three minutes on it.

```bash
pw /Users/Userit/Branch/tools/run-harness.js /Users/Userit/Branch/branch-studio 8911
# prints:  TITLE:   MOTION OK
#          SUMMARY: checks=191  fails=0      (exit 0 = green)
```

`run-harness.js <dir> [port] [--quiet]` serves `dir`, opens `motion-test.html`, waits for the title
verdict (180 s), prints the summary and any `[FAIL]` lines, and exits non-zero on failure. It also
surfaces every `console.error` and `pageerror` from the page — so a stray `console.log`-driven
debug line is harmless but an uncaught exception fails the run.

### How `motion-test.html` works

It loads `index.html?harness=1` in an offscreen iframe, `localStorage.clear()`s, builds a fixture
tree through `w.eval("eval('state') … adoptState(s) … renderAll()")`, then asserts.

```js
const results = []; let n = 0;
function log(cls, msg) {           // cls: 'pass' | 'fail' | anything else = info
  n++; results.push(cls);
  out.textContent += String(n).padStart(2,'0') + ' [' + cls.toUpperCase() + '] ' + msg;
  summary.textContent = `checks=${results.length}  fails=${results.filter(c=>c==='fail').length}`;
}
```

Add checks anywhere inside `run()`: `log('pass','my thing works')` /
`log('fail','reason: ' + detail)`. Verdict comes from `document.title` (`MOTION OK` /
`MOTION n FAILED` / `MOTION ERROR`) and `#summary` is parsed by the runner — keep both formats.

### Playwright recipe

```js
const p = await browser.newPage({ viewport: {width:1280, height:820} });
const errs = []; p.on('pageerror', e => errs.push(e.message));
await p.goto('http://127.0.0.1:8787/index.html');
await p.evaluate(() => { try { localStorage.clear() } catch(e){} });
await p.reload({ waitUntil: 'networkidle' });
await p.waitForTimeout(2000);

// act through the API instead of the DOM where you can
await p.evaluate(() => { BS.setMode('split'); BS.addChild(); BS.doc().selectedId = BS.tree()[0].id; BS.renderAll() });
```

### Pitfalls

1. **Screenshots of the running app come out tiled/ghosted** (Chromium + the canvas layers).
   Assert on DOM/geometry instead, or render a single SVG/canvas yourself.
2. **Keep first-run overlays out of the harness** — `navigator.webdriver` guards exist for this;
   a modal backdrop silently blocks every click.
3. **`SOUND.s.enabled`**, not `SOUND.enabled`. Probes that toggle sound leave it off for later runs.
4. Serve from the repo dir, not `Applications/Branch Studio.app/Contents/Resources/`.
5. Two `<script>` tags in `index.html`; when extracting JS for a syntax check use
   `s.rfind('<script>')` … `s.find('</script>', i)` — the first `</script>` cuts it short
   (the font blob comes after the app script).
6. Don't read `index.html` lines ~13–3244 (MathLive bundle) or base64 font blobs; filter greps by
   line number (`awk -F: '$1>3244'`).
7. Copy to the app bundle after editing: `cp index.html "/Users/Userit/Applications/Branch Studio.app/Contents/Resources/index.html"`.
8. Pages publishes `main` only; `animation-overhaul` must be fast-forwarded into `main`.

---

## 12. Conventions

- One file, no bundler, no imports, no `node_modules`. Keep edits inside `index.html`.
- Icon library, not generated art. Sound is synthesised, not loaded.
- Every new interaction needs: a keyboard path, a distinct sound cue, and an undo snapshot if it
  mutates the tree.
- `state.behavior` flags gate chrome: `showTopbar showContextbar showStatusbar showSidebar
  showAddButtons showFeedback shortcutsEnabled confirmDelete focusNewNote nestedReading inputMode`.
- Anything persisted must survive `normalizeState()` (it re-merges every default, so unknown keys
  round-trip but missing ones are refilled).

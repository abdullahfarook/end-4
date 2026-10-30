// Hidden Changes: hide tracked files from Source Control with `git update-index --skip-worktree`.
// Hidden files are tracked per repo in <gitdir>/info/vscode-hidden-changes.json as { files: { "<rel path>": { hash } } }.
// Whether a file is currently hidden is always read from git (`git ls-files -v`), never cached.

const vscode = require('vscode');
const cp = require('child_process');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const STATE_FILE = 'info/vscode-hidden-changes.json';

let gitApi;
let watchers = [];
let queue = Promise.resolve();

// Serialize all git/state work so watcher events and commands never interleave.
function enqueue(fn) {
  const run = queue.then(fn);
  queue = run.catch(() => {});
  return run.catch(err => vscode.window.showErrorMessage(`Hidden Changes: ${err.message}`));
}

function git(cwd, args) {
  return new Promise((resolve, reject) => {
    cp.execFile('git', args, { cwd, maxBuffer: 1 << 26 }, (err, stdout, stderr) =>
      err ? reject(new Error((stderr || err.message).trim())) : resolve(stdout));
  });
}

async function gitPath(root, p) {
  return path.resolve(root, (await git(root, ['rev-parse', '--git-path', p])).trim());
}

async function loadState(root) {
  try {
    const st = JSON.parse(fs.readFileSync(await gitPath(root, STATE_FILE), 'utf8'));
    return { files: st.files || {} };
  } catch {
    return { files: {} };
  }
}

async function saveState(root, st) {
  const file = await gitPath(root, STATE_FILE);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(st, null, 2));
}

function hashFile(file) {
  try {
    return crypto.createHash('sha1').update(fs.readFileSync(file)).digest('hex');
  } catch {
    return null;
  }
}

async function excludedLines(root) {
  try {
    return new Set(fs.readFileSync(await gitPath(root, 'info/exclude'), 'utf8').split(/\r?\n/));
  } catch {
    return new Set();
  }
}

// Map of index path -> true if skip-worktree is set.
async function indexFlags(root) {
  const out = await git(root, ['ls-files', '-v', '-z']);
  const flags = new Map();
  for (const entry of out.split('\0')) {
    if (entry.length > 2) flags.set(entry.slice(2), entry[0] === 'S');
  }
  return flags;
}

// Untracked files are hidden via a line in .git/info/exclude instead of skip-worktree.
async function setExcluded(root, rel, on) {
  const exclude = await gitPath(root, 'info/exclude');
  const line = '/' + rel;
  const existing = fs.existsSync(exclude) ? fs.readFileSync(exclude, 'utf8') : '';
  const lines = existing.split(/\r?\n/);
  if (on === lines.includes(line)) return;
  if (on) {
    fs.mkdirSync(path.dirname(exclude), { recursive: true });
    fs.appendFileSync(exclude, (existing && !existing.endsWith('\n') ? '\n' : '') + line + '\n');
  } else {
    fs.writeFileSync(exclude, lines.filter(l => l !== line).join('\n'));
  }
}

// Hide or show one recorded file, whichever way it was hidden.
function setHidden(root, rel, entry, on) {
  return entry.untracked ? setExcluded(root, rel, on) : setSkip(root, rel, on);
}

function setSkip(root, rel, on) {
  return git(root, ['update-index', on ? '--skip-worktree' : '--no-skip-worktree', '--', rel]);
}

function relPath(root, fsPath) {
  return path.relative(root, fsPath).split(path.sep).join('/');
}

function repoForRoot(rootUri) {
  return gitApi.repositories.find(r => r.rootUri.toString() === rootUri.toString());
}

// Collect file URIs from SCM context-menu args (clicked resource + multi-selection) or the active editor.
function urisFromArgs(args) {
  const uris = new Map();
  for (const a of args.flat()) {
    if (a && a.resourceUri) uris.set(a.resourceUri.toString(), a.resourceUri);
    else if (a instanceof vscode.Uri && a.scheme === 'file') uris.set(a.toString(), a);
  }
  if (!uris.size && vscode.window.activeTextEditor) {
    const u = vscode.window.activeTextEditor.document.uri;
    if (u.scheme === 'file') uris.set(u.toString(), u);
  }
  return [...uris.values()];
}

async function refresh(repos) {
  for (const repo of repos) {
    try { await repo.status(); } catch { /* repo may have closed */ }
  }
  await updateContext();
}

// Recompute the toggle-button context keys and the file watchers for every open repo.
async function updateContext() {
  const canShow = [];
  const canHide = [];
  for (const w of watchers) w.dispose();
  watchers = [];

  for (const repo of gitApi.repositories) {
    const root = repo.rootUri.fsPath;
    let st, flags;
    try {
      st = await loadState(root);
      flags = await indexFlags(root);
    } catch {
      continue;
    }

    // Drop entries for files that are no longer in the index (deleted or renamed upstream).
    const listed = Object.keys(st.files);
    const gone = listed.filter(p => !flags.has(p) && !st.files[p].untracked);
    if (gone.length) {
      gone.forEach(p => delete st.files[p]);
      await saveState(root, st);
    }

    const tracked = Object.keys(st.files);
    const excluded = await excludedLines(root);
    const isHidden = p => st.files[p].untracked ? excluded.has('/' + p) : flags.get(p);
    const visible = tracked.filter(p => !isHidden(p));
    if (visible.length) canHide.push(repo.rootUri.toString());
    else if (tracked.length) canShow.push(repo.rootUri.toString());

    for (const rel of tracked.filter(p => isHidden(p))) {
      const w = vscode.workspace.createFileSystemWatcher(new vscode.RelativePattern(repo.rootUri, rel));
      const check = () => enqueue(() => checkChanged(repo, rel));
      w.onDidChange(check);
      w.onDidCreate(check);
      watchers.push(w);
    }
  }

  await vscode.commands.executeCommand('setContext', 'hiddenChanges.canShow', canShow);
  await vscode.commands.executeCommand('setContext', 'hiddenChanges.canHide', canHide);
}

// A hidden file changed on disk: if its content differs from when it was hidden, bring it back.
async function checkChanged(repo, rel) {
  if (!vscode.workspace.getConfiguration('hiddenChanges').get('autoShowOnChange')) return;
  const root = repo.rootUri.fsPath;
  const st = await loadState(root);
  const entry = st.files[rel];
  if (!entry) return;
  if (entry.untracked) return;
  const flags = await indexFlags(root);
  if (!flags.get(rel)) return;
  const hash = hashFile(path.join(root, rel));
  if (!hash || hash === entry.hash) return;

  await setSkip(root, rel, false);
  await refresh([repo]);
  // Not awaited: the toast stays open until dismissed and would block the queue (and any Hide command).
  vscode.window.showInformationMessage(
    `Hidden Changes: ${rel} changed, so it is showing in Source Control again.`, 'Hide Again').then(choice => {
    if (choice !== 'Hide Again') return;
    enqueue(async () => {
      const cur = await loadState(root);
      if (!cur.files[rel]) return;
      cur.files[rel].hash = hashFile(path.join(root, rel));
      await saveState(root, cur);
      await setSkip(root, rel, true);
      await refresh([repo]);
    });
  });
}

async function hideFile(...args) {
  const uris = urisFromArgs(args);
  if (!uris.length) return vscode.window.showWarningMessage('Hidden Changes: no file selected.');
  const touched = new Set();

  // Expand folders (Explorer menu) into the changed and untracked files beneath them.
  const expanded = [];
  for (const uri of uris) {
    let isDir = false;
    try { isDir = fs.statSync(uri.fsPath).isDirectory(); } catch { /* deleted file */ }
    const repo = isDir && gitApi.getRepository(uri);
    if (!repo) { expanded.push(uri); continue; }
    const root = repo.rootUri.fsPath;
    const rel = relPath(root, uri.fsPath) || '.';
    const changed = await git(root, ['diff', '--name-only', '-z', 'HEAD', '--', rel]).catch(() => '');
    const untracked = await git(root, ['ls-files', '-o', '--exclude-standard', '-z', '--', rel]);
    for (const f of (changed + untracked).split('\0').filter(Boolean)) {
      expanded.push(vscode.Uri.file(path.join(root, f)));
    }
  }

  for (const uri of expanded) {
    const repo = gitApi.getRepository(uri);
    if (!repo) continue;
    const root = repo.rootUri.fsPath;
    const rel = relPath(root, uri.fsPath);
    touched.add(repo);

    const flags = await indexFlags(root);
    if (!flags.has(rel)) {
      // Untracked files can't use skip-worktree; ignore them locally instead, and remember them so Show/Unhide work.
      const st = await loadState(root);
      st.files[rel] = { untracked: true };
      await saveState(root, st);
      await setExcluded(root, rel, true);
      continue;
    }

    const st = await loadState(root);
    st.files[rel] = { hash: hashFile(uri.fsPath) };
    await saveState(root, st);
    await setSkip(root, rel, true);
  }
  await refresh([...touched]);
}

async function forgetFile(...args) {
  let targets = []; // { repo, rel }
  const uris = args.flat().some(a => a && a.resourceUri) ? urisFromArgs(args) : [];

  if (uris.length) {
    for (const uri of uris) {
      const repo = gitApi.getRepository(uri);
      if (repo) targets.push({ repo, rel: relPath(repo.rootUri.fsPath, uri.fsPath) });
    }
  } else {
    const items = [];
    for (const repo of gitApi.repositories) {
      const st = await loadState(repo.rootUri.fsPath);
      for (const rel of Object.keys(st.files)) {
        items.push({ label: rel, description: path.basename(repo.rootUri.fsPath), repo, rel });
      }
    }
    if (!items.length) return vscode.window.showInformationMessage('Hidden Changes: no hidden files.');
    const picked = await vscode.window.showQuickPick(items, { canPickMany: true, placeHolder: 'Stop hiding which files?' });
    if (!picked) return;
    targets = picked;
  }

  for (const { repo, rel } of targets) {
    const root = repo.rootUri.fsPath;
    const st = await loadState(root);
    if (!st.files[rel]) continue;
    const entry = st.files[rel];
    delete st.files[rel];
    await saveState(root, st);
    await setHidden(root, rel, entry, false);
  }
  await refresh(targets.map(t => t.repo));
}

function reposFromArg(sourceControl) {
  if (sourceControl && sourceControl.rootUri) {
    const repo = repoForRoot(sourceControl.rootUri);
    return repo ? [repo] : [];
  }
  return gitApi.repositories;
}

async function showAll(sourceControl) {
  const repos = reposFromArg(sourceControl);
  for (const repo of repos) {
    const root = repo.rootUri.fsPath;
    const st = await loadState(root);
    for (const [rel, e] of Object.entries(st.files)) await setHidden(root, rel, e, false);
  }
  await refresh(repos);
}

async function hideAll(sourceControl) {
  const repos = reposFromArg(sourceControl);
  for (const repo of repos) {
    const root = repo.rootUri.fsPath;
    const st = await loadState(root);
    // Re-hiding accepts the current content as the new baseline for change detection.
    for (const rel of Object.keys(st.files)) {
      if (!st.files[rel].untracked) st.files[rel].hash = hashFile(path.join(root, rel));
    }
    await saveState(root, st);
    for (const [rel, e] of Object.entries(st.files)) await setHidden(root, rel, e, true);
  }
  await refresh(repos);
}

async function activate(context) {
  const ext = vscode.extensions.getExtension('vscode.git');
  if (!ext) return;
  const exports = ext.isActive ? ext.exports : await ext.activate();
  gitApi = exports.getAPI(1);

  const reg = (id, fn) => context.subscriptions.push(
    vscode.commands.registerCommand(id, (...args) => enqueue(() => fn(...args))));
  reg('hiddenChanges.hideFile', hideFile);
  reg('hiddenChanges.forgetFile', forgetFile);
  reg('hiddenChanges.showAll', showAll);
  reg('hiddenChanges.hideAll', hideAll);

  const update = () => enqueue(updateContext);
  context.subscriptions.push(
    gitApi.onDidOpenRepository(update),
    gitApi.onDidCloseRepository(update),
    gitApi.onDidChangeState(update),
    { dispose: () => watchers.forEach(w => w.dispose()) });
  update();
}

function deactivate() {}

module.exports = { activate, deactivate };

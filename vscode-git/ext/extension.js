// Opens the Source Control view on startup and closes restored editors (panel stays narrow until a file is opened); title-bar buttons to change/add the folder (the menu bar is hidden).
const vscode = require('vscode');
const run = (id) => () => vscode.commands.executeCommand(id);
exports.activate = async (ctx) => {
  for (const [id, cmd] of [['openFolder', 'workbench.action.files.openFolder'], ['openRecent', 'workbench.action.openRecent'], ['addFolder', 'workbench.action.addRootFolder']])
    ctx.subscriptions.push(vscode.commands.registerCommand('gitpanel.' + id, run(cmd)));
  await new Promise(r => setTimeout(r, 2500));  // after the workbench restores its last view
  await vscode.commands.executeCommand('workbench.view.scm');
  await vscode.commands.executeCommand('workbench.action.closePanel');
  await vscode.commands.executeCommand('workbench.action.closeAllEditors');
  // Opening a file/diff makes VS Code pop up the bottom panel (Git output etc.): keep it closed.
  // (Hiding the editor area when no editor is open is done by vscode-git-watch.sh via a `when`-guarded keybinding, so it cannot get out of step.)
  const tabCount = () => vscode.window.tabGroups.all.reduce((n, g) => n + g.tabs.length, 0);
  ctx.subscriptions.push(vscode.window.tabGroups.onDidChangeTabs(() => {
    if (tabCount() > 0) for (const ms of [150, 700]) setTimeout(() => vscode.commands.executeCommand('workbench.action.closePanel'), ms);
  }));
};

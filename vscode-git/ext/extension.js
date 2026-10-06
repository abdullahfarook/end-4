// Opens the Source Control view on startup; title-bar buttons to change/add the folder (the menu bar is hidden).
const vscode = require('vscode');
const run = (id) => () => vscode.commands.executeCommand(id);
exports.activate = async (ctx) => {
  for (const [id, cmd] of [['openFolder', 'workbench.action.files.openFolder'], ['openRecent', 'workbench.action.openRecent'], ['addFolder', 'workbench.action.addRootFolder']])
    ctx.subscriptions.push(vscode.commands.registerCommand('gitpanel.' + id, run(cmd)));
  await new Promise(r => setTimeout(r, 2500));  // after the workbench restores its last view
  await vscode.commands.executeCommand('workbench.view.scm');
  await vscode.commands.executeCommand('workbench.action.closePanel');
};

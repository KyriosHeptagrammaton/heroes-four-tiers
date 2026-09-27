const fs = require('fs'), path = require('path'), vm = require('vm');
const dir = path.join(__dirname, '../web/js');
const files = fs.readdirSync(dir).filter(f => f.endsWith('.js')).sort().filter(f => !/_ui|^9/.test(f));
global.window = undefined;
for (const f of files) vm.runInThisContext(fs.readFileSync(path.join(dir, f), 'utf8'), { filename: f });
module.exports = globalThis.G;

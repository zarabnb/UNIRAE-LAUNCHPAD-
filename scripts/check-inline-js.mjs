import fs from 'node:fs';
import vm from 'node:vm';

const file = new URL('../frontend/UNIRAE-Premium-UI-v2.27.html', import.meta.url);
const html = fs.readFileSync(file, 'utf8');
const blocks = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script\s*>/gi)]
  .map((match) => match[1].trim())
  .filter(Boolean);

for (let index = 0; index < blocks.length; index += 1) {
  new vm.Script(blocks[index], { filename: `inline-script-${index + 1}.js` });
}

console.log(`Inline JavaScript syntax checks passed (${blocks.length} blocks).`);

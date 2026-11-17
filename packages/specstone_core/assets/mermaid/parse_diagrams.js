// Parses Mermaid blocks with the bundled parser: run as `node -e <this file>`.
// stdin: the patched mermaid.min.js text, a newline, then one JSON line of
// [{i, text}]. stdout: one JSON result line per block, in input order.
'use strict';

const noop = () => {};
globalThis.window = globalThis;
globalThis.self = globalThis;
globalThis.addEventListener = noop;
globalThis.removeEventListener = noop;
globalThis.document = {
  createElement: () => ({
    style: {},
    setAttribute: noop,
    appendChild: noop,
    getElementsByTagName: () => [],
  }),
  createElementNS: () => ({ style: {}, setAttribute: noop, appendChild: noop }),
  querySelector: noop,
  querySelectorAll: () => [],
  getElementsByTagName: () => [],
  body: { appendChild: noop },
  addEventListener: noop,
  documentElement: { style: {} },
};
try {
  globalThis.navigator = { userAgent: 'node' };
} catch (e) {
  // Newer Node defines a read-only navigator, which serves as well.
}
globalThis.__esbuild_esm_mermaid_nm = {};
// stdout carries only result lines, so the bundle's own logs go to stderr.
for (const name of ['log', 'info', 'debug', 'trace', 'warn']) {
  console[name] = console.error;
}

// The count of lines the bundle's own preprocess keeps of block lines [lines].
function keptLines(lines) {
  try {
    const code = globalThis
      .__specstonePreprocessDiagram(lines.join('\n') + '\n')
      .code.replace(/\n$/, '');
    return code === '' ? 0 : code.split('\n').length;
  } catch (e) {
    return -1;
  }
}

// The 1-based block line of the parser's line [named], or null past the block.
function blockLine(text, named) {
  const lines = text.split('\n');
  if (keptLines(lines) < named) return null;
  let count = lines.length;
  while (count > 1 && keptLines(lines.slice(0, count - 1)) >= named) count--;
  return count;
}

async function parseBlock(block) {
  const mermaid = globalThis.mermaid;
  let message = null;
  try {
    await mermaid.parse(block.text);
  } catch (e) {
    message = String((e && e.message) || e);
  }
  let diagram = null;
  try {
    diagram = mermaid.detectType(block.text);
  } catch (e) {
    // No diagram type detected: the key stays null.
  }
  if (message === null) return { i: block.i, diagram, parses: true };
  const named = /\bline (\d+)/.exec(message);
  return {
    i: block.i,
    diagram,
    parses: false,
    message,
    line: named ? blockLine(block.text, Number(named[1])) : null,
  };
}

async function main() {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  const input = Buffer.concat(chunks).toString('utf8');
  const split = input.lastIndexOf('\n');
  (0, eval)(input.slice(0, split));
  for (const block of JSON.parse(input.slice(split + 1))) {
    process.stdout.write(JSON.stringify(await parseBlock(block)) + '\n');
  }
}

main().catch((e) => {
  console.error(String((e && e.stack) || e));
  process.exitCode = 1;
});

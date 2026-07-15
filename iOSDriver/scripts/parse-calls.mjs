#!/usr/bin/env node
import fs from "fs";

const txt = fs.readFileSync(process.argv[2], "utf8");

const blocks = [];
let pos = 0;
while (true) {
  const callIdx = txt.indexOf("=== tools/call", pos);
  if (callIdx < 0) break;
  const hdrEnd = txt.indexOf("\n", callIdx) + 1;
  const nextCall = txt.indexOf("=== tools/call", hdrEnd);
  const doneIdx = txt.indexOf("=== done", hdrEnd);
  let blockEnd = txt.length;
  if (nextCall > 0) blockEnd = Math.min(blockEnd, nextCall);
  if (doneIdx > 0) blockEnd = Math.min(blockEnd, doneIdx);
  blocks.push(txt.slice(hdrEnd, blockEnd).trim());
  pos = blockEnd;
}

function parseBalanced(s) {
  let depth = 0, inS = false, esc = false, end = -1;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (esc) { esc = false; continue; }
    if (c === "\\" && inS) { esc = true; continue; }
    if (c === "\"") inS = !inS;
    else if (!inS) {
      if (c === "{") depth++;
      else if (c === "}") { depth--; if (depth === 0) { end = i + 1; break; } }
    }
  }
  if (end < 0) return null;
  try { return JSON.parse(s.slice(0, end)); } catch { return null; }
}

for (let i = 0; i < blocks.length; i++) {
  const json = parseBalanced(blocks[i]);
  if (!json) { console.log(`Block#${i}: parse failed`); continue; }
  const text = json.content?.[0]?.text;
  if (!text) { console.log(`Block#${i}: no text (perhaps image)`); continue; }
  let parsed;
  try { parsed = JSON.parse(text); } catch { parsed = { __raw: text.slice(0,80) }; }

  if (parsed.cursor && parsed.latestAvailableID !== undefined) {
    console.log(`#${i} [mark] latestAvailableID=${parsed.latestAvailableID} sessionID=${parsed.cursor.captureSessionID}`);
  } else if (parsed.entries !== undefined) {
    console.log(`#${i} [read] entries=${parsed.entries.length}`);
    for (const e of parsed.entries.slice(0, 3)) {
      console.log(`    id=${e.id} source=${e.source} category=${e.category} level=${e.level} msg="${(e.message||"").slice(0, 80)}"`);
    }
  } else {
    console.log(`#${i} [other] code=${parsed.code} message="${(parsed.message||"").slice(0,80)}" isError=${json.isError}`);
  }
}

// Minimal DOM stub to execute site/index.html's inline script and verify
// the zh/en toggle renders both languages correctly.
import { readFileSync } from "node:fs";

const html = readFileSync(new URL("../site/index.html", import.meta.url), "utf8");
const m = html.match(/<script>([\s\S]*?)<\/script>/);
if (!m) throw new Error("no script found");

const elements = new Map();
function makeEl(id) {
  return {
    id,
    innerHTML: "",
    textContent: "",
    setAttribute() {},
    classList: { toggle() {}, add() {}, remove() {} },
    addEventListener() {},
  };
}

const storage = new Map();
globalThis.window = { location: { search: "" } };
Object.defineProperty(globalThis, "navigator", {
  value: { language: "zh-CN" },
  configurable: true,
});
globalThis.localStorage = {
  getItem: (k) => (storage.has(k) ? storage.get(k) : null),
  setItem: (k, v) => storage.set(k, String(v)),
};
globalThis.document = {
  documentElement: { lang: "" },
  title: "",
  getElementById(id) {
    if (!elements.has(id)) elements.set(id, makeEl(id));
    return elements.get(id);
  },
};

// Execute the page script plus a scope-exposure snippet in one eval.
const combined = m[1] + "\n;globalThis.__test = { render: render, currentLang: currentLang };";
eval(combined);

const T = globalThis.__test;

function snapshots() {
  const out = {};
  for (const [id, el] of elements) {
    if (el.innerHTML !== "" || el.textContent !== "") {
      out[id] = el.innerHTML || el.textContent;
    }
  }
  return out;
}

// Default render is EN even when the browser language is zh-CN.
const en0 = snapshots();
const en0Tagline = en0.heroTagline || "";
const en0Features = en0.featuresTitle || "";
const en0Nav = en0.topnav || "";
const toggleLabel = en0.langToggle || "";
const en0Title = document.title;

// Switch to zh.
T.render("zh");
const zh = snapshots();
const zhTagline = zh.heroTagline || "";
const zhFeatures = zh.featuresTitle || "";

// Switch back to en via the toggle handler path.
T.currentLang = "zh";
T.render("en");
const en2 = snapshots();
const en2Tagline = en2.heroTagline || "";

const checks = [
  ["en default tagline (browser zh)", en0Tagline.includes("One-click")],
  ["en default features", en0Features.includes("Why FRAMPP")],
  ["en default nav", en0Nav.includes("Quick Start")],
  ["toggle shows 中文 in en mode", toggleLabel === "中文"],
  ["en default title", en0Title.includes("One-click")],
  ["zh tagline after switch", zhTagline.includes("一键安装")],
  ["zh features after switch", zhFeatures.includes("为什么选 FRAMPP")],
  ["en back after toggle", en2Tagline.includes("One-click")],
];

let failed = 0;
for (const [name, ok] of checks) {
  console.log(`${ok ? "PASS" : "FAIL"}: ${name}`);
  if (!ok) failed++;
}
// Show a couple of snippets for evidence.
console.log("--- en0 heroTagline:", JSON.stringify(en0Tagline));
console.log("--- zh heroTagline:", JSON.stringify(zhTagline));
console.log("--- en0 langToggle:", JSON.stringify(toggleLabel));
console.log(failed === 0 ? "ALL_RENDER_CHECKS_PASSED" : `FAILED=${failed}`);
process.exit(failed === 0 ? 0 : 1);

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

// Default render uses zh (navigator zh-CN).
const zh = snapshots();
const zhTitle = zh.metaTitle ? null : document.title;
const zhTagline = zh.heroTagline || "";
const zhFeatures = zh.featuresTitle || "";

// Switch to EN.
T.render("en");
const en = snapshots();
const enTagline = en.heroTagline || "";
const enFeatures = en.featuresTitle || "";
const enNav = en.topnav || "";
const toggleLabel = en.langToggle || "";
const enTitle = document.title;

// Switch back to zh via the toggle handler path.
T.currentLang = "en";
T.render("zh");
const zh2 = snapshots();
const zh2Tagline = zh2.heroTagline || "";

const checks = [
  ["zh default tagline", zhTagline.includes("一键安装")],
  ["zh features", zhFeatures.includes("为什么选 FRAMPP")],
  ["en tagline", enTagline.includes("One-click")],
  ["en features", enFeatures.includes("Why FRAMPP")],
  ["en nav", enNav.includes("Quick Start")],
  ["toggle shows 中文 in en mode", toggleLabel === "中文"],
  ["title switch", enTitle.includes("One-click")],
  ["zh back after toggle", zh2Tagline.includes("一键安装")],
];

let failed = 0;
for (const [name, ok] of checks) {
  console.log(`${ok ? "PASS" : "FAIL"}: ${name}`);
  if (!ok) failed++;
}
// Show a couple of snippets for evidence.
console.log("--- zh heroTagline:", JSON.stringify(zhTagline));
console.log("--- en heroTagline:", JSON.stringify(enTagline));
console.log("--- en langToggle:", JSON.stringify(toggleLabel));
console.log(failed === 0 ? "ALL_RENDER_CHECKS_PASSED" : `FAILED=${failed}`);
process.exit(failed === 0 ? 0 : 1);

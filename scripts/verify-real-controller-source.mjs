import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { normalizedCatalogText } from "./normalize-localizations.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

function absolute(relativePath) {
  return path.join(root, relativePath);
}

function read(relativePath) {
  return readFileSync(absolute(relativePath), "utf8");
}

function listSwiftFiles(relativeDirectory) {
  const dir = absolute(relativeDirectory);
  if (!existsSync(dir)) return [];
  return readdirSync(dir).flatMap((entry) => {
    const full = path.join(dir, entry);
    const rel = path.relative(root, full);
    if (statSync(full).isDirectory()) return listSwiftFiles(rel);
    return rel.endsWith(".swift") ? [rel] : [];
  });
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

// 1. Validate Localizable.xcstrings structure and normalization parity.
const catalogPath = "Sources/Mica/Resources/Localizable.xcstrings";
const rawCatalog = read(catalogPath);
const catalog = JSON.parse(rawCatalog);
assert(catalog && typeof catalog.strings === "object", "Localizable.xcstrings must contain strings object");
assert(
  rawCatalog === normalizedCatalogText(rawCatalog),
  "Localizable.xcstrings is not normalized; run node scripts/normalize-localizations.mjs"
);

// 2. Validate Info.plist exists and declares macOS 27 minimum.
assert(existsSync(absolute("Sources/Mica/App/Info.plist")), "Missing Sources/Mica/App/Info.plist");
const plist = read("Sources/Mica/App/Info.plist");
assert(plist.includes("<string>27.0</string>"), "Info.plist must target macOS 27.0+");

// 3. Validate localization keys referenced via L("...") in refactored UI exist in EN & zh-Hans.
const uiFiles = [
  ...listSwiftFiles("Sources/Mica/Design"),
  ...listSwiftFiles("Sources/Mica/UI"),
];
assert(uiFiles.length >= 10, "Expected refactored UI Swift files under Sources/Mica/UI and Design");

const literalKeyRegex = /\bL\(\s*"([^"\\]+)"\s*,/g;
const forbiddenPatterns = [
  { name: "anchorPreference", regex: /\.anchorPreference\b/ },
  { name: "overlayPreferenceValue", regex: /\.overlayPreferenceValue\b/ },
  { name: "shadow modifier", regex: /\.shadow\s*\(/ },
  { name: "ViewThatFits", regex: /\bViewThatFits\b/ },
  { name: "MicaThemeFontModifier", regex: /\bMicaThemeFontModifier\b/ },
];

for (const file of uiFiles) {
  const content = read(file);
  for (const { name, regex } of forbiddenPatterns) {
    assert(!regex.test(content), `${file} uses forbidden heavy pattern: ${name}`);
  }

  for (const match of content.matchAll(literalKeyRegex)) {
    const key = match[1];
    if (key.includes("\\(")) continue;
    const entry = catalog.strings[key];
    assert(entry, `${file}: missing localization key "${key}" in Localizable.xcstrings`);
    assert(entry.localizations?.en?.stringUnit?.value, `${file}: missing EN localization for "${key}"`);
    assert(entry.localizations?.["zh-Hans"]?.stringUnit?.value, `${file}: missing zh-Hans localization for "${key}"`);
  }
}

console.log("Mica refactored UI source & localization contract passed");

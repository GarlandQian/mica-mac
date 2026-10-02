// Canonical formatting for the string catalog so additions never reorder or
// reformat unrelated entries: string keys sorted case-insensitively (as Xcode
// lists them), nested keys sorted, every entry marked as manually managed,
// two-space JSON, and a trailing newline.
//
//   node scripts/normalize-localizations.mjs          rewrite in place
//   node scripts/normalize-localizations.mjs --check  exit 1 when not canonical
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

export const catalogPath = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  "Sources/Mica/Resources/Localizable.xcstrings",
);

function compareCodeUnits(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}

export function compareStringKeys(left, right) {
  return compareCodeUnits(left.toLowerCase(), right.toLowerCase())
    || compareCodeUnits(left, right);
}

function sortedValue(value) {
  if (Array.isArray(value)) return value.map(sortedValue);
  if (value === null || typeof value !== "object") return value;
  return Object.fromEntries(
    Object.keys(value)
      .sort(compareCodeUnits)
      .map((key) => [key, sortedValue(value[key])]),
  );
}

export function normalizedCatalogText(raw) {
  const catalog = JSON.parse(raw);
  const strings = Object.fromEntries(
    Object.keys(catalog.strings)
      .sort(compareStringKeys)
      .map((key) => {
        const entry = sortedValue(catalog.strings[key]);
        return [key, sortedValue({ extractionState: "manual", ...entry })];
      }),
  );
  const normalized = { ...sortedValue({ ...catalog, strings: {} }), strings };
  const ordered = Object.fromEntries(
    Object.keys(normalized)
      .sort(compareCodeUnits)
      .map((key) => [key, normalized[key]]),
  );
  return `${JSON.stringify(ordered, null, 2)}\n`;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const raw = readFileSync(catalogPath, "utf8");
  const normalized = normalizedCatalogText(raw);
  if (process.argv.includes("--check")) {
    if (raw !== normalized) {
      console.error("Localizable.xcstrings is not canonical; run node scripts/normalize-localizations.mjs");
      process.exit(1);
    }
  } else if (raw !== normalized) {
    writeFileSync(catalogPath, normalized);
  }
}

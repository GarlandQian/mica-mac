#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { isDeepStrictEqual } from "node:util";
import { pathToFileURL } from "node:url";

const usage = "Usage: node scripts/compare-performance.mjs BEFORE.json AFTER.json [--max-regression 1.25]";
const isRecord = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const isText = (value) => typeof value === "string" && value.trim().length > 0;
const isCount = (value) => Number.isSafeInteger(value) && value >= 0;
const isTiming = (value) => typeof value === "number" && Number.isFinite(value) && value >= 0;
const noScrollSurface = "no overflowing native vertical scroll surface in this fixture";

// Neither schema identifies the physical machine. Matching metadata is a
// necessary precondition, not proof of identical hardware or idle conditions.
export function compareReports(before, after, { maxRegression } = {}) {
  const issues = [];
  const rows = [];
  const unmeasured = [];
  const issue = (message) => issues.push(message);
  const equal = (left, right, label) => {
    if (!isDeepStrictEqual(left, right)) issue(`${label} differs: ${JSON.stringify(left)} -> ${JSON.stringify(right)}`);
  };
  if (maxRegression !== undefined && (!Number.isFinite(maxRegression) || maxRegression <= 0)) {
    issue("--max-regression must be a finite positive after/before ratio");
  }

  function schema(report, side) {
    if (!isRecord(report) || !Array.isArray(report.cases) || report.cases.length === 0) {
      issue(`${side}: a report must contain a nonempty cases array`);
      return undefined;
    }
    if (report.buildConfiguration !== "release") issue(`${side}: buildConfiguration must be release`);
    if (!isText(report.operatingSystem)) issue(`${side}: operatingSystem is missing`);
    if (report.schemaVersion === 2 && report.cases.every((entry) => isRecord(entry) && isText(entry.name))) return "cpu";
    if (report.schemaVersion === 1 && report.cases.every((entry) => isRecord(entry) && isText(entry.destination))) return "scroll";
    issue(`${side}: unsupported or mixed performance report schema`);
    return undefined;
  }

  const kind = schema(before, "before");
  const afterKind = schema(after, "after");
  if (kind && afterKind) {
    equal(kind, afterKind, "report kind");
    equal(before.operatingSystem, after.operatingSystem, "operatingSystem");
    if (kind === "cpu" && afterKind === "cpu") {
      if (!isText(before.swiftVersion) || !isText(after.swiftVersion)) issue("swiftVersion is missing");
      equal(before.swiftVersion, after.swiftVersion, "swiftVersion");
    }
    if (kind === "scroll" && afterKind === "scroll") {
      for (const [side, report] of [["before", before], ["after", after]]) {
        if (!isRecord(report.fixtureCounts) || Object.keys(report.fixtureCounts).length === 0
            || !Object.values(report.fixtureCounts).every(isCount)) issue(`${side}: invalid fixtureCounts`);
        if (!isCount(report.samplesPerSurface) || report.samplesPerSurface < 2) issue(`${side}: invalid samplesPerSurface`);
        for (const field of ["requestedTickHz", "refreshHz"]) {
          if (!isTiming(report[field]) || report[field] === 0) issue(`${side}: invalid ${field}`);
        }
      }
      for (const field of ["fixtureCounts", "samplesPerSurface", "requestedTickHz", "refreshHz"]) {
        equal(before[field], after[field], field);
      }
    }
  }

  function indexCases(report, side) {
    const entries = new Map();
    for (const entry of report.cases) {
      const parts = kind === "cpu"
        ? [entry.name, entry.fixtureCount]
        : [entry.destination, entry.mode, entry.surfaceIndex];
      if (kind === "cpu" && (!isCount(entry.fixtureCount) || entry.fixtureCount === 0)) {
        issue(`${side}: ${entry.name} has invalid fixtureCount`);
      }
      if (kind === "scroll" && (!["stationary", "refreshing"].includes(entry.mode) || !isCount(entry.surfaceIndex))) {
        issue(`${side}: ${entry.destination} has invalid mode/surfaceIndex`);
      }
      const key = JSON.stringify(parts);
      if (entries.has(key)) issue(`${side}: duplicate case ${key}`);
      entries.set(key, entry);
    }
    return entries;
  }

  function metric(label, left, right) {
    if (!isTiming(left) || !isTiming(right)) {
      issue(`${label}: missing, negative, or nonfinite timing`);
      return undefined;
    }
    const ratio = left === 0 ? (right === 0 ? 1 : Infinity) : right / left;
    return { label, before: left, after: right, ratio, overBudget: maxRegression !== undefined && ratio > maxRegression };
  }

  if (issues.length === 0) {
    const previous = indexCases(before, "before");
    const next = indexCases(after, "after");
    for (const key of previous.keys()) if (!next.has(key)) issue(`after: missing case ${key}`);
    for (const key of next.keys()) if (!previous.has(key)) issue(`after: unexpected case ${key}`);
    for (const [key, left] of previous) {
      const right = next.get(key);
      if (!right) continue;
      const label = kind === "cpu"
        ? `${left.name} [${left.fixtureCount}]`
        : `${left.destination}/${left.mode}/${left.surfaceIndex}`;
      if (kind === "cpu") {
        if (!isCount(left.samples) || left.samples === 0 || !isCount(right.samples) || right.samples === 0) {
          issue(`${label}: invalid samples`);
        }
        equal(left.samples, right.samples, `${label} samples`);
        rows.push({ label, metrics: [
          metric(`${label} median`, left.medianMilliseconds, right.medianMilliseconds),
          metric(`${label} p95`, left.p95Milliseconds, right.p95Milliseconds),
        ].filter(Boolean) });
      } else {
        for (const field of ["status", "surfaceKind", "inputMode"]) {
          if (!isText(left[field]) || !isText(right[field])) issue(`${label}: missing ${field}`);
          equal(left[field], right[field], `${label} ${field}`);
        }
        equal(left.sampleCount, right.sampleCount, `${label} sampleCount`);
        if (left.status !== "measured" || right.status !== "measured") {
          if (left.status !== noScrollSurface || right.status !== noScrollSurface) {
            issue(`${label}: failed or unknown scroll measurement status`);
          }
          unmeasured.push(`${label}: ${left.status}`);
          continue;
        }
        equal(left.viewportHeight, right.viewportHeight, `${label} viewportHeight`);
        for (const [side, entry, report] of [["before", left, before], ["after", right, after]]) {
          if (!isCount(entry.sampleCount) || entry.sampleCount < 2 || entry.sampleCount !== report.samplesPerSurface) {
            issue(`${side} ${label}: incomplete samples`);
          }
          if (!["native-wheel", "programmatic-viewport"].includes(entry.inputMode)
              || !isTiming(entry.offsetRange) || entry.offsetRange <= 1
              || !isCount(entry.changedOffsetCount) || entry.changedOffsetCount === 0) {
            issue(`${side} ${label}: measured case has no verified scrolling displacement`);
          }
          if (!isTiming(entry.viewportHeight) || entry.viewportHeight === 0) issue(`${side} ${label}: invalid viewportHeight`);
          if (entry.tickInterval?.count !== entry.sampleCount - 1 || entry.layoutAndCommit?.count !== entry.sampleCount) {
            issue(`${side} ${label}: incomplete tick/layout sample counts`);
          }
          if (!isCount(entry.refreshCount) || entry.fixturePublication?.count !== entry.refreshCount
              || (entry.mode === "refreshing" ? entry.refreshCount === 0 : entry.refreshCount !== 0)) {
            issue(`${side} ${label}: fixture publication did not match the requested refresh workload`);
          }
        }
        rows.push({ label, metrics: [
          metric(`${label} tick p95`, left.tickInterval?.p95Milliseconds, right.tickInterval?.p95Milliseconds),
          metric(`${label} layout p95`, left.layoutAndCommit?.p95Milliseconds, right.layoutAndCommit?.p95Milliseconds),
        ].filter(Boolean) });
      }
    }
    if (rows.length === 0) issue("No measured cases are comparable; unmeasured surfaces cannot pass a performance budget");
  }

  const regressions = rows.flatMap((row) => row.metrics).filter((entry) => entry.overBudget);
  const warnings = kind === "cpu" && before.swiftVersion === "unknown"
    ? ["swiftVersion is unknown; matching compiler versions could not be verified."] : [];
  return { kind, maxRegression, rows, unmeasured, issues, regressions, warnings, exitCode: issues.length ? 2 : regressions.length ? 1 : 0 };
}

export function formatComparison(result) {
  const lines = [`${result.kind?.toUpperCase() ?? "Performance"} comparison (after / before)`];
  if (result.issues.length) {
    lines.push("INCOMPARABLE — no performance verdict", ...result.issues.map((entry) => `  ${entry}`));
    return lines.join("\n");
  }
  const number = (value) => Number.isFinite(value) ? value.toFixed(3) : "Infinity";
  for (const row of result.rows) {
    lines.push(`${row.label}: ${row.metrics.map((entry) =>
      `${entry.label.slice(row.label.length + 1)} ${number(entry.before)} -> ${number(entry.after)} ms (${number(entry.ratio)}x)${entry.overBudget ? " OVER BUDGET" : ""}`
    ).join("; ")}`);
  }
  for (const entry of result.unmeasured) lines.push(`NOT MEASURED — ${entry}`);
  lines.push(`${result.rows.length} measured cases compared; ${result.unmeasured.length} unmeasured cases receive no verdict.`);
  lines.push(result.maxRegression === undefined
    ? "Report only: no regression threshold applied."
    : `Budget ${result.maxRegression}x: ${result.regressions.length} metrics over budget (measured cases only).`);
  lines.push(...result.warnings);
  lines.push("Machine identity, idle conditions, compositor frames and touchpad behavior are not verified by this comparison.");
  return lines.join("\n");
}

function main(args) {
  if (args.length === 1 && ["--help", "-h"].includes(args[0])) {
    console.log(`${usage}\nDefault: report only. Exit codes: 0 comparable, 1 budget exceeded, 2 invalid/incomparable.`);
    return 0;
  }
  const paths = [];
  let maxRegression;
  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index];
    if (argument === "--max-regression" && maxRegression === undefined && args[index + 1] !== undefined) {
      maxRegression = Number(args[++index]);
    } else if (argument.startsWith("-")) {
      throw new Error(`Unknown or incomplete option: ${argument}\n${usage}`);
    } else {
      paths.push(argument);
    }
  }
  if (paths.length !== 2) throw new Error(usage);
  const [before, after] = paths.map((path) => JSON.parse(readFileSync(path, "utf8")));
  const result = compareReports(before, after, { maxRegression });
  console.log(formatComparison(result));
  return result.exitCode;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    process.exitCode = main(process.argv.slice(2));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 2;
  }
}

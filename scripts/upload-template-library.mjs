#!/usr/bin/env node

import { createHash } from "node:crypto";
import { execFile, execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const execFileAsync = promisify(execFile);
const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const sourceRoot = path.join(repoRoot, "Flick", "ExampleSlideshows");
const pageSize = numberArg("--page-size", 24);
const concurrency = numberArg("--concurrency", 8);
const bucket = stringArg("--bucket") ?? process.env.R2_BUCKET;
const releaseID = stringArg("--release-id") ?? defaultReleaseID();

if (!bucket) {
  fail("R2 bucket is required. Pass --bucket <name> or set R2_BUCKET.");
}

const releaseBasePath = `template-library/releases/${releaseID}`;
const generatedRoot = mkdtempSync(path.join(tmpdir(), `flick-template-library-${releaseID}-`));

const sourceFiles = listFiles(sourceRoot);
const contentHash = hashFiles(sourceFiles);
const sourceIndex = readJSON(path.join(sourceRoot, "index.json"));
const generatedObjects = generateIndexes(sourceIndex);
const uploadObjects = [
  ...sourceFiles.map((filePath) => ({
    key: `${releaseBasePath}/ExampleSlideshows/${relativePOSIX(sourceRoot, filePath)}`,
    filePath,
    contentType: contentTypeFor(filePath)
  })),
  ...generatedObjects
];

ensureBucket();
await uploadAll(uploadObjects);

const currentPath = path.join(generatedRoot, "current.json");
writeJSON(currentPath, {
  releaseID,
  basePath: releaseBasePath,
  indexPath: `${releaseBasePath}/index.json`,
  uploadedAt: new Date().toISOString(),
  fileCount: sourceFiles.length,
  objectCount: uploadObjects.length + 1,
  contentHash
});
await putObject("template-library/current.json", currentPath, "application/json");

await verifyObject("template-library/current.json");
await verifyObject(`${releaseBasePath}/index.json`);
await verifyObject(`${releaseBasePath}/ExampleSlideshows/index.json`);

console.log(`Uploaded template library release ${releaseID}`);
console.log(`Bucket: ${bucket}`);
console.log(`Source files: ${sourceFiles.length}`);
console.log(`Uploaded objects including current.json: ${uploadObjects.length + 1}`);
console.log(`Content hash: ${contentHash}`);

function generateIndexes(sourceIndex) {
  const objects = [];
  const niches = sourceIndex.niches.map((niche) => {
    const manifestPath = path.join(sourceRoot, niche.manifest);
    const manifest = readJSON(manifestPath);
    const nicheSlug = manifest.nicheSlug ?? niche.nicheSlug;
    const pageCount = Math.max(1, Math.ceil(manifest.slideshows.length / pageSize));
    const pages = [];

    for (let offset = 0; offset < manifest.slideshows.length; offset += pageSize) {
      const pageNumber = Math.floor(offset / pageSize) + 1;
      const pagePath = `${releaseBasePath}/niches/${nicheSlug}/pages/${pageNumber}.json`;
      pages.push(pagePath);
      const pageFilePath = path.join(generatedRoot, "niches", nicheSlug, "pages", `${pageNumber}.json`);
      writeJSON(pageFilePath, {
        releaseID,
        nicheSlug,
        pageNumber,
        pageSize,
        pageCount,
        slideshows: manifest.slideshows.slice(offset, offset + pageSize)
      });
      objects.push({ key: pagePath, filePath: pageFilePath, contentType: "application/json" });
    }

    const nicheIndexPath = `${releaseBasePath}/niches/${nicheSlug}/index.json`;
    const nicheIndexFilePath = path.join(generatedRoot, "niches", nicheSlug, "index.json");
    writeJSON(nicheIndexFilePath, {
      releaseID,
      folder: niche.folder,
      title: manifest.niche,
      nicheSlug,
      sourcePage: manifest.sourcePage,
      slideshowCount: manifest.slideshowCount,
      totalSlideCount: manifest.totalSlideCount,
      pageSize,
      pageCount,
      pages
    });
    objects.push({ key: nicheIndexPath, filePath: nicheIndexFilePath, contentType: "application/json" });

    return {
      folder: niche.folder,
      title: manifest.niche,
      nicheSlug,
      sourcePage: manifest.sourcePage,
      slideshowCount: manifest.slideshowCount,
      totalSlideCount: manifest.totalSlideCount,
      pageSize,
      pageCount
    };
  });

  const indexPath = path.join(generatedRoot, "index.json");
  writeJSON(indexPath, {
    releaseID,
    basePath: releaseBasePath,
    pageSize,
    updatedAt: sourceIndex.updatedAt,
    niches
  });
  objects.push({ key: `${releaseBasePath}/index.json`, filePath: indexPath, contentType: "application/json" });
  return objects;
}

function ensureBucket() {
  const list = runWrangler(["r2", "bucket", "list"], { stdio: "pipe" });
  if (list.includes(bucket)) {
    return;
  }
  console.log(`Bucket ${bucket} not found in wrangler list; creating it.`);
  runWrangler(["r2", "bucket", "create", bucket]);
}

async function uploadAll(objects) {
  let nextIndex = 0;
  let completed = 0;
  const workers = Array.from({ length: Math.min(concurrency, objects.length) }, async () => {
    while (nextIndex < objects.length) {
      const object = objects[nextIndex];
      nextIndex += 1;
      await putObject(object.key, object.filePath, object.contentType);
      completed += 1;
      if (completed === objects.length || completed % 25 === 0) {
        console.log(`Uploaded ${completed}/${objects.length} release objects`);
      }
    }
  });
  await Promise.all(workers);
}

async function putObject(key, filePath, contentType) {
  await runWranglerAsync([
    "r2",
    "object",
    "put",
    `${bucket}/${key}`,
    "--remote",
    "--file",
    filePath,
    "--content-type",
    contentType
  ]);
}

async function verifyObject(key) {
  const verifyPath = path.join(generatedRoot, `verify-${createHash("sha1").update(key).digest("hex")}`);
  await runWranglerAsync(["r2", "object", "get", `${bucket}/${key}`, "--remote", "--file", verifyPath]);
  const stats = statSync(verifyPath);
  if (stats.size <= 0) {
    fail(`Verification failed for ${key}: downloaded file was empty.`);
  }
}

function runWrangler(args, options = {}) {
  const output = execFileSync("npx", ["wrangler", ...args], {
    cwd: repoRoot,
    encoding: "utf8",
    stdio: options.stdio ?? "inherit"
  });
  return output ?? "";
}

async function runWranglerAsync(args) {
  await execFileAsync("npx", ["wrangler", ...args], {
    cwd: repoRoot,
    encoding: "utf8",
    maxBuffer: 32 * 1024 * 1024
  });
}

function listFiles(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      return listFiles(entryPath);
    }
    return entry.name === ".DS_Store" ? [] : [entryPath];
  });
}

function hashFiles(files) {
  const hash = createHash("sha256");
  for (const filePath of [...files].sort()) {
    hash.update(relativePOSIX(sourceRoot, filePath));
    hash.update("\0");
    hash.update(readFileSync(filePath));
    hash.update("\0");
  }
  return hash.digest("hex");
}

function readJSON(filePath) {
  return JSON.parse(readFileSync(filePath, "utf8"));
}

function writeJSON(filePath, value) {
  execFileSync("mkdir", ["-p", path.dirname(filePath)]);
  writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function relativePOSIX(from, to) {
  return path.relative(from, to).split(path.sep).join("/");
}

function contentTypeFor(filePath) {
  switch (path.extname(filePath).toLowerCase()) {
  case ".json":
    return "application/json";
  case ".jpg":
  case ".jpeg":
    return "image/jpeg";
  case ".png":
    return "image/png";
  case ".webp":
    return "image/webp";
  default:
    return "application/octet-stream";
  }
}

function defaultReleaseID() {
  return new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z");
}

function stringArg(name) {
  const index = process.argv.indexOf(name);
  if (index === -1) {
    return undefined;
  }
  return process.argv[index + 1];
}

function numberArg(name, fallback) {
  const value = stringArg(name);
  if (!value) {
    return fallback;
  }
  const number = Number(value);
  if (!Number.isInteger(number) || number <= 0) {
    fail(`${name} must be a positive integer.`);
  }
  return number;
}

function fail(message) {
  console.error(message);
  process.exit(1);
}

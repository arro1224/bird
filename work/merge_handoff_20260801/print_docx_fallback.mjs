import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { chromium } from "playwright";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "..", "..");
const outputDir = path.join(repoRoot, "qa", "merge_handoff_20260801", "docx_fallback");
const htmlName = fs.readdirSync(outputDir).find((name) => name.endsWith(".html"));
if (!htmlName) throw new Error(`No fallback HTML found in ${outputDir}`);
const htmlPath = path.join(outputDir, htmlName);
const pdfPath = path.join(outputDir, `${path.basename(htmlName, ".html")}-fallback.pdf`);

const browser = await chromium.launch({
  headless: true,
  executablePath: "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
});
try {
  const page = await browser.newPage({ viewport: { width: 1400, height: 1000 }, deviceScaleFactor: 1 });
  await page.goto(pathToFileURL(htmlPath).href, { waitUntil: "load" });
  await page.pdf({
    path: pdfPath,
    preferCSSPageSize: true,
    printBackground: true,
    displayHeaderFooter: false,
  });
  console.log(pdfPath);
} finally {
  await browser.close();
}

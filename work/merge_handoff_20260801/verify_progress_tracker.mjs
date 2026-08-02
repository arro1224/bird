import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "..", "..");
const workbookPath = path.join(repoRoot, "outputs", "merge_handoff_20260801", "birdpart2_项目合并进度表_2026-08-01.xlsx");
const qaDir = path.join(repoRoot, "qa", "merge_handoff_20260801", "xlsx_final");
await fs.mkdir(qaDir, { recursive: true });

const workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(workbookPath));
const sheetScan = await workbook.inspect({ kind: "sheet", include: "id,name" });
const summary = await workbook.inspect({ kind: "table", sheetId: "总览", range: "A1:N38", include: "values,formulas", maxChars: 14000 });
const errorScan = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 200 },
  summary: "final formula error scan",
});
await fs.writeFile(
  path.join(qaDir, "final_workbook_inspect.json"),
  JSON.stringify({ sheets_ndjson: sheetScan.ndjson, summary_ndjson: summary.ndjson, errors_ndjson: errorScan.ndjson }, null, 2),
  "utf8",
);

for (const sheetName of ["总览", "进度计划", "对接矩阵", "风险问题", "里程碑", "来源清单"]) {
  const preview = await workbook.render({ sheetName, autoCrop: "all", scale: 1, format: "png" });
  await fs.writeFile(path.join(qaDir, `${sheetName}.png`), new Uint8Array(await preview.arrayBuffer()));
}

console.log(workbookPath);

import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "..", "..");
const data = JSON.parse(await fs.readFile(path.join(here, "merge_plan_data.json"), "utf8"));
const outputDir = path.join(repoRoot, "outputs", "merge_handoff_20260801");
const qaDir = path.join(repoRoot, "qa", "merge_handoff_20260801", "xlsx");
const outputPath = path.join(outputDir, "birdpart2_项目合并进度表_2026-08-01.xlsx");
await fs.mkdir(outputDir, { recursive: true });
await fs.mkdir(qaDir, { recursive: true });

const COLORS = {
  navy: "#17365D",
  blue: "#2E74B5",
  darkBlue: "#1F4D78",
  paleBlue: "#EAF2F8",
  green: "#70AD47",
  paleGreen: "#E2F0D9",
  amber: "#FFC000",
  paleAmber: "#FFF2CC",
  red: "#C65911",
  paleRed: "#FCE4D6",
  gray: "#F2F4F7",
  border: "#CBD5E1",
  text: "#202124",
  muted: "#5F6B76",
  white: "#FFFFFF",
};

const wb = Workbook.create();
const summary = wb.worksheets.add("总览");
const progress = wb.worksheets.add("进度计划");
const matrix = wb.worksheets.add("对接矩阵");
const risks = wb.worksheets.add("风险问题");
const milestones = wb.worksheets.add("里程碑");
const sources = wb.worksheets.add("来源清单");

for (const sheet of [summary, progress, matrix, risks, milestones, sources]) {
  sheet.showGridLines = false;
}

function asDate(value) {
  if (!value) return null;
  const [y, m, d] = value.split("-").map(Number);
  return new Date(y, m - 1, d, 12, 0, 0);
}

function titleBlock(sheet, lastColumn, title, subtitle) {
  sheet.mergeCells(`A1:${lastColumn}1`);
  sheet.getRange("A1").values = [[title]];
  sheet.getRange(`A1:${lastColumn}1`).format = {
    fill: COLORS.navy,
    font: { bold: true, color: COLORS.white, size: 18 },
    verticalAlignment: "center",
    horizontalAlignment: "left",
  };
  sheet.getRange(`A1:${lastColumn}1`).format.rowHeight = 34;
  sheet.mergeCells(`A2:${lastColumn}2`);
  sheet.getRange("A2").values = [[subtitle]];
  sheet.getRange(`A2:${lastColumn}2`).format = {
    fill: COLORS.paleBlue,
    font: { color: COLORS.darkBlue, size: 10 },
    verticalAlignment: "center",
    horizontalAlignment: "left",
    wrapText: true,
  };
  sheet.getRange(`A2:${lastColumn}2`).format.rowHeight = 28;
}

function styleHeader(range) {
  range.format = {
    fill: COLORS.darkBlue,
    font: { bold: true, color: COLORS.white, size: 10 },
    verticalAlignment: "center",
    horizontalAlignment: "center",
    wrapText: true,
    borders: {
      bottom: { color: COLORS.blue, style: "continuous", weight: 1 },
    },
  };
  range.format.rowHeight = 28;
}

function bodyStyle(range, { wrap = true, size = 9 } = {}) {
  range.format = {
    font: { color: COLORS.text, size },
    verticalAlignment: "center",
    wrapText: wrap,
  };
}

function applyStatusConditional(range, firstRow) {
  range.conditionalFormats.addCustom(`=$F${firstRow}="已完成"`, {
    fill: COLORS.paleGreen,
    font: { color: "#375623", bold: true },
  });
  range.conditionalFormats.addCustom(`=$F${firstRow}="进行中"`, {
    fill: COLORS.paleAmber,
    font: { color: "#7F6000", bold: true },
  });
  range.conditionalFormats.addCustom(`=$F${firstRow}="阻塞"`, {
    fill: COLORS.paleRed,
    font: { color: "#9C0006", bold: true },
  });
  range.conditionalFormats.addCustom(`=$F${firstRow}="待开始"`, {
    fill: COLORS.gray,
    font: { color: COLORS.muted, bold: true },
  });
}

function setWidths(sheet, entries) {
  for (const [col, width] of entries) {
    sheet.getRange(`${col}:${col}`).format.columnWidth = width;
  }
}

// ---------------- 总览 ----------------
titleBlock(
  summary,
  "N",
  "birdpart2 项目合并进度总览",
  `基线 ${data.meta.baseline_date}｜${data.meta.branch}@${data.meta.head.slice(0, 12)}｜契约 ${data.meta.contract}｜建议完成 ${data.meta.proposed_finish}`,
);
summary.getRange("A4:N4").format.rowHeight = 8;

const kpiLabels = [["总任务数"], ["已完成"], ["进行中"], ["阻塞"]];
for (const [idx, col] of ["A", "D", "G", "J"].entries()) {
  summary.mergeCells(`${col}5:${String.fromCharCode(col.charCodeAt(0) + 1)}5`);
  summary.getRange(`${col}5`).values = [[kpiLabels[idx][0]]];
  summary.getRange(`${col}5:${String.fromCharCode(col.charCodeAt(0) + 1)}5`).format = {
    fill: COLORS.paleBlue,
    font: { bold: true, color: COLORS.darkBlue, size: 10 },
    horizontalAlignment: "center",
    verticalAlignment: "center",
  };
  summary.mergeCells(`${col}6:${String.fromCharCode(col.charCodeAt(0) + 1)}7`);
  summary.getRange(`${col}6:${String.fromCharCode(col.charCodeAt(0) + 1)}7`).format = {
    fill: idx === 1 ? COLORS.paleGreen : idx === 2 ? COLORS.paleAmber : idx === 3 ? COLORS.paleRed : COLORS.gray,
    font: { bold: true, color: COLORS.navy, size: 22 },
    horizontalAlignment: "center",
    verticalAlignment: "center",
  };
}
summary.getRange("A6").formulas = [["=COUNTA('进度计划'!$A$5:$A$47)"]];
summary.getRange("D6").formulas = [["=COUNTIF('进度计划'!$F$5:$F$47,\"已完成\")"]];
summary.getRange("G6").formulas = [["=COUNTIF('进度计划'!$F$5:$F$47,\"进行中\")"]];
summary.getRange("J6").formulas = [["=COUNTIF('进度计划'!$F$5:$F$47,\"阻塞\")"]];

summary.mergeCells("A9:C9");
summary.getRange("A9").values = [["加权总体进度"]];
summary.mergeCells("A10:C11");
summary.getRange("A10").formulas = [["=SUM('进度计划'!$I$5:$I$47)/SUM('进度计划'!$H$5:$H$47)"]];
summary.getRange("A10:C11").format = {
  fill: COLORS.navy,
  font: { bold: true, color: COLORS.white, size: 24 },
  numberFormat: "0.0%",
  horizontalAlignment: "center",
  verticalAlignment: "center",
};

const secondaryKpis = [
  ["D9:F9", "D10:F11", "剩余权重", "=1-A10", "0.0%", COLORS.paleAmber],
  ["G9:I9", "G10:I11", "极高风险", "=COUNTIF('风险问题'!$H$5:$H$15,\"极高\")", "0", COLORS.paleRed],
  ["J9:L9", "J10:L11", "发布状态", null, "@", COLORS.gray],
];
for (const [labelRange, valueRange, label, formula, format, fill] of secondaryKpis) {
  summary.mergeCells(labelRange);
  summary.getRange(labelRange.split(":")[0]).values = [[label]];
  summary.getRange(labelRange).format = {
    fill: COLORS.paleBlue,
    font: { bold: true, color: COLORS.darkBlue, size: 10 },
    horizontalAlignment: "center",
    verticalAlignment: "center",
  };
  summary.mergeCells(valueRange);
  if (formula) summary.getRange(valueRange.split(":")[0]).formulas = [[formula]];
  else summary.getRange(valueRange.split(":")[0]).values = [["NO-GO"]];
  summary.getRange(valueRange).format = {
    fill,
    font: { bold: true, color: COLORS.navy, size: 18 },
    numberFormat: format,
    horizontalAlignment: "center",
    verticalAlignment: "center",
  };
}

summary.getRange("A13:F13").values = [["批次", "主题", "权重", "已获权重", "进度", "判定"]];
styleHeader(summary.getRange("A13:F13"));
for (let i = 0; i < data.batches.length; i += 1) {
  const row = 14 + i;
  const batch = data.batches[i];
  summary.getRange(`A${row}:B${row}`).values = [[batch.batch, batch.name]];
  summary.getRange(`C${row}`).formulas = [[`=SUMIF('进度计划'!$B$5:$B$47,A${row},'进度计划'!$H$5:$H$47)`]];
  summary.getRange(`D${row}`).formulas = [[`=SUMIF('进度计划'!$B$5:$B$47,A${row},'进度计划'!$I$5:$I$47)`]];
  summary.getRange(`E${row}`).formulas = [[`=IFERROR(D${row}/C${row},0)`]];
  summary.getRange(`F${row}`).formulas = [[`=IF(COUNTIFS('进度计划'!$B$5:$B$47,A${row},'进度计划'!$F$5:$F$47,\"阻塞\")>0,\"外部阻塞\",IF(E${row}=1,\"已完成\",\"进行中\"))`]];
}
bodyStyle(summary.getRange("A14:F21"), { size: 9 });
summary.getRange("C14:D21").format.numberFormat = "0.00";
summary.getRange("E14:E21").format.numberFormat = "0.0%";
summary.getRange("E14:E21").conditionalFormats.add("colorScale", {
  colors: [COLORS.paleRed, COLORS.paleAmber, COLORS.paleGreen],
  thresholds: ["min", "50%", "max"],
});
summary.getRange("F14:F21").conditionalFormats.addCustom('=$F14="已完成"', { fill: COLORS.paleGreen, font: { color: "#375623", bold: true } });
summary.getRange("F14:F21").conditionalFormats.addCustom('=$F14="进行中"', { fill: COLORS.paleAmber, font: { color: "#7F6000", bold: true } });
summary.getRange("F14:F21").conditionalFormats.addCustom('=$F14="外部阻塞"', { fill: COLORS.paleRed, font: { color: "#9C0006", bold: true } });

summary.getRange("H13:I13").values = [["状态", "数量"]];
styleHeader(summary.getRange("H13:I13"));
const statusRows = [["已完成"], ["进行中"], ["阻塞"], ["待开始"]];
for (let i = 0; i < statusRows.length; i += 1) {
  const row = 14 + i;
  summary.getRange(`H${row}`).values = [[statusRows[i][0]]];
  summary.getRange(`I${row}`).formulas = [[`=COUNTIF('进度计划'!$F$5:$F$47,H${row})`]];
}
bodyStyle(summary.getRange("H14:I17"));

summary.mergeCells("A23:F24");
summary.getRange("A23").values = [["关键路径：T04 真盒基线 → B3 鉴权 → B4 任务 → B5 相册审阅 → B6 复制日志 → T41 真盒证据 → T42 签名 → T43 发布决策"]];
summary.getRange("A23:F24").format = {
  fill: COLORS.paleBlue,
  font: { bold: true, color: COLORS.darkBlue, size: 10 },
  wrapText: true,
  verticalAlignment: "center",
  horizontalAlignment: "left",
};
summary.mergeCells("H19:N21");
summary.getRange("H19").values = [["发布硬门：strict baseline、11 项真盒 E2E、正式签名验签、干净工作区。任何一项未通过，结果均为 NO-GO。"]];
summary.getRange("H19:N21").format = {
  fill: COLORS.paleRed,
  font: { bold: true, color: "#9C0006", size: 10 },
  wrapText: true,
  verticalAlignment: "center",
  horizontalAlignment: "left",
};

summary.mergeCells("H36:N38");
summary.getRange("H36").values = [["当前结论：客户端主结构已合并，真实盒子基线、真盒 E2E、正式签名和当前树完整复跑尚未闭环，因此只允许继续联调，不允许正式发布。"]];
summary.getRange("H36:N38").format = {
  fill: COLORS.paleAmber,
  font: { bold: true, color: "#7F6000", size: 10 },
  wrapText: true,
  verticalAlignment: "center",
  horizontalAlignment: "left",
};
summary.freezePanes.freezeRows(2);
setWidths(summary, [["A", 12], ["B", 24], ["C", 11], ["D", 12], ["E", 12], ["F", 16], ["G", 3], ["H", 14], ["I", 10], ["J", 13], ["K", 10], ["L", 11], ["M", 3], ["N", 12]]);

// ---------------- 进度计划 ----------------
titleBlock(progress, "R", "项目合并实施进度计划", "绿色=已完成；黄色=进行中；红色=阻塞。修改完成度和权重后，加权进度会自动更新。计划日期为建议值。 ");
const progressHeaders = ["ID", "批次", "工作域", "工作项", "来源", "状态", "完成度", "权重", "加权完成", "优先级", "计划开始", "计划结束", "实际完成", "Owner", "依赖", "交付物", "验收标准", "证据 / 差距"];
progress.getRange("A4:R4").values = [progressHeaders];
styleHeader(progress.getRange("A4:R4"));
const firstTaskRow = 5;
const lastTaskRow = firstTaskRow + data.tasks.length - 1;
for (let i = 0; i < data.tasks.length; i += 1) {
  const row = firstTaskRow + i;
  const t = data.tasks[i];
  progress.getRange(`A${row}:H${row}`).values = [[t.id, t.batch, t.area, t.task, t.source, t.status, t.progress, t.weight]];
  progress.getRange(`I${row}`).formulas = [[`=G${row}*H${row}`]];
  progress.getRange(`J${row}:R${row}`).values = [[t.priority, asDate(t.planned_start), asDate(t.planned_end), asDate(t.actual_end), t.owner, t.dependency, t.deliverable, t.acceptance, `${t.evidence}\n差距：${t.gap}`]];
}
bodyStyle(progress.getRange(`A5:R${lastTaskRow}`), { size: 9 });
progress.getRange(`A5:C${lastTaskRow}`).format.horizontalAlignment = "center";
progress.getRange(`F5:J${lastTaskRow}`).format.horizontalAlignment = "center";
progress.getRange(`G5:G${lastTaskRow}`).format.numberFormat = "0%";
progress.getRange(`H5:I${lastTaskRow}`).format.numberFormat = "0.00";
progress.getRange(`K5:M${lastTaskRow}`).format.numberFormat = "yyyy-mm-dd";
progress.getRange(`A5:R${lastTaskRow}`).format.rowHeight = 46;
progress.getRange(`F5:F${lastTaskRow}`).dataValidation = { rule: { type: "list", values: ["已完成", "进行中", "阻塞", "待开始"] } };
progress.getRange(`G5:G${lastTaskRow}`).dataValidation = { rule: { type: "decimal", operator: "between", formula1: 0, formula2: 1 } };
progress.getRange(`J5:J${lastTaskRow}`).dataValidation = { rule: { type: "list", values: ["P0", "P1", "P2"] } };
applyStatusConditional(progress.getRange(`F5:F${lastTaskRow}`), firstTaskRow);
progress.getRange(`G5:G${lastTaskRow}`).conditionalFormats.add("dataBar", { color: COLORS.blue, thresholds: ["min", "max"] });
progress.getRange(`I5:I${lastTaskRow}`).conditionalFormats.add("dataBar", { color: COLORS.green, thresholds: ["min", "max"] });
const progressTable = progress.tables.add(`A4:R${lastTaskRow}`, true, "MergeProgressTable");
progressTable.style = "TableStyleMedium2";
progressTable.showBandedRows = true;
progress.freezePanes.freezeRows(4);
progress.freezePanes.freezeColumns(3);
setWidths(progress, [["A", 8], ["B", 8], ["C", 12], ["D", 39], ["E", 16], ["F", 11], ["G", 10], ["H", 9], ["I", 11], ["J", 9], ["K", 12], ["L", 12], ["M", 12], ["N", 24], ["O", 18], ["P", 24], ["Q", 34], ["R", 50]]);

// ---------------- 对接矩阵 ----------------
titleBlock(matrix, "H", "功能与模块对接矩阵", "描述功能从哪个页面/控制器出发，经哪些 Repository/Core，到达哪条协议或盒子能力。 ");
matrix.getRange("A4:H4").values = [["ID", "业务链路", "起点模块", "目标模块", "怎么对接", "协议/数据", "状态", "差距"]];
styleHeader(matrix.getRange("A4:H4"));
for (let i = 0; i < data.interfaces.length; i += 1) {
  const row = 5 + i;
  const x = data.interfaces[i];
  matrix.getRange(`A${row}:H${row}`).values = [[x.id, x.flow, x.source_module, x.target_module, x.mechanism, x.protocol, x.status, x.gap]];
}
const lastInterfaceRow = 4 + data.interfaces.length;
bodyStyle(matrix.getRange(`A5:H${lastInterfaceRow}`), { size: 9 });
matrix.getRange(`A5:A${lastInterfaceRow}`).format.horizontalAlignment = "center";
matrix.getRange(`G5:G${lastInterfaceRow}`).format.horizontalAlignment = "center";
matrix.getRange(`A5:H${lastInterfaceRow}`).format.rowHeight = 58;
matrix.getRange(`G5:G${lastInterfaceRow}`).conditionalFormats.addCustom('=$G5="已接入"', { fill: COLORS.paleGreen, font: { color: "#375623", bold: true } });
matrix.getRange(`G5:G${lastInterfaceRow}`).conditionalFormats.addCustom('=ISNUMBER(SEARCH("客户端",$G5))', { fill: COLORS.paleAmber, font: { color: "#7F6000", bold: true } });
matrix.getRange(`G5:G${lastInterfaceRow}`).conditionalFormats.addCustom('=$G5="部分一致"', { fill: COLORS.paleRed, font: { color: "#9C0006", bold: true } });
const matrixTable = matrix.tables.add(`A4:H${lastInterfaceRow}`, true, "IntegrationMatrixTable");
matrixTable.style = "TableStyleMedium2";
matrix.freezePanes.freezeRows(4);
matrix.freezePanes.freezeColumns(2);
setWidths(matrix, [["A", 8], ["B", 18], ["C", 30], ["D", 32], ["E", 45], ["F", 25], ["G", 20], ["H", 36]]);

// ---------------- 风险问题 ----------------
titleBlock(risks, "L", "风险与问题清单", "风险分数=发生概率×影响（1-5）。20-25 极高，12-19 高，6-11 中，1-5 低。 ");
risks.getRange("A4:L4").values = [["ID", "分类", "风险", "触发条件", "概率", "影响", "分数", "等级", "Owner", "缓解措施", "状态", "截止日"]];
styleHeader(risks.getRange("A4:L4"));
for (let i = 0; i < data.risks.length; i += 1) {
  const row = 5 + i;
  const risk = data.risks[i];
  risks.getRange(`A${row}:F${row}`).values = [[risk.id, risk.category, risk.risk, risk.trigger, risk.probability, risk.impact]];
  risks.getRange(`G${row}`).formulas = [[`=E${row}*F${row}`]];
  risks.getRange(`H${row}`).formulas = [[`=IF(G${row}>=20,\"极高\",IF(G${row}>=12,\"高\",IF(G${row}>=6,\"中\",\"低\")))`]];
  risks.getRange(`I${row}:L${row}`).values = [[risk.owner, risk.mitigation, risk.status, asDate(risk.due)]];
}
const lastRiskRow = 4 + data.risks.length;
bodyStyle(risks.getRange(`A5:L${lastRiskRow}`), { size: 9 });
risks.getRange(`A5:B${lastRiskRow}`).format.horizontalAlignment = "center";
risks.getRange(`E5:H${lastRiskRow}`).format.horizontalAlignment = "center";
risks.getRange(`K5:L${lastRiskRow}`).format.horizontalAlignment = "center";
risks.getRange(`L5:L${lastRiskRow}`).format.numberFormat = "yyyy-mm-dd";
risks.getRange(`A5:L${lastRiskRow}`).format.rowHeight = 58;
risks.getRange(`E5:F${lastRiskRow}`).dataValidation = { rule: { type: "whole", operator: "between", formula1: 1, formula2: 5 } };
risks.getRange(`K5:K${lastRiskRow}`).dataValidation = { rule: { type: "list", values: ["开放", "处理中", "已关闭"] } };
risks.getRange(`G5:G${lastRiskRow}`).conditionalFormats.add("colorScale", { colors: [COLORS.paleGreen, COLORS.paleAmber, COLORS.paleRed], thresholds: ["min", "50%", "max"] });
risks.getRange(`H5:H${lastRiskRow}`).conditionalFormats.addCustom('=$H5="极高"', { fill: COLORS.paleRed, font: { color: "#9C0006", bold: true } });
risks.getRange(`H5:H${lastRiskRow}`).conditionalFormats.addCustom('=$H5="高"', { fill: "#F4B183", font: { color: "#833C0C", bold: true } });
risks.getRange(`H5:H${lastRiskRow}`).conditionalFormats.addCustom('=$H5="中"', { fill: COLORS.paleAmber, font: { color: "#7F6000", bold: true } });
const riskTable = risks.tables.add(`A4:L${lastRiskRow}`, true, "MergeRiskTable");
riskTable.style = "TableStyleMedium2";
risks.freezePanes.freezeRows(4);
risks.freezePanes.freezeColumns(2);
setWidths(risks, [["A", 8], ["B", 12], ["C", 44], ["D", 35], ["E", 8], ["F", 8], ["G", 9], ["H", 9], ["I", 26], ["J", 45], ["K", 11], ["L", 12]]);

// ---------------- 里程碑 ----------------
titleBlock(milestones, "F", "项目合并里程碑", "里程碑日期是建议目标；实际承诺应在真实盒子、联系人和联调窗口补齐后冻结。 ");
milestones.getRange("A4:F4").values = [["ID", "里程碑", "计划日期", "进度", "状态", "完成条件"]];
styleHeader(milestones.getRange("A4:F4"));
for (let i = 0; i < data.milestones.length; i += 1) {
  const row = 5 + i;
  const m = data.milestones[i];
  milestones.getRange(`A${row}:F${row}`).values = [[m.id, m.name, asDate(m.planned), m.progress, m.status, m.criteria]];
}
const lastMilestoneRow = 4 + data.milestones.length;
bodyStyle(milestones.getRange(`A5:F${lastMilestoneRow}`), { size: 9 });
milestones.getRange(`A5:A${lastMilestoneRow}`).format.horizontalAlignment = "center";
milestones.getRange(`C5:E${lastMilestoneRow}`).format.horizontalAlignment = "center";
milestones.getRange(`C5:C${lastMilestoneRow}`).format.numberFormat = "yyyy-mm-dd";
milestones.getRange(`D5:D${lastMilestoneRow}`).format.numberFormat = "0%";
milestones.getRange(`D5:D${lastMilestoneRow}`).conditionalFormats.add("dataBar", { color: COLORS.blue, thresholds: ["min", "max"] });
milestones.getRange(`E5:E${lastMilestoneRow}`).conditionalFormats.addCustom('=$E5="已完成"', { fill: COLORS.paleGreen, font: { color: "#375623", bold: true } });
milestones.getRange(`E5:E${lastMilestoneRow}`).conditionalFormats.addCustom('=$E5="进行中"', { fill: COLORS.paleAmber, font: { color: "#7F6000", bold: true } });
milestones.getRange(`E5:E${lastMilestoneRow}`).conditionalFormats.addCustom('=$E5="阻塞"', { fill: COLORS.paleRed, font: { color: "#9C0006", bold: true } });
milestones.getRange(`A5:F${lastMilestoneRow}`).format.rowHeight = 46;
const milestoneTable = milestones.tables.add(`A4:F${lastMilestoneRow}`, true, "MilestoneTable");
milestoneTable.style = "TableStyleMedium2";
milestones.freezePanes.freezeRows(4);
setWidths(milestones, [["A", 9], ["B", 32], ["C", 14], ["D", 11], ["E", 12], ["F", 72]]);

// ---------------- 来源清单 ----------------
titleBlock(sources, "E", "资料来源与可追溯清单", "交接资料、当前契约、历史证据和 live working tree 共同组成 2026-08-01 实施基线。 ");
sources.getRange("A4:E4").values = [["ID", "资料", "类型", "路径", "用途"]];
styleHeader(sources.getRange("A4:E4"));
for (let i = 0; i < data.sources.length; i += 1) {
  const row = 5 + i;
  const s = data.sources[i];
  sources.getRange(`A${row}:E${row}`).values = [[s.id, s.name, s.type, s.path, s.used_for]];
}
const lastSourceRow = 4 + data.sources.length;
bodyStyle(sources.getRange(`A5:E${lastSourceRow}`), { size: 9 });
sources.getRange(`A5:C${lastSourceRow}`).format.horizontalAlignment = "center";
sources.getRange(`A5:E${lastSourceRow}`).format.rowHeight = 50;
const sourceTable = sources.tables.add(`A4:E${lastSourceRow}`, true, "SourceTable");
sourceTable.style = "TableStyleMedium2";
sources.freezePanes.freezeRows(4);
setWidths(sources, [["A", 8], ["B", 32], ["C", 16], ["D", 90], ["E", 48]]);

// Inspect, render, and export.
const inspectPayload = {
  sheets_ndjson: (await wb.inspect({ kind: "sheet", include: "id,name" })).ndjson,
  summary_ndjson: (await wb.inspect({ kind: "table", sheetId: "总览", range: "A1:N38", include: "values,formulas", maxChars: 12000 })).ndjson,
  progress_ndjson: (await wb.inspect({ kind: "table", sheetId: "进度计划", range: `A1:R${lastTaskRow}`, include: "values,formulas", maxChars: 18000 })).ndjson,
  errors_ndjson: (await wb.inspect({ kind: "match", searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A", options: { useRegex: true, maxResults: 200 }, summary: "formula error scan" })).ndjson,
};
await fs.writeFile(path.join(qaDir, "workbook_inspect.json"), JSON.stringify(inspectPayload, null, 2), "utf8");

try {
  const xlsx = await SpreadsheetFile.exportXlsx(wb);
  await xlsx.save(outputPath);
} catch (error) {
  console.error("EXPORT_ERROR:", error?.message ?? String(error));
  process.exit(2);
}

for (const sheetName of ["总览", "进度计划", "对接矩阵", "风险问题", "里程碑", "来源清单"]) {
  const preview = await wb.render({ sheetName, autoCrop: "all", scale: 1, format: "png" });
  await fs.writeFile(path.join(qaDir, `${sheetName}.png`), new Uint8Array(await preview.arrayBuffer()));
}

console.log(outputPath);

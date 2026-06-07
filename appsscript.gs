// GBI Daily Ops Report — Google Apps Script Backend
// ─────────────────────────────────────────────────
// DEPLOY INSTRUCTIONS:
//   1. Open your Google Sheet → Extensions → Apps Script
//   2. Delete any existing code, paste this entire file
//   3. Click Deploy → New deployment
//   4. Type: Web App
//   5. Execute as: Me
//   6. Who has access: Anyone
//   7. Click Deploy → copy the Web App URL
//   8. In the GBI app, go to Admin → "📊 Connect Sheets" → paste the URL

const SHEET_NAME = "Reports";

function getSheet() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sheet = ss.getSheetByName(SHEET_NAME);
  if (!sheet) {
    sheet = ss.insertSheet(SHEET_NAME);
    sheet.appendRow(["id","roleId","roleLabel","reporter","date","submittedAt","data"]);
    sheet.setFrozenRows(1);
    sheet.getRange("A1:G1").setFontWeight("bold");
  }
  return sheet;
}

function doGet(e) {
  const action = (e.parameter && e.parameter.action) || "list";

  if (action === "list") {
    return listReports();
  }
  if (action === "delete") {
    return deleteReport(e.parameter.id);
  }
  if (action === "clear") {
    return clearReports();
  }
  return json({ error: "Unknown action" });
}

function doPost(e) {
  try {
    const payload = JSON.parse(e.postData.contents);
    if (payload.action === "save" || !payload.action) {
      return saveReport(payload);
    }
  } catch(err) {
    return json({ error: err.message });
  }
  return json({ error: "Unknown action" });
}

function listReports() {
  const sheet = getSheet();
  const lastRow = sheet.getLastRow();
  if (lastRow <= 1) return json([]);

  const rows = sheet.getRange(2, 1, lastRow - 1, 7).getValues();
  const reports = rows
    .filter(r => r[0] !== "")
    .map(r => {
      try { return JSON.parse(r[6]); } catch { return null; }
    })
    .filter(Boolean);

  return json(reports);
}

function saveReport(record) {
  const sheet = getSheet();
  sheet.appendRow([
    record.id || "",
    record.roleId || "",
    record.roleLabel || "",
    record.reporter || "",
    record.date || "",
    record.submittedAt || "",
    JSON.stringify(record)
  ]);
  return json({ success: true, id: record.id });
}

function deleteReport(id) {
  if (!id) return json({ error: "No id provided" });
  const sheet = getSheet();
  const lastRow = sheet.getLastRow();
  if (lastRow <= 1) return json({ success: true });

  const ids = sheet.getRange(2, 1, lastRow - 1, 1).getValues();
  for (let i = ids.length - 1; i >= 0; i--) {
    if (ids[i][0] == id) {
      sheet.deleteRow(i + 2);
      break;
    }
  }
  return json({ success: true });
}

function clearReports() {
  const sheet = getSheet();
  const lastRow = sheet.getLastRow();
  if (lastRow > 1) sheet.deleteRows(2, lastRow - 1);
  return json({ success: true });
}

function json(data) {
  return ContentService
    .createTextOutput(JSON.stringify(data))
    .setMimeType(ContentService.MimeType.JSON);
}

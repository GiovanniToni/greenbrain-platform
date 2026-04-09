type AnyObj = Record<string, any>;

function safeSheetName(name: string): string {
  // Excel limits sheet name to 31 chars and forbids: : \ / ? * [ ]
  const cleaned = name.replace(/[:\\\/\?\*\[\]]/g, "-");
  return cleaned.length > 31 ? cleaned.slice(0, 31) : cleaned;
}

export async function exportToXlsx(
  filenameBase: string,
  sheets: { name: string; rows: AnyObj[] }[],
) {
  const XLSX = await import("xlsx");
  const wb = XLSX.utils.book_new();

  for (const s of sheets) {
    const ws = XLSX.utils.json_to_sheet(s.rows ?? []);
    XLSX.utils.book_append_sheet(wb, ws, safeSheetName(s.name));
  }

  const filename = filenameBase.toLowerCase().endsWith(".xlsx")
    ? filenameBase
    : `${filenameBase}.xlsx`;

  XLSX.writeFile(wb, filename, { compression: true });
}

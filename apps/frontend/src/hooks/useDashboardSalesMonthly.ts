import { useEffect, useState } from "react";
import { apiGet } from "@/lib/apiClient";

export type SalesMonthRow = { data: string; imp_tot: number };

function isoDay(v: any) {
  return String(v ?? "").slice(0, 10);
}

export function useDashboardSalesMonthly() {
  const [rows, setRows] = useState<SalesMonthRow[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      setLoading(true);
      let resp: any;
      try {
        resp = await apiGet("/api/v1/dashboard/sales-monthly");
      } catch (error: any) {
        console.error("sales monthly error:", error.message);
        setRows([]);
        setLoading(false);
        return;
      }

      setRows(
        ((resp?.items) ?? []).map((r: any) => ({
          data: isoDay(r.data),
          imp_tot: Number(r.imp_tot ?? 0) || 0,
        })),
      );
      setLoading(false);
    })();
  }, []);

  return { rows, loading };
}

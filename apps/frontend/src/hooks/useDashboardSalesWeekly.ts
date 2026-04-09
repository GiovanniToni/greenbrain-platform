import { useEffect, useState } from "react";
import { apiGet } from "@/lib/apiClient";

export type SalesWeekRow = { data: string; imp_tot: number };

function isoDay(v: any) {
  return String(v ?? "").slice(0, 10);
}

export function useDashboardSalesWeekly() {
  const [rows, setRows] = useState<SalesWeekRow[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      setLoading(true);

      let resp: any;
      try {
        resp = await apiGet("/api/v1/dashboard/sales-weekly");
      } catch (error: any) {
        console.error("sales weekly error:", error.message);
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

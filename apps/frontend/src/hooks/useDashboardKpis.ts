import { useEffect, useState } from "react";
import { apiGet } from "@/lib/apiClient";

interface DashboardKpis {
  reordersWeek: number;
  stockOutRisk: number;
  salesWeek: number;
  salesTrend: number | null;
  forecast14d: number;
  productsMonitored: number;

  reorderRiskLines: number;
  reorderQtyTot: number;

  // ✅ NEW
  salesYtd: number;
  salesYtdTrend: number | null;
}

export function useDashboardKpis() {
  const [kpis, setKpis] = useState<DashboardKpis>({
    reordersWeek: 0,
    stockOutRisk: 0,
    salesWeek: 0,
    salesTrend: null,
    forecast14d: 0,
    productsMonitored: 0,
    reorderRiskLines: 0,
    reorderQtyTot: 0,

    salesYtd: 0,
    salesYtdTrend: null,
  });
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      setLoading(true);

      let row: any;
      try {
        row = await apiGet("/api/v1/dashboard/kpis");
      } catch (error: any) {
        console.error("dashboard kpis error:", error.message);
        setLoading(false);
        return;
      }

      setKpis({
        reordersWeek: Number(row?.reorder_lines ?? 0) || 0,
        stockOutRisk: Number(row?.stock_out_risk ?? 0) || 0,
        salesWeek: Number(row?.sales_week ?? 0) || 0,
        salesTrend: row?.sales_trend == null ? null : Number(row.sales_trend),
        forecast14d: Number(row?.forecast_14d ?? 0) || 0,
        productsMonitored: Number(row?.products_monitored ?? 0) || 0,
        reorderRiskLines: Number(row?.reorder_risk_lines ?? 0) || 0,
        reorderQtyTot: Number(row?.reorder_qty_tot ?? 0) || 0,

        // ✅ NEW
        salesYtd: Number(row?.sales_ytd ?? 0) || 0,
        salesYtdTrend: row?.sales_ytd_trend == null ? null : Number(row.sales_ytd_trend),
      });

      setLoading(false);
    })();
  }, []);

  return { kpis, loading };
}

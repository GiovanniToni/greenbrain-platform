// src/hooks/useAnalyticsStockAndReorder.ts
import { useCallback, useState } from "react";
import { apiGet } from "@/lib/apiClient";

export type StockAndReorder = {
  stockQty: number | null;
  reorderQty: number | null;
};

function n(v: any): number {
  const x = Number(v);
  return Number.isFinite(x) ? x : 0;
}

export function useAnalyticsStockAndReorder() {
  const [data, setData] = useState<StockAndReorder | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(
    async (params: { entityType: string; entityKey: string; fasciaPrezzo?: string | null }) => {
      const { entityType, entityKey, fasciaPrezzo } = params;

      if (!entityType || !entityKey) {
        setData(null);
        return;
      }

      setLoading(true);
      setError(null);

      try {
        const row = await apiGet("/api/v1/analytics/stock-and-reorder", {
          entity_type: entityType,
          entity_key: entityKey,
          ...(fasciaPrezzo != null && { fascia_prezzo: fasciaPrezzo }),
        });

        const stockQty = row?.stock_qty == null ? null : n(row.stock_qty);
        const reorderQty = row?.reorder_qty == null ? null : n(row.reorder_qty);

        setData({ stockQty, reorderQty });
      } catch (e: any) {
        const msg = e?.message || `${e}` || "Errore stock/riordino";
        setError(msg);
        setData(null);
      } finally {
        setLoading(false);
      }
    },
    [],
  );

  return { data, loading, error, refetch };
}

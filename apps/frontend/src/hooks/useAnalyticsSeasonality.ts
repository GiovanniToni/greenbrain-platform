import { useState, useCallback } from "react";
import { apiGet } from "@/lib/apiClient";

export interface SeasonalityDataPoint {
  month_num: number;
  month_name: string;
  avg_qty_per_day: number;
  sum_qty: number;
  avg_rev_per_day?: number;
  sum_rev?: number;
  n_days?: number;
}

interface SeasonalityParams {
  entityType: string;
  entityKey: string;
}

const MONTH_NAMES = ["Gen", "Feb", "Mar", "Apr", "Mag", "Giu", "Lug", "Ago", "Set", "Ott", "Nov", "Dic"];

function normKey(v: any): string {
  return String(v ?? "")
    .trim()
    .toLowerCase();
}

export function useAnalyticsSeasonality() {
  const [data, setData] = useState<SeasonalityDataPoint[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(async (params: SeasonalityParams) => {
    const { entityType, entityKey } = params;

    // niente seasonality per articolo (se vuoi aggiungerla dopo, togli questa guard)
    if (!entityType || !entityKey || entityType === "articolo") {
      setData([]);
      return;
    }

    const k = normKey(entityKey);

    setLoading(true);
    setError(null);

    try {
      const resp = await apiGet("/api/v1/analytics/seasonality", {
        entity_type: entityType,
        entity_key: k,
      });

      const rows = ((resp?.items) || []) as any[];

      // indicizza per mese (nel DB è già unico, ma così riempiamo i mesi mancanti con 0)
      const byMonth = new Map<number, any>();
      rows.forEach((r) => byMonth.set(Number(r.month_num), r));

      const result: SeasonalityDataPoint[] = [];
      for (let i = 1; i <= 12; i++) {
        const r = byMonth.get(i);
        result.push({
          month_num: i,
          month_name: MONTH_NAMES[i - 1],
          avg_qty_per_day: r ? Number(r.avg_qty_per_day ?? 0) : 0,
          sum_qty: r ? Number(r.sum_qty ?? 0) : 0,
          avg_rev_per_day: r ? Number(r.avg_rev_per_day ?? 0) : 0,
          sum_rev: r ? Number(r.sum_rev ?? 0) : 0,
          n_days: r ? Number(r.n_days ?? 0) : 0,
        });
      }

      setData(result);
    } catch (err) {
      console.error("Seasonality error:", err);
      setError("Errore nel caricamento della stagionalità");
      setData([]);
    } finally {
      setLoading(false);
    }
  }, []);

  return { data, loading, error, refetch };
}

import { useState, useCallback } from "react";
import { apiGet } from "@/lib/apiClient";

export interface WeeklySeasonalityDataPoint {
  dow: number;
  day_name: string;
  avg_qty_per_day: number;
  sum_qty: number;
  avg_rev_per_day?: number;
  sum_rev?: number;
  n_days?: number;
}

interface Params {
  entityType: string;
  entityKey: string;
  fasciaPrezzo?: string | null;
}

const DAYS = ["Dom", "Lun", "Mar", "Mer", "Gio", "Ven", "Sab"];

export function useAnalyticsWeeklySeasonality() {
  const [data, setData] = useState<WeeklySeasonalityDataPoint[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(async ({ entityType, entityKey, fasciaPrezzo }: Params) => {
    if (!entityType || !entityKey) {
      setData([]);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const resp = await apiGet("/api/v1/analytics/seasonality-weekly", {
        entity_type: entityType,
        entity_key: String(entityKey).trim().toLowerCase(),
        ...(fasciaPrezzo ? { fascia_prezzo: fasciaPrezzo } : {}),
      });

      const rows = ((resp?.items) || []) as any[];
      const byDow = new Map<number, any>();
      rows.forEach((r) => byDow.set(Number(r.dow), r));

      setData(
        DAYS.map((name, dow) => {
          const r = byDow.get(dow);
          return {
            dow,
            day_name: name,
            avg_qty_per_day: r ? Number(r.avg_qty_per_day ?? 0) : 0,
            sum_qty: r ? Number(r.sum_qty ?? 0) : 0,
            avg_rev_per_day: r ? Number(r.avg_rev_per_day ?? 0) : 0,
            sum_rev: r ? Number(r.sum_rev ?? 0) : 0,
            n_days: r ? Number(r.n_days ?? 0) : 0,
          };
        })
      );
    } catch (e) {
      console.error("Weekly seasonality error:", e);
      setError("Errore nel caricamento della stagionalità settimanale");
      setData([]);
    } finally {
      setLoading(false);
    }
  }, []);

  return { data, loading, error, refetch };
}

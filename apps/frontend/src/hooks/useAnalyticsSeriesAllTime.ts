import { useCallback, useState } from "react";
import { apiGet } from "@/lib/apiClient";

interface Params {
  entityType: string;
  entityKey: string;
}

export interface SeriesBounds {
  min: string | null; // YYYY-MM-DD
  max: string | null; // YYYY-MM-DD
}

function isoDay(v: any) {
  return String(v ?? "").slice(0, 10);
}

function normKey(v: any): string {
  return String(v ?? "")
    .trim()
    .toLowerCase();
}

export function useAnalyticsSeriesAllTime() {
  const [bounds, setBounds] = useState<SeriesBounds>({ min: null, max: null });
  const [loadingAll, setLoadingAll] = useState(false);
  const [errorAll, setErrorAll] = useState<string | null>(null);

  const refetchAll = useCallback(async ({ entityType, entityKey }: Params) => {
    if (!entityType || !entityKey) {
      setBounds({ min: null, max: null });
      setErrorAll(null);
      setLoadingAll(false);
      return;
    }

    setLoadingAll(true);
    setErrorAll(null);

    try {
      const row = await apiGet("/api/v1/analytics/series-bounds", {
        entity_type: entityType,
        granularity: "day",
        entity_key: entityType === "articolo" ? String(entityKey).trim() : normKey(entityKey),
      });

      setBounds({
        min: row?.min_date ? isoDay(row.min_date) : null,
        max: row?.max_date ? isoDay(row.max_date) : null,
      });
    } catch (e: any) {
      setErrorAll(e?.message ?? "Errore caricamento bounds storico");
      setBounds({ min: null, max: null });
    } finally {
      setLoadingAll(false);
    }
  }, []);

  return { bounds, loadingAll, errorAll, refetchAll };
}

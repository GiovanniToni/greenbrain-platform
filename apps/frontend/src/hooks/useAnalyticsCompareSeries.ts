import { useState, useCallback } from "react";
import { apiGet } from "@/lib/apiClient";

export interface CompareItem {
  entity_type: "famiglia" | "categoria" | "fascia";
  entity_key: string;
  label: string;
}

export interface CompareDataPoint {
  data: string;
  qty: number;
  forecast: number | null;
}

export interface CompareSeries {
  key: string;
  label: string;
  entity_type: "famiglia" | "categoria" | "fascia";
  points: CompareDataPoint[];
}

interface CompareParams {
  items: CompareItem[];
  dateFrom: string;
  dateTo: string;
}

export function useAnalyticsCompareSeries() {
  const [series, setSeries] = useState<CompareSeries[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(async (params: CompareParams) => {
    const { items, dateFrom, dateTo } = params;

    if (!items || items.length === 0) {
      setSeries([]);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const promises = items.map(async (item) => {
        const resp = await apiGet("/api/v1/analytics/compare-series", {
          entity_type: item.entity_type,
          entity_key: item.entity_key,
          date_from: dateFrom,
          date_to: dateTo,
        });

        const points: CompareDataPoint[] = ((resp?.items || []) as any[]).map((row) => ({
          data: row.data,
          qty: parseFloat(row.qty_venduta_tot) || 0,
          forecast: row.qty_forecast_tot != null ? parseFloat(row.qty_forecast_tot) : null,
        }));

        return {
          key: `${item.entity_type}__${item.entity_key}`,
          label: item.label,
          entity_type: item.entity_type,
          points,
        };
      });

      const results = await Promise.all(promises);
      setSeries(results);
    } catch (err) {
      console.error("Compare series error:", err);
      setError(err instanceof Error ? err.message : "Errore nel caricamento delle serie di confronto");
      setSeries([]);
    } finally {
      setLoading(false);
    }
  }, []);

  return { series, loading, error, refetch };
}

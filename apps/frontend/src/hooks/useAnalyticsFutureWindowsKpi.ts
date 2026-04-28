// src/hooks/useAnalyticsFutureWindowsKpi.ts
import { useCallback, useRef, useState } from "react";
import { apiGet } from "@/lib/apiClient";

export type FutureWindowRow = {
  window_days: number;
  min_qty: number;
  max_qty: number;
  avg_qty: number;
};

function isoDay(v: any): string {
  return String(v ?? "").slice(0, 10);
}

function n(v: any): number {
  const x = Number(v);
  return Number.isFinite(x) ? x : 0;
}

function normKey(v: any): string {
  return String(v ?? "")
    .trim()
    .toLowerCase();
}

type RefetchParams = {
  entityType: string;
  entityKey: string;
  anchorTo: string; // ✅ fondamentale: userai l'anchorTo calcolato in Analytics.tsx
  windows?: number[]; // opzionale: default [7,14,30,60]
  famiglia?: string | null; // compat (ignorato in v2)
  fasciaPrezzo?: string | null;
};

export function useAnalyticsFutureWindowsKpi() {
  const [rows, setRows] = useState<FutureWindowRow[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // evita race conditions: l'ultima richiesta vince
  const reqIdRef = useRef(0);

  const refetch = useCallback(async (params: RefetchParams) => {
    const reqId = ++reqIdRef.current;

    const entityType = params?.entityType;
    const entityKey = params?.entityKey;
    const anchorTo = isoDay(params?.anchorTo);
    const fasciaPrezzo = String(params?.fasciaPrezzo ?? "").trim();

    const windows = (params?.windows && params.windows.length > 0 ? params.windows : [7, 14, 30, 60])
      .map((x) => Number(x))
      .filter((x) => Number.isFinite(x) && x > 0);

    if (!entityType || !entityKey || !anchorTo) {
      if (reqId !== reqIdRef.current) return;
      setRows([]);
      setError(null);
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const resp = await apiGet("/api/v1/analytics/future-windows-stats", {
        entity_type: entityType,
        entity_key: normKey(entityKey),
        anchor_to: anchorTo,
        windows,
        ...(fasciaPrezzo && { fascia_prezzo: fasciaPrezzo }),
      });

      if (reqId !== reqIdRef.current) return;

      const out: FutureWindowRow[] = ((resp?.items ?? []) as any[]).map((r) => ({
        window_days: Number(r.window_days),
        min_qty: n(r.min_qty),
        max_qty: n(r.max_qty),
        avg_qty: n(r.avg_qty),
      }));

      // Ordina (nel dubbio)
      out.sort((a, b) => a.window_days - b.window_days);

      setRows(out);
    } catch (e: any) {
      if (reqId !== reqIdRef.current) return;
      const msg = e?.message || (typeof e === "string" ? e : null) || "Errore KPI future windows";
      setError(msg);
      setRows([]);
    } finally {
      if (reqId === reqIdRef.current) setLoading(false);
    }
  }, []);

  return { rows, loading, error, refetch };
}

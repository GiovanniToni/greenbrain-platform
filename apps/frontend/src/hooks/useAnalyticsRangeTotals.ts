// src/hooks/useAnalyticsRangeTotals.ts
import { useCallback, useRef, useState } from "react";
import { apiGet } from "@/lib/apiClient";

export type RangeTotals = {
  qty_tot: number;
  imp_tot: number;
  days: number;
  active_days: number;
  zero_days: number;
  min_day: string | null;
  min_qty: number;
  max_day: string | null;
  max_qty: number;
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

type Params = {
  entityType: string;
  entityKey: string;
  dateFrom: string;
  dateTo: string;

  // contesto opzionale (come in Series)
  fasciaPrezzo?: string | null; // label tipo "0 - 2,99€"
};

type Granularity = "day" | "week" | "month" | "year";

function pickBreakdownDaily(entityType: string) {
  if (entityType === "famiglia") return "core_analytics__breakdown_daily_famiglia_fp_v2";
  if (entityType === "categoria") return "core_analytics__breakdown_daily_categoria_fp_v2";
  if (entityType === "fascia") return "core_analytics__breakdown_daily_fascia_fp_v2";
  return null;
}

export function useAnalyticsRangeTotals() {
  const [data, setData] = useState<RangeTotals | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const reqIdRef = useRef(0);

  const clear = useCallback(() => {
    // ✅ invalida eventuali richieste in volo
    reqIdRef.current += 1;
    setData(null);
    setError(null);
    setLoading(false);
  }, []);

  const refetch = useCallback(async (params: Params) => {
    const reqId = ++reqIdRef.current;

    const entityType = params?.entityType;
    const entityKey = params?.entityKey;
    const dateFrom = isoDay(params?.dateFrom);
    const dateTo = isoDay(params?.dateTo);

    if (!entityType || !entityKey || !dateFrom || !dateTo) {
      if (reqId !== reqIdRef.current) return;
      setData(null);
      setError(null);
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      // ---- FP FILTER (famiglia/categoria/fascia) -> calcolo totals via breakdown daily ----
      const fp = String((params as any)?.fasciaPrezzo ?? "")
        .replace(/\u00A0/g, " ")
        .trim();
      const hasFpFilter = !!fp && (entityType === "famiglia" || entityType === "categoria" || entityType === "fascia");

      if (hasFpFilter) {
        const breakdownView = pickBreakdownDaily(entityType);
        if (!breakdownView) throw new Error(`Breakdown daily non disponibile per ${entityType}`);

        const _fpResp = await apiGet("/api/v1/analytics/series", {
          entity_type: entityType,
          granularity: "day",
          entity_key: normKey(entityKey),
          date_from: dateFrom,
          date_to: dateTo,
          fascia_prezzo: fp,
        });
        if (reqId !== reqIdRef.current) return;

        const rws = (_fpResp?.items ?? []) as any[];

        // aggregazione per giorno (nel daily dovrebbe già essere 1 riga/giorno per fp, ma facciamo safe)
        const byDay = new Map<string, { qty: number; imp: number }>();
        for (const r of rws) {
          const d = isoDay(r.data);
          const prev = byDay.get(d);
          const qty = n(r.qty_venduta);
          const imp = n(r.imponibile_netto_tot);
          if (!prev) byDay.set(d, { qty, imp });
          else {
            prev.qty += qty;
            prev.imp += imp;
          }
        }

        // range day-by-day: per coerenza con range_totals_v2 contiamo TUTTI i giorni del range,
        // non solo quelli presenti nella breakdown view.
        const start = Date.parse(dateFrom);
        const end = Date.parse(dateTo);
        const days = Math.floor((end - start) / 86400000) + 1;

        let qty_tot = 0;
        let imp_tot = 0;
        let active_days = 0;
        let zero_days = 0;

        let min_day: string | null = null;
        let min_qty = Number.POSITIVE_INFINITY;
        let max_day: string | null = null;
        let max_qty = Number.NEGATIVE_INFINITY;

        for (let i = 0; i < days; i++) {
          const d = new Date(start + i * 86400000);
          const iso = d.toISOString().slice(0, 10);
          const v = byDay.get(iso);
          const q = v?.qty ?? 0;
          const imp = v?.imp ?? 0;

          qty_tot += q;
          imp_tot += imp;

          if (q > 0) active_days++;
          if (q === 0) zero_days++;

          if (q < min_qty) {
            min_qty = q;
            min_day = iso;
          }
          if (q > max_qty) {
            max_qty = q;
            max_day = iso;
          }
        }

        setData({
          qty_tot,
          imp_tot,
          days,
          active_days,
          zero_days,
          min_day,
          min_qty: Number.isFinite(min_qty) ? min_qty : 0,
          max_day,
          max_qty: Number.isFinite(max_qty) ? max_qty : 0,
        });

        return; // IMPORTANT: non chiamare la RPC standard
      }
      const row = await apiGet("/api/v1/analytics/range-totals", {
        entity_type: entityType,
        entity_key: entityType === "articolo" ? String(entityKey).trim() : normKey(entityKey),
        date_from: dateFrom,
        date_to: dateTo,
      });
      if (reqId !== reqIdRef.current) return;

      setData({
        qty_tot: n(row?.qty_tot),
        imp_tot: n(row?.imp_tot),
        days: Number(row?.days ?? 0) || 0,
        active_days: Number(row?.active_days ?? 0) || 0,
        zero_days: Number(row?.zero_days ?? 0) || 0,
        min_day: row?.min_day ? isoDay(row.min_day) : null,
        min_qty: n(row?.min_qty),
        max_day: row?.max_day ? isoDay(row.max_day) : null,
        max_qty: n(row?.max_qty),
      });
    } catch (e: any) {
      if (reqId !== reqIdRef.current) return;
      const msg = e?.message || (typeof e === "string" ? e : null) || "Errore range totals";
      setError(msg);
      setData(null);
    } finally {
      if (reqId === reqIdRef.current) setLoading(false);
    }
  }, []);

  return { data, loading, error, refetch, clear };
}

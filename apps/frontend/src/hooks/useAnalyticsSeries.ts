// src/hooks/useAnalyticsSeries.ts
import { useState, useCallback, useRef } from "react";
import { apiGet } from "@/lib/apiClient";

export type Granularity = "day" | "week" | "month" | "year";
export type GranularityMode = Granularity | "auto";

export interface SeriesDataPoint {
  data: string; // YYYY-MM-DD (day OR bucket start)
  qty_venduta_tot: number;
  imponibile_netto_tot: number;
  qty_forecast_tot: number | null;
  dow: number; // meaningful only for day
  is_holiday: boolean; // meaningful only for day
  holiday_name: string | null; // meaningful only for day
}

export interface BreakdownDataPoint {
  data: string;
  fascia_prezzo_iva_inc: string;
  qty_venduta: number;
  qty_forecast: number | null;
  dow: number;
  is_holiday: boolean;
  holiday_name: string | null;
}

interface SeriesParams {
  entityType: string;
  entityKey: string;
  dateFrom: string;
  dateTo: string;
  includeBreakdown?: boolean;
  granularity?: GranularityMode;

  fascia?: string | null;
  categoria?: string | null;
  famiglia?: string | null;

  // label tipo "0 - 2,99€"
  fasciaPrezzo?: string | null;
}

function isoDay(v: any): string {
  return String(v ?? "").slice(0, 10);
}

function n(v: any): number {
  const x = Number(v);
  return Number.isFinite(x) ? x : 0;
}

function normKey(v: any): string {
  return String(v ?? "")
    .replace(/\u00A0/g, " ") // NBSP -> spazio normale
    .trim()
    .toLowerCase();
}

function daysDiff(from: string, to: string) {
  const a = Date.parse(from.slice(0, 10));
  const b = Date.parse(to.slice(0, 10));
  return Math.floor((b - a) / 86400000) + 1;
}

export function pickGranularityAuto(from: string, to: string): Granularity {
  const d = daysDiff(from, to);
  if (d > 4000) return "year";
  if (d > 2000) return "month";
  if (d > 1095) return "week";
  return "day";
}

const G_RANK: Record<Granularity, number> = { day: 0, week: 1, month: 2, year: 3 };

function maxGranularity(a: Granularity, b: Granularity): Granularity {
  return G_RANK[a] >= G_RANK[b] ? a : b;
}

export function resolveGranularity(from: string, to: string, requested: GranularityMode): Granularity {
  const autoG = pickGranularityAuto(from, to);
  if (requested === "auto") return autoG;
  return maxGranularity(requested, autoG);
}

// snap helpers
function parseISODate0(iso: string) {
  return new Date(`${isoDay(iso)}T00:00:00`);
}

function fmtISO(d: Date) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function startOfWeekMonISO(iso: string) {
  const d = parseISODate0(iso);
  const day = d.getDay();
  const diff = (day + 6) % 7;
  d.setDate(d.getDate() - diff);
  d.setHours(0, 0, 0, 0);
  return fmtISO(d);
}

function startOfMonthISO(iso: string) {
  const d = parseISODate0(iso);
  d.setDate(1);
  d.setHours(0, 0, 0, 0);
  return fmtISO(d);
}

function startOfYearISO(iso: string) {
  const d = parseISODate0(iso);
  d.setMonth(0, 1);
  d.setHours(0, 0, 0, 0);
  return fmtISO(d);
}

function snapRangeForGranularity(from: string, to: string, g: Granularity) {
  if (g === "year") return { from: startOfYearISO(from), to: startOfYearISO(to) };
  if (g === "month") return { from: startOfMonthISO(from), to: startOfMonthISO(to) };
  if (g === "week") return { from: startOfWeekMonISO(from), to: startOfWeekMonISO(to) };
  return { from, to };
}

function pickTotalSource(entityType: string, g: Granularity) {
  if (g === "day") {
    if (entityType === "famiglia") return "core_analytics__series_daily_famiglia_lc";
    if (entityType === "categoria") return "core_analytics__series_daily_categoria_lc";
    if (entityType === "fascia") return "core_analytics__series_daily_fascia_lc";
    if (entityType === "fascia_prezzo") return "core_analytics__series_daily_fascia_prezzo_lc";
  }
  if (g === "week") {
    if (entityType === "famiglia") return "core_analytics__series_weekly_famiglia_lc";
    if (entityType === "categoria") return "core_analytics__series_weekly_categoria_lc";
    if (entityType === "fascia") return "core_analytics__series_weekly_fascia_lc";
    if (entityType === "fascia_prezzo") return "core_analytics__series_weekly_fascia_prezzo_lc";
  }
  if (g === "month") {
    if (entityType === "famiglia") return "core_analytics__series_monthly_famiglia_lc";
    if (entityType === "categoria") return "core_analytics__series_monthly_categoria_lc";
    if (entityType === "fascia") return "core_analytics__series_monthly_fascia_lc";
    if (entityType === "fascia_prezzo") return "core_analytics__series_monthly_fascia_prezzo_lc";
  }
  if (g === "year") {
    if (entityType === "famiglia") return "core_analytics__series_yearly_famiglia_lc";
    if (entityType === "categoria") return "core_analytics__series_yearly_categoria_lc";
    if (entityType === "fascia") return "core_analytics__series_yearly_fascia_lc";
    if (entityType === "fascia_prezzo") return "core_analytics__series_yearly_fascia_prezzo_lc";
  }
  return null;
}

function pickBreakdownSource(entityType: string, g: Granularity) {
  if (g === "day") {
    if (entityType === "famiglia") return "core_analytics__breakdown_daily_famiglia_fp_v2";
    if (entityType === "categoria") return "core_analytics__breakdown_daily_categoria_fp_v2";
    if (entityType === "fascia") return "core_analytics__breakdown_daily_fascia_fp_v2";
    return null;
  }
  if (g === "week") {
    if (entityType === "famiglia") return "core_analytics__breakdown_weekly_famiglia_fp_v2";
    if (entityType === "categoria") return "core_analytics__breakdown_weekly_categoria_fp_v2";
    if (entityType === "fascia") return "core_analytics__breakdown_weekly_fascia_fp_v2";
    return null;
  }
  if (g === "month") {
    if (entityType === "famiglia") return "core_analytics__breakdown_monthly_famiglia_fp_v2";
    if (entityType === "categoria") return "core_analytics__breakdown_monthly_categoria_fp_v2";
    if (entityType === "fascia") return "core_analytics__breakdown_monthly_fascia_fp_v2";
    return null;
  }
  if (g === "year") {
    if (entityType === "famiglia") return "core_analytics__breakdown_yearly_famiglia_fp_v2";
    if (entityType === "categoria") return "core_analytics__breakdown_yearly_categoria_fp_v2";
    if (entityType === "fascia") return "core_analytics__breakdown_yearly_fascia_fp_v2";
    return null;
  }
  return null;
}

type AggRow = {
  data: string;
  qty: number;
  imp: number;
  forecast: number | null;
  dow: number;
  is_holiday: boolean;
  holiday_name: string | null;
};

function groupAgg(rows: any[], g: Granularity): SeriesDataPoint[] {
  const m = new Map<string, AggRow>();

  for (const r of rows) {
    const d = isoDay(r.data);
    const prev = m.get(d);

    const qty = n(r.qty_venduta ?? r.qty_venduta_tot ?? r.qty_tot);
    // ✅ imponibile: presente nel DAILY cat/fam e nella MV fascia; nelle weekly/monthly/yearly che hai incollato potrebbe NON esserci
    const imp = n(r.imponibile_netto_tot ?? r.imp_tot ?? 0);

    const fcRaw = r.qty_forecast ?? r.qty_forecast_tot;
    const forecast = fcRaw == null ? null : n(fcRaw);

    const dow = g === "day" ? Number(r.dow ?? 0) : 0;
    const is_holiday = g === "day" ? !!r.is_holiday : false;
    const holiday_name = g === "day" ? (r.holiday_name ?? null) : null;

    if (!prev) {
      m.set(d, { data: d, qty, imp, forecast, dow, is_holiday, holiday_name });
    } else {
      prev.qty += qty;
      prev.imp += imp;

      // forecast: se almeno uno non-null sommo, altrimenti resta null
      if (prev.forecast == null && forecast == null) {
        prev.forecast = null;
      } else {
        prev.forecast = (prev.forecast ?? 0) + (forecast ?? 0);
      }

      // dow/is_holiday/holiday_name: per day restano coerenti (stessa data)
      // per safety:
      prev.is_holiday = prev.is_holiday || is_holiday;
      if (!prev.holiday_name && holiday_name) prev.holiday_name = holiday_name;
    }
  }

  return Array.from(m.values())
    .sort((a, b) => (a.data < b.data ? -1 : a.data > b.data ? 1 : 0))
    .map((x) => ({
      data: x.data,
      qty_venduta_tot: x.qty,
      imponibile_netto_tot: x.imp,
      qty_forecast_tot: x.forecast,
      dow: x.dow,
      is_holiday: x.is_holiday,
      holiday_name: x.holiday_name,
    }));
}

export function useAnalyticsSeries() {
  const [totalSeries, setTotalSeries] = useState<SeriesDataPoint[]>([]);
  const [breakdownSeries, setBreakdownSeries] = useState<BreakdownDataPoint[]>([]);
  const [granularity, setGranularity] = useState<Granularity>("day");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const reqIdRef = useRef(0);

  const refetch = useCallback(async (params: SeriesParams) => {
    const { entityType, entityKey, dateFrom, dateTo, includeBreakdown } = params;
    const reqId = ++reqIdRef.current;

    const from = isoDay(dateFrom);
    const to = isoDay(dateTo);

    if (!entityType || !entityKey || !from || !to) {
      if (reqId !== reqIdRef.current) return;
      setTotalSeries([]);
      setBreakdownSeries([]);
      return;
    }

    const requested = params?.granularity ?? "auto";
    const g: Granularity = entityType === "articolo" ? "day" : resolveGranularity(from, to, requested);
    setGranularity(g);

    const fp = String(params?.fasciaPrezzo ?? "")
      .replace(/\u00A0/g, " ")
      .trim();

    const hasFpFilter = !!fp && (entityType === "famiglia" || entityType === "categoria" || entityType === "fascia");

    const snapped = snapRangeForGranularity(from, to, g);
    const qFrom = snapped.from;
    const qTo = snapped.to;

    setLoading(true);
    setError(null);

    try {
      // ---- ARTICOLO ----
      if (entityType === "articolo") {
        const _artResp = await apiGet("/api/v1/analytics/series", {
          entity_type: "articolo",
          granularity: "day",
          entity_key: entityKey,
          date_from: from,
          date_to: to,
        });
        if (reqId !== reqIdRef.current) return;

        const rows = (_artResp?.items ?? []) as any[];
        setTotalSeries(
          rows.map((r) => ({
            data: isoDay(r.data),
            qty_venduta_tot: n(r.qty_venduta),
            imponibile_netto_tot: n(r.imponibile_netto),
            qty_forecast_tot: r.qty_forecast != null ? n(r.qty_forecast) : null,
            dow: Number(r.dow ?? 0),
            is_holiday: !!r.is_holiday,
            holiday_name: r.holiday_name ?? null,
          })),
        );
        setBreakdownSeries([]);
        return;
      }

      // ---- FP FILTER (famiglia/categoria/fascia) ----
      // Con il tuo DB: il modo corretto è leggere dalla breakdown view e aggregare per data.
      if (hasFpFilter) {
        const breakdownView = pickBreakdownSource(entityType, g);
        if (!breakdownView) throw new Error(`Breakdown non disponibile per ${entityType} @ ${g}`);

        const _fpResp = await apiGet("/api/v1/analytics/series", {
          entity_type: entityType,
          granularity: g,
          entity_key: normKey(entityKey),
          date_from: g === "day" ? from : qFrom,
          date_to: g === "day" ? to : qTo,
          fascia_prezzo: fp,
        });
        if (reqId !== reqIdRef.current) return;

        const agg = groupAgg((_fpResp?.items ?? []) as any[], g);
        setTotalSeries(agg);

        // quando filtro per fp, breakdown non ha senso (sei già su un solo fp)
        setBreakdownSeries([]);
        return;
      }

      // ---- NORMAL TOTAL SERIES ----
      const totalView = pickTotalSource(entityType, g);
      if (!totalView) throw new Error(`EntityType non supportato: ${entityType}`);

      const _totResp = await apiGet("/api/v1/analytics/series", {
        entity_type: entityType,
        granularity: g,
        entity_key: normKey(entityKey),
        date_from: g === "day" ? from : qFrom,
        date_to: g === "day" ? to : qTo,
      });
      if (reqId !== reqIdRef.current) return;

      const totRows = (_totResp?.items ?? []) as any[];

      setTotalSeries(
        totRows.map((r) => ({
          data: isoDay(r.data),
          qty_venduta_tot: n(r.qty_venduta_tot),
          imponibile_netto_tot: n(r.imponibile_netto_tot),
          qty_forecast_tot: r.qty_forecast_tot != null ? n(r.qty_forecast_tot) : null,
          dow: g === "day" ? Number(r.dow ?? 0) : 0,
          is_holiday: g === "day" ? !!r.is_holiday : false,
          holiday_name: g === "day" ? (r.holiday_name ?? null) : null,
        })),
      );

      // ---- BREAKDOWN (solo se richiesto, e non su fascia_prezzo/articolo) ----
      const breakdownAllowed = entityType === "famiglia" || entityType === "categoria" || entityType === "fascia";
      if (!includeBreakdown || !breakdownAllowed) {
        setBreakdownSeries([]);
        return;
      }

      const breakdownView = pickBreakdownSource(entityType, g);
      if (!breakdownView) {
        setBreakdownSeries([]);
        return;
      }

      let _bResp: any;
      try {
        _bResp = await apiGet("/api/v1/analytics/series-breakdown", {
          entity_type: entityType,
          granularity: g,
          entity_key: normKey(entityKey),
          date_from: g === "day" ? from : qFrom,
          date_to: g === "day" ? to : qTo,
        });
      } catch (bErr: any) {
        console.error("Breakdown fetch error:", bErr);
        if (reqId !== reqIdRef.current) return;
        setBreakdownSeries([]);
        return;
      }
      if (reqId !== reqIdRef.current) return;

      const bRows = (_bResp?.items ?? []) as any[];

      setBreakdownSeries(
        bRows.map((r) => ({
          data: isoDay(r.data),
          fascia_prezzo_iva_inc: r.fascia_prezzo_iva_inc,
          qty_venduta: n(r.qty_venduta),
          qty_forecast: r.qty_forecast != null ? n(r.qty_forecast) : null,
          dow: g === "day" ? Number(r.dow ?? 0) : 0,
          is_holiday: g === "day" ? !!r.is_holiday : false,
          holiday_name: g === "day" ? (r.holiday_name ?? null) : null,
        })),
      );
    } catch (e: any) {
      console.error("Series error:", e);
      if (reqId !== reqIdRef.current) return;

      const msg = e?.message || (typeof e === "string" ? e : null) || "Errore nel caricamento delle serie";
      setError(msg);
      setTotalSeries([]);
      setBreakdownSeries([]);
    } finally {
      if (reqId === reqIdRef.current) setLoading(false);
    }
  }, []);

  return { totalSeries, breakdownSeries, granularity, loading, error, refetch };
}

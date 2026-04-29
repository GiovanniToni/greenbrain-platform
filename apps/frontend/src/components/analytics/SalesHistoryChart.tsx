// src/components/analytics/SalesHistoryChart.tsx
import { useEffect, useMemo, useState } from "react";
import { apiGet } from "@/lib/apiClient";
import { Card } from "@/components/ui/card";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import {
  ComposedChart,
  Bar,
  Cell,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
  ReferenceDot,
  ReferenceLine,
  Legend,
} from "recharts";
import { SeriesDataPoint, BreakdownDataPoint, Granularity, GranularityMode } from "@/hooks/useAnalyticsSeries";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { DateField } from "@/components/analytics/DateField";

type DayFilter = "ALL" | "WEEKEND" | "SAT" | "SUN" | "HOLIDAYS_ONLY";

interface SalesHistoryChartProps {
  data: SeriesDataPoint[];
  breakdownData: BreakdownDataPoint[];

  showBreakdown: boolean;
  onToggleBreakdown: (value: boolean) => void;

  dateFrom: string;
  dateTo: string;

  onDateRangeChange: (range: { from: string; to: string }) => void;

  anchorTo?: string;
  minAvailableDate?: string;

  dayFilter: DayFilter;
  onDayFilterChange: (v: DayFilter) => void;

  holidayNameFilter: string;
  onHolidayNameFilterChange: (v: string) => void;

  onResetControls: () => void;

  granularity?: Granularity;

  granularityMode: GranularityMode;
  onGranularityModeChange: (v: GranularityMode) => void;

  granularityModeSelectValue?: GranularityMode;

  granularitySelectDisabled?: boolean;

  entityType: string;
  entityKey: string;
  fasciaPrezzo?: string | null;
}

const FASCIA_COLORS = [
  "hsl(142, 45%, 35%)",
  "hsl(200, 60%, 50%)",
  "hsl(280, 50%, 55%)",
  "hsl(35, 80%, 50%)",
  "hsl(350, 60%, 55%)",
  "hsl(170, 50%, 45%)",
];

const FORECAST_HORIZON_DAYS = 10;

function parseISODate(iso: string) {
  return new Date(`${String(iso).slice(0, 10)}T00:00:00`);
}

function formatISO(d: Date) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function isoDay(v: any) {
  return String(v ?? "").slice(0, 10);
}

function addDaysISO(iso: string, days: number) {
  const d = parseISODate(iso);
  d.setDate(d.getDate() + days);
  return formatISO(d);
}

function maxISO(a: string, b: string) {
  return a >= b ? a : b;
}

function buildDailyRange(fromISO: string, toISO: string) {
  const from = isoDay(fromISO);
  const to = isoDay(toISO);
  if (!from || !to || from > to) return [];
  const out: string[] = [];
  let cur = from;
  while (cur <= to) {
    out.push(cur);
    cur = addDaysISO(cur, 1);
  }
  return out;
}

function startOfYear(d: Date) {
  return new Date(d.getFullYear(), 0, 1);
}

function addDays(d: Date, days: number) {
  const x = new Date(d);
  x.setDate(x.getDate() + days);
  return x;
}

function addMonths(d: Date, months: number) {
  const x = new Date(d);
  x.setMonth(x.getMonth() + months);
  return x;
}

function addYears(d: Date, years: number) {
  const x = new Date(d);
  x.setFullYear(x.getFullYear() + years);
  return x;
}

function norm(s: any) {
  return String(s ?? "")
    .trim()
    .toLowerCase();
}

const FASCIA_PREZZO_ORDER: string[] = [
  "0 - 2,99€",
  "3 - 4,99€",
  "5 - 9,99€",
  "10 - 14,99€",
  "15 - 19,99€",
  "20 - 24,99€",
  "25 - 29,99€",
  "30 - 39,99€",
  "40 - 49,99€",
  "50 - 59,99€",
  "60 - 69€",
  "70 - 99,99€",
  "100 - 149,99€",
  "150 - 199,99€",
  "200€ - >",
];

const FP_INDEX = new Map(FASCIA_PREZZO_ORDER.map((l, i) => [norm(l), i]));

// weekly/monthly/year buckets
function startOfWeekMon(d: Date) {
  const x = new Date(d);
  const day = x.getDay();
  const diff = (day + 6) % 7;
  x.setDate(x.getDate() - diff);
  x.setHours(0, 0, 0, 0);
  return x;
}

function buildWeeklyRange(fromISO: string, toISO: string) {
  const f = startOfWeekMon(parseISODate(fromISO));
  const t = startOfWeekMon(parseISODate(toISO));
  const out: string[] = [];
  let cur = new Date(f);
  while (cur <= t) {
    out.push(formatISO(cur));
    cur = addDays(cur, 7);
  }
  return out;
}

function buildMonthlyRange(fromISO: string, toISO: string) {
  const f = parseISODate(fromISO);
  const t = parseISODate(toISO);
  let cur = new Date(f.getFullYear(), f.getMonth(), 1);
  const end = new Date(t.getFullYear(), t.getMonth(), 1);
  const out: string[] = [];
  while (cur <= end) {
    out.push(formatISO(cur));
    cur = new Date(cur.getFullYear(), cur.getMonth() + 1, 1);
  }
  return out;
}

function buildYearlyRange(fromISO: string, toISO: string) {
  const f = parseISODate(fromISO);
  const t = parseISODate(toISO);
  let cur = new Date(f.getFullYear(), 0, 1);
  const end = new Date(t.getFullYear(), 0, 1);
  const out: string[] = [];
  while (cur <= end) {
    out.push(formatISO(cur));
    cur = new Date(cur.getFullYear() + 1, 0, 1);
  }
  return out;
}

function monthShortIT(d: Date) {
  return d.toLocaleDateString("it-IT", { month: "short" });
}

function isoWeekNumber(date: Date) {
  // ISO week number
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() + 3 - ((d.getDay() + 6) % 7));
  const week1 = new Date(d.getFullYear(), 0, 4);
  return 1 + Math.round(((d.getTime() - week1.getTime()) / 86400000 - 3 + ((week1.getDay() + 6) % 7)) / 7);
}

function formatDayMonth(d: Date) {
  return `${String(d.getDate()).padStart(2, "0")} ${monthShortIT(d)}`;
}

type TickLabel = { top: string; bottom?: string } | null;

/**
 * Label “esplicative” + anti-overlap:
 * - usiamo step dinamico (meno label quando ci sono tanti punti)
 * - e rendiamo visibile il contesto (mese/anno) ai cambi e ai bordi
 */
function makeTickLabel(
  iso: string,
  granularity: Granularity,
  prevISO: string | null,
  idx: number,
  step: number,
  isEdge: boolean,
): TickLabel {
  const d = parseISODate(iso);
  const p = prevISO ? parseISODate(prevISO) : null;

  const y = d.getFullYear();
  const m = d.getMonth();
  const day = d.getDate();

  const yearChanged = p ? y !== p.getFullYear() : true;
  const monthChanged = p ? m !== p.getMonth() : true;

  if (granularity === "year") {
    // pochi punti, sempre
    return { top: String(y) };
  }

  if (granularity === "month") {
    // top: MMM, bottom: YYYY (mostra sempre ai bordi e quando cambia anno, e altrimenti a step)
    const show = isEdge || yearChanged || idx % step === 0;
    if (!show) return null;
    return { top: monthShortIT(d), bottom: yearChanged || isEdge ? String(y) : "" };
  }

  if (granularity === "week") {
    const show = isEdge || idx % step === 0;
    if (!show) return null;

    const weekNo = isoWeekNumber(d);

    // solo week number sopra, anno sotto (solo a cambio anno o ai bordi)
    const bottomYear = yearChanged || isEdge ? String(y) : "";

    return {
      top: `W${String(weekNo).padStart(2, "0")}`,
      bottom: bottomYear,
    };
  }

  // day (NO anno qui: l'anno è sulla seconda XAxis "year")
  // - mostriamo solo "25 gen" a step regolari
  // - ai bordi lo mostriamo sempre
  if (!isEdge && idx % step !== 0) return null;

  return {
    top: `${String(day).padStart(2, "0")} ${monthShortIT(d)}`,
    bottom: "", // niente anno sotto
  };
}

function CustomXAxisTick(props: any) {
  const { x, y, payload, tickLabel, angle } = props as {
    x: number;
    y: number;
    payload: any;
    tickLabel: TickLabel;
    angle: number;
  };

  if (!tickLabel) return null;

  const top = tickLabel.top ?? "";
  const bottom = tickLabel.bottom ?? "";
  const hasBottom = bottom.trim().length > 0;

  // ruota attorno al punto (x,y) per comprimere e ridurre overlap
  // anchor "end" aiuta molto con angoli negativi
  const textAnchor = angle < 0 ? "end" : "middle";

  return (
    <g transform={`translate(${x},${y})`}>
      <text textAnchor={textAnchor} fill="currentColor" fontSize={11} transform={`rotate(${angle})`}>
        <tspan x={0} dy={hasBottom ? 0 : 4}>
          {top}
        </tspan>
        {hasBottom && (
          <tspan x={0} dy={14} fontSize={10} opacity={0.8}>
            {bottom}
          </tspan>
        )}
      </text>
    </g>
  );
}

export function SalesHistoryChart({
  data,
  breakdownData,
  showBreakdown,
  onToggleBreakdown,
  dateFrom,
  dateTo,
  onDateRangeChange,
  anchorTo,
  minAvailableDate,
  dayFilter,
  onDayFilterChange,
  holidayNameFilter,
  onHolidayNameFilterChange,
  onResetControls,
  granularity = "day",
  granularityMode,
  onGranularityModeChange,
  granularityModeSelectValue,
  granularitySelectDisabled,
  entityType,
  entityKey,
  fasciaPrezzo,
}: SalesHistoryChartProps) {
  const selectValue = granularityModeSelectValue ?? granularityMode;

  const anchorISO = (anchorTo ?? formatISO(new Date())).slice(0, 10);
  const anchorDate = useMemo(() => parseISODate(anchorISO), [anchorISO]);

  const [forecastV2ByDay, setForecastV2ByDay] = useState<Map<string, number>>(new Map());

  const keys = useMemo(() => {
    const from = isoDay(dateFrom);
    const to = isoDay(dateTo);
    if (!from || !to || from > to) return [];

    if (granularity === "day") {
      const fcEnd = addDaysISO(anchorISO, FORECAST_HORIZON_DAYS);
      const effectiveTo = maxISO(to, fcEnd);
      return buildDailyRange(from, effectiveTo);
    }

    if (granularity === "year") return buildYearlyRange(from, to);
    if (granularity === "month") return buildMonthlyRange(from, to);
    if (granularity === "week") return buildWeeklyRange(from, to);
    return buildDailyRange(from, to);
  }, [dateFrom, dateTo, granularity, anchorISO]);

  useEffect(() => {
    let cancelled = false;

    async function loadForecastV2() {
      // solo day
      if (granularity !== "day") {
        setForecastV2ByDay(new Map());
        return;
      }

      // la tabella è per famiglia (+ fascia prezzo): quindi la usiamo solo quando entityType=famiglia
      if (entityType !== "famiglia") {
        setForecastV2ByDay(new Map());
        return;
      }

      const from = isoDay(dateFrom);
      const to = isoDay(dateTo);
      if (!from || !to || from > to) {
        setForecastV2ByDay(new Map());
        return;
      }

      // NOTA: qui facciamo coincidere le date della query con l’asse (in day l’asse estende fino anchor+10)
      const fcEnd = addDaysISO(anchorISO, FORECAST_HORIZON_DAYS);
      const effectiveTo = maxISO(to, fcEnd);

      const fp = String(fasciaPrezzo ?? "").trim();
      let rows: any[];
      try {
        const resp = await apiGet("/api/v1/forecast/series", {
          famiglia: entityKey,
          date_from: from,
          date_to: effectiveTo,
          ...(fp && { fascia_prezzo: fp }),
        });
        rows = resp?.items ?? [];
      } catch (err) {
        console.error("Forecast v2 fetch error:", err);
        if (!cancelled) setForecastV2ByDay(new Map());
        return;
      }

      // aggrega per giorno:
      // - se fp è selezionata => avrai già una sola fascia (o comunque la somma è ok)
      // - se fp non è selezionata => sommi tutte le fasce per ottenere forecast totale famiglia
      const m = new Map<string, number>();
      for (const r of (rows || []) as any[]) {
        const d = String(r.data).slice(0, 10);
        const v = Number(r.qty_forecast);
        if (!Number.isFinite(v)) continue;
        m.set(d, (m.get(d) ?? 0) + v);
      }

      if (!cancelled) setForecastV2ByDay(m);
    }

    loadForecastV2();
    return () => {
      cancelled = true;
    };
  }, [granularity, entityType, entityKey, fasciaPrezzo, dateFrom, dateTo, anchorISO]);

  const keyIndex = useMemo(() => {
    const m = new Map<string, number>();
    (keys ?? []).forEach((k, i) => m.set(k, i));
    return m;
  }, [keys]);

  const yearSeparators = useMemo(() => {
    if (!keys || keys.length < 2) return [];
    const out: string[] = [];
    for (let i = 1; i < keys.length; i++) {
      const cur = parseISODate(keys[i]);
      const prev = parseISODate(keys[i - 1]);
      if (cur.getFullYear() !== prev.getFullYear()) out.push(keys[i]);
    }
    return out;
  }, [keys]);

  const yearCenters = useMemo(() => {
    if (!keys || keys.length === 0) return [];

    // raggruppa per anno
    const byYear = new Map<number, string[]>();
    keys.forEach((k) => {
      const y = parseISODate(k).getFullYear();
      if (!byYear.has(y)) byYear.set(y, []);
      byYear.get(y)!.push(k);
    });

    // centro = elemento a metà del range dell'anno
    return Array.from(byYear.entries())
      .sort((a, b) => a[0] - b[0])
      .map(([year, arr]) => {
        const mid = arr[Math.floor(arr.length / 2)];
        return { year, x: mid };
      });
  }, [keys]);

  // step + angle (anti overlap) dinamici
  const xAxisLayout = useMemo(() => {
    const total = keys.length;

    // step base (quante label saltare)
    const dayStep =
      total > 1200 ? 30 : total > 700 ? 14 : total > 400 ? 7 : total > 220 ? 5 : total > 120 ? 3 : total > 60 ? 2 : 1;

    const weekStep = total > 520 ? 10 : total > 260 ? 6 : total > 130 ? 3 : 1;
    const monthStep = total > 240 ? 6 : total > 120 ? 3 : total > 60 ? 2 : 1;

    const step =
      granularity === "day" ? dayStep : granularity === "week" ? weekStep : granularity === "month" ? monthStep : 1;

    // angolo: più denso => più inclinazione
    const angle =
      granularity === "week"
        ? total > 90
          ? -35
          : total > 60
            ? -25
            : -15
        : granularity === "day"
          ? total > 180
            ? -45
            : total > 90
              ? -35
              : -20
          : granularity === "month"
            ? total > 36
              ? -30
              : -15
            : 0;

    // altezza asse: serve spazio per 2 righe + rotazione
    const height = angle === 0 ? 46 : angle <= -40 ? 88 : angle <= -30 ? 78 : 66;

    return { step, angle, height };
  }, [keys, granularity]);

  const xTickLabelGetter = useMemo(() => {
    const { step } = xAxisLayout;

    return (v: any) => {
      const iso = String(v).slice(0, 10);
      const idx = keyIndex.get(iso);
      if (idx == null) return null;

      const prev = idx > 0 ? keys[idx - 1] : null;
      const isEdge = idx === 0 || idx === keys.length - 1;

      return makeTickLabel(iso, granularity, prev, idx, step, isEdge);
    };
  }, [keys, keyIndex, granularity, xAxisLayout]);

  const chartData = useMemo(() => {
    const rows = (data ?? []).map((d) => {
      const k = isoDay(d.data);
      const dt = parseISODate(k);
      const dow = granularity === "day" ? Number((d as any).dow ?? dt.getDay()) : 0;

      const dateLabel =
        granularity === "year"
          ? dt.toLocaleDateString("it-IT", { year: "numeric" })
          : granularity === "month"
            ? dt.toLocaleDateString("it-IT", { month: "short", year: "numeric" })
            : granularity === "week"
              ? (() => {
                  const end = addDays(dt, 6);
                  const w = isoWeekNumber(dt);
                  return `W${String(w).padStart(2, "0")} • ${formatDayMonth(dt)}–${formatDayMonth(end)} ${end.getFullYear()}`;
                })()
              : dt.toLocaleDateString("it-IT", { day: "2-digit", month: "short", year: "numeric" });

      return {
        ...d,
        data: k,
        isWeekend: granularity === "day" ? dow === 0 || dow === 6 : false,
        dateLabel,
      };
    });

    const byKey = new Map<string, any>(rows.map((r) => [r.data, r]));

    return keys.map((k) => {
      const existing = byKey.get(k);

      const base = existing
        ? existing
        : (() => {
            const dt = parseISODate(k);
            const dow = granularity === "day" ? dt.getDay() : 0;

            const dateLabel =
              granularity === "year"
                ? dt.toLocaleDateString("it-IT", { year: "numeric" })
                : granularity === "month"
                  ? dt.toLocaleDateString("it-IT", { month: "short", year: "numeric" })
                  : granularity === "week"
                    ? (() => {
                        const end = addDays(dt, 6);
                        const w = isoWeekNumber(dt);
                        return `W${String(w).padStart(2, "0")} • ${formatDayMonth(dt)}–${formatDayMonth(end)} ${end.getFullYear()}`;
                      })()
                    : dt.toLocaleDateString("it-IT", { day: "2-digit", month: "short", year: "numeric" });

            return {
              data: k,
              qty_venduta_tot: 0,
              imponibile_netto_tot: 0,
              qty_forecast_tot: null,
              dow,
              is_holiday: false,
              holiday_name: null,
              isWeekend: granularity === "day" ? dow === 0 || dow === 6 : false,
              dateLabel,
            };
          })();

      const fcV2 = forecastV2ByDay.get(k);
      const baseWithForecast = {
        ...base,
        qty_forecast_tot: fcV2 != null ? fcV2 : base.qty_forecast_tot,
      };

      if (granularity !== "day") {
        return {
          ...baseWithForecast,
          qty_forecast_shadow: baseWithForecast.qty_forecast_tot != null ? baseWithForecast.qty_forecast_tot : 0,
        };
      }

      const fcEnd = addDaysISO(anchorISO, FORECAST_HORIZON_DAYS);

      const isPastOrToday = k <= anchorISO;
      const isFuture = k > anchorISO;
      const isFutureWithinHorizon = isFuture && k <= fcEnd;

      const vendite = isPastOrToday ? Number(baseWithForecast.qty_venduta_tot ?? baseWithForecast.qty_venduta ?? 0) : 0;
      const fc = baseWithForecast.qty_forecast_tot != null ? Number(baseWithForecast.qty_forecast_tot) : null;

      return {
        ...baseWithForecast,
        qty_venduta_tot: vendite,
        qty_forecast_bar: isFutureWithinHorizon && fc != null ? fc : 0,
        qty_forecast_line: k === anchorISO ? vendite : isFuture ? fc : null,
        qty_forecast_shadow: isFutureWithinHorizon && fc != null ? fc : 0,
      };
    });
  }, [data, keys, granularity, anchorISO, forecastV2ByDay]);

  const holidays = useMemo(
    () => (granularity === "day" ? chartData.filter((d: any) => d.is_holiday) : []),
    [chartData, granularity],
  );

  const fasce = useMemo(() => {
    const set = new Set<string>();
    breakdownData.forEach((d) => set.add(d.fascia_prezzo_iva_inc));
    const arr = Array.from(set);
    return arr.sort((a, b) => {
      const ia = FP_INDEX.has(norm(a)) ? (FP_INDEX.get(norm(a)) as number) : 999;
      const ib = FP_INDEX.has(norm(b)) ? (FP_INDEX.get(norm(b)) as number) : 999;
      return ia - ib;
    });
  }, [breakdownData]);

  const breakdownByKey = useMemo(() => {
    if (!showBreakdown) return {};
    const map: Record<string, Record<string, number>> = {};
    breakdownData.forEach((d) => {
      const k = String(d.data).slice(0, 10);
      if (!map[k]) map[k] = {};
      map[k][d.fascia_prezzo_iva_inc] = Number(d.qty_venduta ?? 0);
    });
    return map;
  }, [breakdownData, showBreakdown]);

  const mergedData = useMemo(() => {
    return chartData.map((d: any) => {
      const extra: Record<string, number> = {};
      if (showBreakdown && fasce.length > 0) {
        fasce.forEach((f) => {
          extra[`fascia_${f}`] = (breakdownByKey as any)?.[d.data]?.[f] ?? 0;
        });
      }
      return { ...d, ...extra };
    });
  }, [chartData, showBreakdown, breakdownByKey, fasce]);

  const CustomTooltip = ({ active, payload }: any) => {
    if (!active || !payload?.length) return null;

    const point = payload[0]?.payload as any;

    const sorted = [...payload].sort((a: any, b: any) => {
      const rank = (name: string) => {
        if (name === "Vendite") return 0;
        if (name === "Trend atteso") return 1;
        if (name === "Forecast (10g)") return 2;
        if (name === "Forecast (shadow)") return 99;
        return 3;
      };
      return rank(a.name) - rank(b.name);
    });

    const cleaned = sorted.filter((p: any) => p.name !== "Forecast (shadow)");

    const vendite = cleaned.find((p: any) => p.name === "Vendite")?.value;
    const forecastLine = cleaned.find((p: any) => p.name === "Trend atteso")?.value;

    const hasBoth = typeof vendite === "number" && typeof forecastLine === "number" && vendite > 0;
    const deltaAbs = hasBoth ? forecastLine - vendite : null;
    const deltaPct = hasBoth ? ((forecastLine - vendite) / vendite) * 100 : null;

    return (
      <div className="bg-card border border-border rounded-lg p-3 shadow-lg">
        <p className="font-medium text-sm">{point?.dateLabel}</p>

        {granularity === "day" && point?.isWeekend && (
          <p className="text-xs text-muted-foreground font-medium">📅 Weekend</p>
        )}

        {granularity === "day" && point?.is_holiday && (
          <p className="text-xs text-amber-600 font-medium">🎉 {point?.holiday_name}</p>
        )}

        {cleaned.map((p: any, idx: number) => (
          <p key={idx} className="text-xs" style={{ color: p.color }}>
            {p.name}:{" "}
            {typeof p.value === "number" ? p.value.toLocaleString("it-IT", { maximumFractionDigits: 0 }) : "-"}
          </p>
        ))}

        {hasBoth && (
          <div className="mt-2 pt-2 border-t border-border">
            <p className="text-xs">
              Scostamento: {deltaAbs!.toLocaleString("it-IT", { maximumFractionDigits: 0 })} (
              {deltaPct! >= 0 ? "+" : ""}
              {deltaPct!.toLocaleString("it-IT", { maximumFractionDigits: 1 })}%)
            </p>
          </div>
        )}
      </div>
    );
  };

  const quickButtons = useMemo(
    () => [
      { k: "5G", fn: () => ({ from: formatISO(addDays(anchorDate, -5)), to: formatISO(anchorDate) }) },
      { k: "1M", fn: () => ({ from: formatISO(addMonths(anchorDate, -1)), to: formatISO(anchorDate) }) },
      { k: "3M", fn: () => ({ from: formatISO(addMonths(anchorDate, -3)), to: formatISO(anchorDate) }) },
      { k: "6M", fn: () => ({ from: formatISO(addMonths(anchorDate, -6)), to: formatISO(anchorDate) }) },
      { k: "YTD", fn: () => ({ from: formatISO(startOfYear(anchorDate)), to: formatISO(anchorDate) }) },
      { k: "1A", fn: () => ({ from: formatISO(addYears(anchorDate, -1)), to: formatISO(anchorDate) }) },
      { k: "5A", fn: () => ({ from: formatISO(addYears(anchorDate, -5)), to: formatISO(anchorDate) }) },
      {
        k: "Tutto",
        fn: () => ({ from: (minAvailableDate ?? "2009-01-01").slice(0, 10), to: formatISO(anchorDate) }),
      },
    ],
    [anchorDate, minAvailableDate],
  );

  if (!data || data.length === 0) {
    return (
      <Card className="p-6">
        <h3 className="text-sm font-medium text-muted-foreground mb-4">Storico Vendite</h3>
        <div className="h-64 flex items-center justify-center text-muted-foreground">
          Nessun dato nell&apos;intervallo selezionato
        </div>
      </Card>
    );
  }

  return (
    <Card className="p-6">
      <div className="flex items-center justify-between mb-4 gap-3">
        <div className="flex items-center gap-3 flex-wrap">
          <h3 className="text-sm font-medium text-muted-foreground">Storico Vendite</h3>

          <span className="text-xs text-muted-foreground">
            •{" "}
            {granularity === "day"
              ? "Giornaliero"
              : granularity === "week"
                ? "Settimanale"
                : granularity === "month"
                  ? "Mensile"
                  : "Annuale"}
          </span>

          {granularityMode !== "auto" && granularity !== granularityMode && (
            <span className="text-xs text-muted-foreground">(Range troppo ampio: passata a {granularity})</span>
          )}
        </div>

        <div className="flex items-center gap-3 flex-wrap justify-end">
          <div className="flex items-center gap-2">
            <Label className="text-xs text-muted-foreground">Aggregazione</Label>
            <select
              className="h-9 px-3 rounded-md border border-input bg-background text-sm"
              value={selectValue}
              onChange={(e) => onGranularityModeChange(e.target.value as GranularityMode)}
              disabled={!!granularitySelectDisabled}
              title={granularitySelectDisabled ? "Seleziona prima una entità" : undefined}
            >
              <option value="day">Giorno</option>
              <option value="week">Settimana</option>
              <option value="month">Mese</option>
              <option value="year">Anno</option>
              <option value="auto">Auto</option>
            </select>
          </div>

          <div className="flex items-center gap-2">
            <Switch id="breakdown-toggle" checked={showBreakdown} onCheckedChange={onToggleBreakdown} />
            <Label htmlFor="breakdown-toggle" className="text-xs">
              Mostra fasce prezzo
            </Label>
          </div>
        </div>
      </div>

      <div className="h-[420px]">
        <ResponsiveContainer width="100%" height="100%">
          <ComposedChart data={mergedData} margin={{ top: 10, right: 10, left: 0, bottom: 30 }}>
            <XAxis
              xAxisId="main"
              dataKey="data"
              tickLine={false}
              axisLine={false}
              interval={0} // decidiamo noi cosa mostrare (tick può tornare null)
              height={xAxisLayout.height}
              tickMargin={10}
              minTickGap={0}
              tick={(p: any) => (
                <CustomXAxisTick {...p} angle={xAxisLayout.angle} tickLabel={xTickLabelGetter(p.payload?.value)} />
              )}
            />
            <XAxis
              xAxisId="year"
              dataKey="data"
              orientation="bottom"
              axisLine={false}
              tickLine={false}
              interval={0}
              height={15}
              tickMargin={5}
              tick={(p: any) => {
                const iso = String(p.payload?.value ?? "").slice(0, 10);
                const found = yearCenters.find((yc) => yc.x === iso);
                if (!found) return null;

                // testo centrato, non ruotato, un po' più grande
                const { x, y } = p;
                return (
                  <g transform={`translate(${x},${y})`}>
                    <text textAnchor="middle" fill="currentColor" fontSize={12} fontWeight={600}>
                      {found.year}
                    </text>
                  </g>
                );
              }}
            />

            <YAxis tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
            <Tooltip content={<CustomTooltip />} />

            {yearSeparators.map((x) => (
              <ReferenceLine
                key={`year-${x}`}
                xAxisId="main"
                x={x}
                stroke="hsl(var(--border))"
                strokeWidth={2} // più evidente
                strokeOpacity={0.9}
                ifOverflow="extendDomain"
              />
            ))}

            {showBreakdown && fasce.length > 0 ? (
              <>
                {fasce.map((fascia, idx) => (
                  <Bar
                    key={fascia}
                    xAxisId="main"
                    dataKey={`fascia_${fascia}`}
                    name={fascia}
                    stackId="a"
                    fill={FASCIA_COLORS[idx % FASCIA_COLORS.length]}
                    radius={idx === fasce.length - 1 ? [6, 6, 0, 0] : [0, 0, 0, 0]}
                    isAnimationActive={false}
                    minPointSize={1}
                  />
                ))}
                <Legend />
              </>
            ) : (
              <>
                {mergedData.some((d: any) => (d.qty_forecast_bar ?? 0) > 0) && (
                  <Bar
                    xAxisId="main"
                    dataKey="qty_forecast_bar"
                    name="Forecast (10g)"
                    fill="hsl(var(--accent))"
                    opacity={0.18}
                    radius={[6, 6, 0, 0]}
                    isAnimationActive={false}
                    minPointSize={1}
                  />
                )}

                <Bar
                  xAxisId="main"
                  dataKey="qty_venduta_tot"
                  name="Vendite"
                  fill="hsl(var(--primary))"
                  opacity={0.85}
                  radius={[6, 6, 0, 0]}
                  isAnimationActive={false}
                  minPointSize={1}
                >
                  {mergedData.map((entry: any, i: number) => (
                    <Cell
                      key={`cell-vendite-${i}`}
                      // weekend arancione (solo in day, ma entry.isWeekend è già true solo in day)
                      fill={entry.isWeekend ? "hsl(35, 80%, 50%)" : "hsl(var(--primary))"}
                      // festività: cornice rossa
                      stroke={entry.is_holiday ? "hsl(0, 80%, 55%)" : "transparent"}
                      strokeWidth={entry.is_holiday ? 2 : 0}
                    />
                  ))}
                </Bar>

                {mergedData.some((d: any) => d.qty_forecast_line != null) && (
                  <Line
                    xAxisId="main"
                    type="monotone"
                    dataKey="qty_forecast_line"
                    name="Trend atteso"
                    stroke="hsl(var(--accent))"
                    strokeWidth={2}
                    strokeDasharray="5 5"
                    dot={false}
                    isAnimationActive={false}
                    connectNulls={false}
                  />
                )}
              </>
            )}

            {granularity === "day" &&
              holidays.map((h: any, idx: number) => (
                <ReferenceDot
                  key={idx}
                  xAxisId="main"
                  x={h.data}
                  y={h.qty_venduta_tot ?? h.qty_venduta ?? 0}
                  r={6}
                  fill="hsl(0, 80%, 50%)"
                  stroke="white"
                  strokeWidth={2}
                />
              ))}
          </ComposedChart>
        </ResponsiveContainer>
      </div>

      <div className="mt-4 flex flex-col gap-3">
        <div className="flex flex-wrap items-end gap-3">
          <div className="flex flex-wrap items-center gap-1 mr-2">
            {quickButtons.map((b) => (
              <Button
                key={b.k}
                variant="outline"
                size="sm"
                className="h-8 px-2"
                onClick={() => onDateRangeChange(b.fn())}
              >
                {b.k}
              </Button>
            ))}
          </div>

          <div className="flex items-end gap-3">
            <div className="space-y-1">
              <Label className="text-xs">Da</Label>
              <DateField value={dateFrom} onChange={(v) => onDateRangeChange({ from: v, to: dateTo })} />
            </div>
            <div className="space-y-1">
              <Label className="text-xs">A</Label>
              <DateField value={dateTo} onChange={(v) => onDateRangeChange({ from: dateFrom, to: v })} />
            </div>
          </div>

          <div className="flex flex-col gap-1 min-w-[170px]">
            <Label className="text-xs leading-none">Giorni</Label>
            <select
              className="h-9 px-3 rounded-md border border-input bg-background text-sm"
              value={dayFilter}
              onChange={(e) => onDayFilterChange(e.target.value as DayFilter)}
              disabled={granularity !== "day"}
              title={granularity !== "day" ? "Disponibile solo in vista giornaliera" : undefined}
            >
              <option value="ALL">Tutti</option>
              <option value="WEEKEND">Weekend</option>
              <option value="SAT">Solo Sabato</option>
              <option value="SUN">Solo Domenica</option>
              <option value="HOLIDAYS_ONLY">Solo Festività</option>
            </select>
          </div>

          <div className="space-y-1">
            <Label className="text-xs">Festività</Label>
            <Input
              placeholder='es. "Natale"'
              value={holidayNameFilter}
              onChange={(e) => onHolidayNameFilterChange(e.target.value)}
              className="h-9 w-[150px]"
              disabled={granularity !== "day"}
              title={granularity !== "day" ? "Disponibile solo in vista giornaliera" : undefined}
            />
          </div>

          <Button variant="outline" className="h-9" onClick={onResetControls}>
            Reset
          </Button>
        </div>
      </div>

      <p className="text-xs text-muted-foreground mt-2">
        {granularity === "day" ? (
          <>
            <span className="inline-block w-3 h-3 bg-muted rounded mr-1" /> Weekend •
            <span className="inline-block w-3 h-3 bg-amber-500 rounded ml-2 mr-1" /> Festività
          </>
        ) : (
          <span className="text-xs text-muted-foreground">
            Vista aggregata ({granularity === "week" ? "settimanale" : granularity === "month" ? "mensile" : "annuale"}
            ): weekend/festività non evidenziati
          </span>
        )}
      </p>
    </Card>
  );
}

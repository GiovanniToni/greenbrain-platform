import { useMemo, useState } from "react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid, ReferenceLine } from "recharts";

import { useDashboardSalesMonthly } from "@/hooks/useDashboardSalesMonthly";
import { useDashboardSalesWeekly } from "@/hooks/useDashboardSalesWeekly";
import { useDashboardSalesYearly } from "@/hooks/useDashboardSalesYearly";

/** Helpers */
function isoDay(v: any) {
  return String(v ?? "").slice(0, 10);
}

function safeParseISODate0(iso: string): Date | null {
  const d = new Date(`${isoDay(iso)}T00:00:00`);
  return Number.isNaN(d.getTime()) ? null : d;
}

function addDays(d: Date, days: number) {
  const x = new Date(d);
  x.setDate(x.getDate() + days);
  return x;
}

function pad2(n: number) {
  return String(n).padStart(2, "0");
}

// ISO week number (Monday-based) + ISO week-year
function isoWeekInfo(date: Date) {
  const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  const dayNum = d.getUTCDay() || 7; // 1..7
  d.setUTCDate(d.getUTCDate() + 4 - dayNum); // Thursday
  const isoYear = d.getUTCFullYear();
  const yearStart = new Date(Date.UTC(isoYear, 0, 1));
  const weekNo = Math.ceil(((d.getTime() - yearStart.getTime()) / 86400000 + 1) / 7);
  return { isoYear, weekNo };
}

function fmtMoneyEUR(n: number) {
  return `€${Number(n || 0).toLocaleString("it-IT", { maximumFractionDigits: 0 })}`;
}
function fmtMoneyEUR2(n: number) {
  return `€${Number(n || 0).toLocaleString("it-IT", { maximumFractionDigits: 2 })}`;
}
function pctChange(curr: number, prev: number) {
  if (!Number.isFinite(curr) || !Number.isFinite(prev)) return null;
  if (prev === 0 && curr === 0) return 0;
  if (prev === 0) return null;
  return ((curr - prev) / Math.abs(prev)) * 100;
}

function fmtMonthShort(d: Date) {
  return d.toLocaleDateString("it-IT", { month: "short" }); // "feb"
}
function fmtMonthLong(d: Date) {
  const s = d.toLocaleDateString("it-IT", { month: "long", year: "numeric" });
  return s.charAt(0).toUpperCase() + s.slice(1);
}
function fmtDayMonth(d: Date) {
  return d.toLocaleDateString("it-IT", { day: "2-digit", month: "short" }); // "02 feb"
}

type Mode = "monthly" | "weekly" | "yearly";

type RangePresetM = "12m" | "24m" | "36m" | "all";
type RangePresetW = "12w" | "26w" | "52w" | "all";
type RangePresetY = "5y" | "10y" | "all";

const PRESETS_M: Array<{ key: RangePresetM; label: string }> = [
  { key: "12m", label: "12 mesi" },
  { key: "24m", label: "24 mesi" },
  { key: "36m", label: "36 mesi" },
  { key: "all", label: "Tutto" },
];

const PRESETS_W: Array<{ key: RangePresetW; label: string }> = [
  { key: "12w", label: "12 sett." },
  { key: "26w", label: "26 sett." },
  { key: "52w", label: "52 sett." },
  { key: "all", label: "Tutto" },
];

const PRESETS_Y: Array<{ key: RangePresetY; label: string }> = [
  { key: "5y", label: "5 anni" },
  { key: "10y", label: "10 anni" },
  { key: "all", label: "Tutto" },
];

const WINDOW_M: Record<Exclude<RangePresetM, "all">, number> = { "12m": 12, "24m": 24, "36m": 36 };
const WINDOW_W: Record<Exclude<RangePresetW, "all">, number> = { "12w": 12, "26w": 26, "52w": 52 };
const WINDOW_Y: Record<Exclude<RangePresetY, "all">, number> = { "5y": 5, "10y": 10 };

type ChartRow = {
  iso: string; // key asse X
  vendite: number;

  // meta per label/marker
  year: number;

  month?: number; // 0..11
  weekNo?: number; // 1..53
  isoWeekYear?: number;

  weekStart?: string; // iso
  weekEnd?: string; // iso

  labelTop: string; // riga 1 tick
  labelBottom: string; // riga 2 tick
};

export function MonthlySalesChart() {
  const [mode, setMode] = useState<Mode>("monthly");

  const monthly = useDashboardSalesMonthly();
  const weekly = useDashboardSalesWeekly();
  const yearly = useDashboardSalesYearly();

  const loading = mode === "monthly" ? monthly.loading : mode === "weekly" ? weekly.loading : yearly.loading;
  const rows = mode === "monthly" ? monthly.rows : mode === "weekly" ? weekly.rows : yearly.rows;

  // preset separati per modalità
  const [presetM, setPresetM] = useState<RangePresetM>("24m");
  const [presetW, setPresetW] = useState<RangePresetW>("52w");
  const [presetY, setPresetY] = useState<RangePresetY>("10y");

  const preset = mode === "monthly" ? presetM : mode === "weekly" ? presetW : presetY;

  // endIndex inclusivo
  const [endIndex, setEndIndex] = useState<number | null>(null);

  // normalizza e ordina
  const all = useMemo(() => {
    const r = (rows ?? [])
      .map((x) => ({
        data: isoDay((x as any).data),
        imp_tot: Number((x as any).imp_tot ?? 0) || 0,
      }))
      .filter((x) => !!x.data)
      .sort((a, b) => (a.data < b.data ? -1 : a.data > b.data ? 1 : 0));
    return r;
  }, [rows]);

  const effectiveEndIndex = useMemo(() => {
    if (all.length === 0) return null;
    if (endIndex == null) return all.length - 1;
    return Math.min(Math.max(endIndex, 0), all.length - 1);
  }, [all.length, endIndex]);

  const windowSize = useMemo(() => {
    if (!all.length) return 0;
    if (preset === "all") return all.length;

    if (mode === "monthly") return WINDOW_M[presetM as Exclude<RangePresetM, "all">];
    if (mode === "weekly") return WINDOW_W[presetW as Exclude<RangePresetW, "all">];
    return WINDOW_Y[presetY as Exclude<RangePresetY, "all">];
  }, [all.length, preset, mode, presetM, presetW, presetY]);

  const slice = useMemo(() => {
    if (!all.length || effectiveEndIndex == null || windowSize <= 0) return [];
    const end = effectiveEndIndex;
    const start = Math.max(0, end - windowSize + 1);
    return all.slice(start, end + 1);
  }, [all, effectiveEndIndex, windowSize]);

  // 🔥 ChartData con label stile Yahoo
  const chartData: ChartRow[] = useMemo(() => {
    const out: ChartRow[] = [];

    for (const r of slice) {
      const d = safeParseISODate0(r.data);
      if (!d) continue;

      if (mode === "monthly") {
        const year = d.getFullYear();
        const month = d.getMonth();

        out.push({
          iso: r.data,
          vendite: r.imp_tot,
          year,
          month,
          labelTop: fmtMonthShort(d), // "feb"
          labelBottom: String(year), // "2026"
        });
      } else if (mode === "weekly") {
        const ws = d; // week start (lun)
        const we = addDays(ws, 6);

        const { isoYear, weekNo } = isoWeekInfo(ws);

        out.push({
          iso: r.data,
          vendite: r.imp_tot,
          year: isoYear, // ✅ anno ISO (coerente con Wxx)
          isoWeekYear: isoYear,
          weekNo,
          weekStart: isoDay(ws.toISOString()),
          weekEnd: isoDay(we.toISOString()),
          labelTop: `W${pad2(weekNo)}`, // "W06"
          labelBottom: `${fmtDayMonth(ws)}–${fmtDayMonth(we)}`, // "02 feb–08 feb"
        });
      } else {
        // yearly: r.data = 01-01-YYYY
        const year = d.getFullYear();

        out.push({
          iso: r.data,
          vendite: r.imp_tot,
          year,
          labelTop: String(year), // "2026"
          labelBottom: "", // niente seconda riga (pulito)
        });
      }
    }

    return out;
  }, [slice, mode]);

  // KPI periodo visibile
  const visibleKpis = useMemo(() => {
    if (!slice.length) return null;

    const total = slice.reduce((s, r) => s + (Number(r.imp_tot) || 0), 0);
    const avg = total / slice.length;

    const last = slice[slice.length - 1]?.imp_tot ?? 0;
    const prev = slice.length >= 2 ? (slice[slice.length - 2]?.imp_tot ?? 0) : 0;
    const delta = slice.length >= 2 ? pctChange(last, prev) : null;

    const from = slice[0].data;
    const to = slice[slice.length - 1].data;

    return { total, avg, delta, from, to };
  }, [slice]);

  const canPrev = useMemo(() => {
    if (!all.length || effectiveEndIndex == null || windowSize <= 0) return false;
    const start = Math.max(0, effectiveEndIndex - windowSize + 1);
    return start > 0;
  }, [all.length, effectiveEndIndex, windowSize]);

  const canNext = useMemo(() => {
    if (!all.length || effectiveEndIndex == null) return false;
    return effectiveEndIndex < all.length - 1;
  }, [all.length, effectiveEndIndex]);

  const shiftWindow = (dir: -1 | 1) => {
    if (!all.length || effectiveEndIndex == null || windowSize <= 0) return;
    const step = Math.max(1, Math.floor(windowSize / 2));
    const nextEnd = effectiveEndIndex + dir * step;
    setEndIndex(Math.min(Math.max(nextEnd, 0), all.length - 1));
  };

  const jumpToLatest = () => {
    if (!all.length) return;
    setEndIndex(all.length - 1);
  };

  // ✅ markers anno: linea quando cambia anno (utile in weekly/monthly quando "Tutto")
  const yearMarkers = useMemo(() => {
    const markers: Array<{ iso: string; year: number }> = [];
    if (chartData.length < 2) return markers;

    let prevYear = chartData[0].year;
    for (let i = 1; i < chartData.length; i++) {
      const y = chartData[i].year;
      if (y !== prevYear) {
        markers.push({ iso: chartData[i].iso, year: y });
        prevYear = y;
      }
    }
    return markers;
  }, [chartData]);

  // Tick custom a 2 righe (top/bottom)
  const CustomTick = (props: any) => {
    const { x, y, payload } = props;
    const iso = payload?.value as string;

    const row = chartData.find((r) => r.iso === iso);
    if (!row) return null;

    const idx = chartData.findIndex((r) => r.iso === iso);
    const prev = idx > 0 ? chartData[idx - 1] : null;

    // weekly: aggiungi anno solo quando cambia
    const showYearInWeekly = mode === "weekly" && (idx === 0 || (prev && prev.year !== row.year));

    // yearly: solo una riga grande
    if (mode === "yearly") {
      return (
        <g transform={`translate(${x},${y})`}>
          <text x={0} y={18} textAnchor="middle" fontSize={12} fill="hsl(var(--muted-foreground))">
            {row.labelTop}
          </text>
        </g>
      );
    }

    const bottom =
      mode === "weekly" ? (showYearInWeekly ? `${row.labelBottom} · ${row.year}` : row.labelBottom) : row.labelBottom;

    return (
      <g transform={`translate(${x},${y})`}>
        <text x={0} y={10} textAnchor="middle" fontSize={12} fill="hsl(var(--muted-foreground))">
          {row.labelTop}
        </text>
        <text x={0} y={26} textAnchor="middle" fontSize={11} fill="hsl(var(--muted-foreground))">
          {bottom}
        </text>
      </g>
    );
  };

  const CustomTooltip = ({ active, payload }: any) => {
    if (!active || !payload || !payload.length) return null;
    const p = payload[0]?.payload as ChartRow | undefined;
    if (!p) return null;

    const header =
      mode === "monthly"
        ? (() => {
            const d = safeParseISODate0(p.iso);
            return d ? fmtMonthLong(d) : p.iso;
          })()
        : mode === "weekly"
          ? (() => {
              const d = safeParseISODate0(p.iso);
              if (!d) return `Settimana ${p.weekNo ?? ""}`;
              const ws = d;
              const we = addDays(ws, 6);
              const wNo = p.weekNo ?? isoWeekInfo(ws).weekNo;
              const wYear = p.isoWeekYear ?? isoWeekInfo(ws).isoYear;
              return `Anno ${wYear} · W${pad2(wNo)} · ${fmtDayMonth(ws)}–${fmtDayMonth(we)}`;
            })()
          : (() => {
              const d = safeParseISODate0(p.iso);
              const y = d ? d.getFullYear() : p.year;
              return `Anno ${y}`;
            })();

    const caption =
      mode === "monthly"
        ? "Totale mese (imponibile netto)"
        : mode === "weekly"
          ? "Totale settimana (imponibile netto)"
          : "Totale anno (imponibile netto)";

    return (
      <div className="rounded-lg border bg-background px-3 py-2 shadow-sm">
        <div className="text-xs text-muted-foreground">{header}</div>
        <div className="text-sm font-semibold tabular-nums">{fmtMoneyEUR2(Number(p.vendite || 0))}</div>
        <div className="text-[11px] text-muted-foreground">{caption}</div>
      </div>
    );
  };

  const presetsForMode = mode === "monthly" ? PRESETS_M : mode === "weekly" ? PRESETS_W : PRESETS_Y;

  return (
    <Card className="p-6 animate-fade-in">
      {/* Header + controls */}
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between mb-4">
        <div>
          <h3 className="text-sm font-medium text-muted-foreground">
            {loading
              ? "Caricamento vendite..."
              : mode === "monthly"
                ? "Vendite mensili"
                : mode === "weekly"
                  ? "Vendite settimanali"
                  : "Vendite annuali"}
          </h3>

          {visibleKpis && !loading ? (
            <div className="mt-1 text-xs text-muted-foreground">
              <span className="tabular-nums">
                {visibleKpis.from} → {visibleKpis.to}
              </span>
              <span className="mx-2">•</span>
              <span className="tabular-nums">Tot: {fmtMoneyEUR(visibleKpis.total)}</span>
              <span className="mx-2">•</span>
              <span className="tabular-nums">Media: {fmtMoneyEUR(visibleKpis.avg)}</span>
              <span className="mx-2">•</span>
              <span
                className={cn(
                  "tabular-nums",
                  visibleKpis.delta == null ? "" : visibleKpis.delta >= 0 ? "text-primary" : "text-destructive",
                )}
              >
                {mode === "monthly" ? "MoM" : mode === "weekly" ? "WoW" : "YoY"}:{" "}
                {visibleKpis.delta == null
                  ? "n/d"
                  : `${visibleKpis.delta >= 0 ? "+" : ""}${visibleKpis.delta.toLocaleString("it-IT", {
                      maximumFractionDigits: 0,
                    })}%`}
              </span>
            </div>
          ) : null}
        </div>

        <div className="flex flex-wrap items-center gap-2">
          {/* toggle mensile/settimanale/annuale */}
          <div className="flex items-center gap-1 rounded-md border p-1">
            <Button
              type="button"
              variant={mode === "monthly" ? "default" : "ghost"}
              size="sm"
              className="h-7 px-2 text-xs"
              onClick={() => {
                setMode("monthly");
                setEndIndex(null);
              }}
            >
              Mensile
            </Button>
            <Button
              type="button"
              variant={mode === "weekly" ? "default" : "ghost"}
              size="sm"
              className="h-7 px-2 text-xs"
              onClick={() => {
                setMode("weekly");
                setEndIndex(null);
              }}
            >
              Settimanale
            </Button>
            <Button
              type="button"
              variant={mode === "yearly" ? "default" : "ghost"}
              size="sm"
              className="h-7 px-2 text-xs"
              onClick={() => {
                setMode("yearly");
                setEndIndex(null);
              }}
            >
              Annuale
            </Button>
          </div>

          {/* presets */}
          <div className="flex items-center gap-1 rounded-md border p-1">
            {presetsForMode.map((p) => (
              <Button
                key={p.key}
                type="button"
                variant={preset === p.key ? "default" : "ghost"}
                size="sm"
                className="h-7 px-2 text-xs"
                onClick={() => {
                  if (mode === "monthly") setPresetM(p.key as RangePresetM);
                  else if (mode === "weekly") setPresetW(p.key as RangePresetW);
                  else setPresetY(p.key as RangePresetY);
                  setEndIndex(null);
                }}
              >
                {p.label}
              </Button>
            ))}
          </div>

          {/* nav */}
          <div className="flex items-center gap-1">
            <Button
              type="button"
              variant="outline"
              size="sm"
              className="h-7 text-xs"
              disabled={!canPrev}
              onClick={() => shiftWindow(-1)}
            >
              Prev
            </Button>
            <Button
              type="button"
              variant="outline"
              size="sm"
              className="h-7 text-xs"
              disabled={!canNext}
              onClick={() => shiftWindow(1)}
            >
              Next
            </Button>
            <Button
              type="button"
              variant="ghost"
              size="sm"
              className="h-7 text-xs"
              disabled={!all.length}
              onClick={jumpToLatest}
            >
              Oggi
            </Button>
          </div>
        </div>
      </div>

      {/* Chart */}
      <div className="h-80">
        {loading ? (
          <div className="h-full rounded-md bg-muted animate-pulse" />
        ) : chartData.length === 0 ? (
          <div className="mt-2 text-sm text-muted-foreground">Nessun dato vendite disponibile.</div>
        ) : (
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={chartData} margin={{ left: 8, right: 8, top: 14, bottom: mode === "yearly" ? 18 : 28 }}>
              <CartesianGrid vertical={false} stroke="hsl(var(--border))" strokeOpacity={0.6} />

              {/* marker anno stile Yahoo (utile per monthly/weekly) */}
              {mode !== "yearly" &&
                yearMarkers.map((m) => (
                  <ReferenceLine
                    key={`${m.year}-${m.iso}`}
                    x={m.iso}
                    stroke="hsl(var(--border))"
                    strokeOpacity={0.9}
                    label={{
                      value: String(m.year),
                      position: "insideTopLeft",
                      fill: "hsl(var(--muted-foreground))",
                      fontSize: 12,
                    }}
                  />
                ))}

              <XAxis
                dataKey="iso"
                tickLine={false}
                axisLine={false}
                interval="preserveStartEnd"
                minTickGap={mode === "yearly" ? 18 : 22}
                height={mode === "yearly" ? 28 : 44}
                tick={<CustomTick />}
              />

              <YAxis
                tick={{ fontSize: 12 }}
                tickLine={false}
                axisLine={false}
                width={60}
                tickFormatter={(value) => {
                  const v = Number(value) || 0;
                  if (v >= 1_000_000) return `€${Math.round(v / 1_000_000)}M`;
                  if (v >= 10_000) return `€${Math.round(v / 1000)}k`;
                  return `€${Math.round(v)}`;
                }}
              />

              <Tooltip content={<CustomTooltip />} />
              <Bar dataKey="vendite" fill="hsl(var(--primary))" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        )}
      </div>
    </Card>
  );
}

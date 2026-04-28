// src/pages/Analytics.tsx
import { useEffect, useMemo, useState, useCallback, useRef } from "react";
import { Card } from "@/components/ui/card";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";

import { AnalyticsEntitySearch } from "@/components/analytics/AnalyticsEntitySearch";
import { SalesHistoryChart } from "@/components/analytics/SalesHistoryChart";
import { EntitySummaryCard } from "@/components/analytics/EntitySummaryCard";
import { CompareSalesChart } from "@/components/analytics/CompareSalesChart";
import { CompareEntitySelector } from "@/components/analytics/CompareEntitySelector";
import { WeeklySeasonalityChart } from "@/components/analytics/WeeklySeasonalityChart";
import { SeasonalityChart } from "@/components/analytics/SeasonalityChart";
import { AnalyticsOperationalKpis } from "@/components/analytics/AnalyticsOperationalKpis";

import { useAnalyticsRollingTotals } from "@/hooks/useAnalyticsRollingTotals";
import { useAnalyticsStockAndReorder } from "@/hooks/useAnalyticsStockAndReorder";

import { CatalogItem } from "@/hooks/useAnalyticsCatalog";
import { useAnalyticsSeries, GranularityMode } from "@/hooks/useAnalyticsSeries";
import { useAnalyticsSeasonality } from "@/hooks/useAnalyticsSeasonality";
import { useAnalyticsComponents } from "@/hooks/useAnalyticsComponents";
import { useAnalyticsCompareSeries, CompareItem } from "@/hooks/useAnalyticsCompareSeries";
import { useAnalyticsFutureWindowsKpi } from "@/hooks/useAnalyticsFutureWindowsKpi";
import { useAnalyticsSeriesAllTime } from "@/hooks/useAnalyticsSeriesAllTime";
import { useAnalyticsRangeTotals } from "@/hooks/useAnalyticsRangeTotals";

import { useLocation, useNavigate } from "react-router-dom";

function formatDateISO(d: Date) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function isoDay(v: any) {
  return String(v ?? "").slice(0, 10);
}

// parse ISO day senza shift timezone
function parseISODate(iso: string) {
  return new Date(`${isoDay(iso)}T00:00:00`);
}

function addDaysISO(iso: string, days: number) {
  const d = parseISODate(iso);
  d.setDate(d.getDate() + days);
  return formatDateISO(d);
}

function minISO(a: string, b: string) {
  return a <= b ? a : b;
}

function getDefaultDateRange180(toISO?: string) {
  const todayISO = formatDateISO(new Date());
  const to = isoDay(toISO ?? todayISO);
  const from = addDaysISO(to, -180);
  return { from, to };
}

// --------------------
// ✅ Snap helpers (per non perdere bucket yearly/week/month quando il range non è allineato)
// --------------------
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
  const day = d.getDay(); // 0..6
  const diff = (day + 6) % 7; // Mon=0
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

function snapRangeForGranularity(from: string, to: string, g: "day" | "week" | "month" | "year") {
  if (g === "year") return { from: startOfYearISO(from), to: startOfYearISO(to) };
  if (g === "month") return { from: startOfMonthISO(from), to: startOfMonthISO(to) };
  if (g === "week") return { from: startOfWeekMonISO(from), to: startOfWeekMonISO(to) };
  return { from, to };
}

type DayFilter = "ALL" | "WEEKEND" | "SAT" | "SUN" | "HOLIDAYS_ONLY";
type ViewMode = "single" | "compare";

export default function Analytics() {
  const location = useLocation();
  const navigate = useNavigate();

  const [viewMode, setViewMode] = useState<ViewMode>("single");

  const [selectedEntity, setSelectedEntity] = useState<CatalogItem | null>(null);
  const ctx = useMemo(() => {
    const e: any = selectedEntity as any;
    return {
      fascia: e?.fascia ?? null,
      categoria: e?.categoria ?? null,
      famiglia: e?.famiglia ?? null,
      fascia_prezzo: e?.fascia_prezzo ?? null,
    };
  }, [selectedEntity]);

  const [compareItems, setCompareItems] = useState<CompareItem[]>([]);

  // ✅ default: ultimi 180 giorni
  const [dateRange, setDateRange] = useState(() => getDefaultDateRange180());

  const [dayFilter, setDayFilter] = useState<DayFilter>("ALL");
  const [holidayNameFilter, setHolidayNameFilter] = useState<string>("");
  const [showBreakdown, setShowBreakdown] = useState(false);

  // ✅ IMPORTANT: default "auto" per evitare query daily enormi
  const [granularityMode, setGranularityMode] = useState<GranularityMode>("auto");

  const rangeTouchedRef = useRef(false);

  const {
    totalSeries,
    breakdownSeries,
    granularity, // effettiva (dopo clamp/override)
    loading: seriesLoading,
    error: seriesError,
    refetch: refetchSeries,
  } = useAnalyticsSeries();

  const { bounds, loadingAll, errorAll, refetchAll } = useAnalyticsSeriesAllTime();

  const {
    series: compareSeries,
    loading: compareLoading,
    error: compareError,
    refetch: refetchCompare,
  } = useAnalyticsCompareSeries();

  const {
    data: seasonalityData,
    loading: seasonalityLoading,
    error: seasonalityError,
    refetch: refetchSeasonality,
  } = useAnalyticsSeasonality();

  const { error: componentsError, refetch: refetchComponents } = useAnalyticsComponents();

  const {
    rows: futureRows,
    loading: futureLoading,
    error: futureError,
    refetch: refetchFuture,
  } = useAnalyticsFutureWindowsKpi();

  const {
    data: rollingTotals,
    loading: rollingLoading,
    error: rollingError,
    refetch: refetchRolling,
  } = useAnalyticsRollingTotals();

  const {
    data: stockAndReorder,
    loading: stockLoading,
    error: stockError,
    refetch: refetchStockAndReorder,
  } = useAnalyticsStockAndReorder();

  // ✅ ora include clearRangeTotals
  const {
    data: rangeTotals,
    loading: rangeTotalsLoading,
    error: rangeTotalsError,
    refetch: refetchRangeTotals,
    clear: clearRangeTotals,
  } = useAnalyticsRangeTotals();

  const todayISO = useMemo(() => formatDateISO(new Date()), []);

  const latestAvailableDate = useMemo(() => bounds?.max ?? null, [bounds]);

  const anchorTo = useMemo(() => {
    if (!latestAvailableDate) return todayISO;
    return minISO(todayISO, latestAvailableDate);
  }, [todayISO, latestAvailableDate]);

  const setDateRangeSafe = useCallback(
    (r: { from: string; to: string }) => {
      rangeTouchedRef.current = true;

      let from = isoDay(r.from);
      let to = isoDay(r.to);

      if (to > anchorTo) to = anchorTo;
      if (from > to) from = to;

      setDateRange({ from, to });
    },
    [anchorTo],
  );

  // ✅ breakdown off se non ha senso o se year
  useEffect(() => {
    if (
      showBreakdown &&
      (selectedEntity?.entity_type === "fascia_prezzo" || selectedEntity?.entity_type === "articolo")
    ) {
      setShowBreakdown(false);
    }
  }, [selectedEntity, showBreakdown, granularity]);

  const handleEntitySelect = useCallback(
    (item: CatalogItem) => {
      setSelectedEntity(item);

      rangeTouchedRef.current = false;
      setDayFilter("ALL");
      setHolidayNameFilter("");
      setShowBreakdown(false);

      // ✅ default: 180 giorni + auto
      setGranularityMode("auto");
      setDateRange(getDefaultDateRange180(todayISO));
    },
    [todayISO],
  );

  // ✅ Se arrivo da TopBar con un preselect, lo apro automaticamente
  useEffect(() => {
    const st: any = location.state;
    const pre = st?.preselect;

    if (pre && pre.entity_type && pre.entity_key) {
      handleEntitySelect(pre);

      // ✅ pulisco lo state per evitare ri-trigger tornando indietro/refresh
      navigate(location.pathname, { replace: true, state: null });
    }
  }, [location.state, handleEntitySelect, navigate, location.pathname]);

  // bounds
  useEffect(() => {
    if (!selectedEntity) return;
    refetchAll({
      entityType: selectedEntity.entity_type,
      entityKey: selectedEntity.entity_key,
    });
  }, [selectedEntity, refetchAll]);

  // quando arrivano bounds, se utente non ha toccato: resetta range 180gg su anchorTo
  useEffect(() => {
    if (!selectedEntity) return;
    if (rangeTouchedRef.current) return;
    setDateRange(getDefaultDateRange180(anchorTo));
  }, [selectedEntity, anchorTo]);

  // clamp to anchor
  useEffect(() => {
    if (!anchorTo) return;
    if (dateRange.to > anchorTo) setDateRange((x) => ({ ...x, to: anchorTo }));
  }, [anchorTo, dateRange.to]);

  // evita invertito
  useEffect(() => {
    if (dateRange.from > dateRange.to) setDateRange((x) => ({ ...x, from: x.to }));
  }, [dateRange.from, dateRange.to]);

  // ✅ UI ONLY: valore tendina (mostra la granularità effettiva se clampata)
  const granularityModeSelectValue = useMemo<GranularityMode>(() => {
    if (granularityMode === "auto") return "auto";
    if (!granularity) return granularityMode;
    return granularityMode !== granularity ? granularity : granularityMode;
  }, [granularityMode, granularity]);

  // ✅ Filtri (solo day) + ✅ range snap per week/month/year
  const filteredTotalSeries = useMemo(() => {
    let rows = totalSeries.slice();

    const from = isoDay(dateRange.from);
    const to = isoDay(dateRange.to);

    const snapped = snapRangeForGranularity(from, to, granularity);
    const fFrom = snapped.from;
    const fTo = snapped.to;

    rows = rows.filter((r: any) => {
      const d = isoDay(r.data);
      return d >= fFrom && d <= fTo;
    });

    if (granularity === "day") {
      if (dayFilter === "WEEKEND") rows = rows.filter((r: any) => r.dow === 0 || r.dow === 6);
      else if (dayFilter === "SAT") rows = rows.filter((r: any) => r.dow === 6);
      else if (dayFilter === "SUN") rows = rows.filter((r: any) => r.dow === 0);
      else if (dayFilter === "HOLIDAYS_ONLY") rows = rows.filter((r: any) => !!r.is_holiday);

      const hn = holidayNameFilter.trim().toLowerCase();
      if (hn) rows = rows.filter((r: any) => (r.holiday_name ?? "").toLowerCase().includes(hn));
    }

    return rows;
  }, [totalSeries, dateRange.from, dateRange.to, dayFilter, holidayNameFilter, granularity]);

  // ✅ hasFpFilter (UNICO, usalo ovunque)
  const hasFpFilter = useMemo(() => {
    const fp = ctx.fascia_prezzo ?? "";
    return (
      !!String(fp).trim() &&
      (selectedEntity?.entity_type === "famiglia" ||
        selectedEntity?.entity_type === "categoria" ||
        selectedEntity?.entity_type === "fascia")
    );
  }, [ctx.fascia_prezzo, selectedEntity?.entity_type]);

  // ✅ effectiveRangeTotals DEVE venire PRIMA di chi lo usa
  const effectiveRangeTotals = useMemo(() => {
    if (hasFpFilter) {
      const qty = filteredTotalSeries.reduce((s, r) => s + Number(r.qty_venduta_tot ?? 0), 0);
      const imp = filteredTotalSeries.reduce((s, r) => s + Number((r as any).imponibile_netto_tot ?? 0), 0);

      const active_days = filteredTotalSeries.filter((r) => (r.qty_venduta_tot ?? 0) > 0).length;
      const zero_days = filteredTotalSeries.filter((r) => (r.qty_venduta_tot ?? 0) === 0).length;

      const minRow =
        filteredTotalSeries.length > 0
          ? filteredTotalSeries.reduce((a, b) =>
              Number(a.qty_venduta_tot ?? 0) <= Number(b.qty_venduta_tot ?? 0) ? a : b,
            )
          : null;

      const maxRow =
        filteredTotalSeries.length > 0
          ? filteredTotalSeries.reduce((a, b) =>
              Number(a.qty_venduta_tot ?? 0) >= Number(b.qty_venduta_tot ?? 0) ? a : b,
            )
          : null;

      return {
        qty_tot: qty,
        imp_tot: imp,
        days: filteredTotalSeries.length,
        active_days,
        zero_days,
        min_day: minRow ? isoDay(minRow.data) : null,
        min_qty: minRow ? Number(minRow.qty_venduta_tot ?? 0) : 0,
        max_day: maxRow ? isoDay(maxRow.data) : null,
        max_qty: maxRow ? Number(maxRow.qty_venduta_tot ?? 0) : 0,
      };
    }

    return rangeTotals;
  }, [hasFpFilter, filteredTotalSeries, rangeTotals]);

  const selectedRangeTotals = useMemo(() => {
    return {
      qty: (effectiveRangeTotals as any)?.qty_tot ?? 0,
      imp: (effectiveRangeTotals as any)?.imp_tot ?? 0,
    };
  }, [effectiveRangeTotals]);

  const filteredBreakdown = useMemo(() => {
    if (!breakdownSeries || breakdownSeries.length === 0) return [];
    const allowedDates = new Set(filteredTotalSeries.map((d: any) => isoDay(d.data)));
    return breakdownSeries.filter((b: any) => allowedDates.has(isoDay(b.data)));
  }, [breakdownSeries, filteredTotalSeries]);

  // Fetch single (usa hasFpFilter dal memo sopra)
  useEffect(() => {
    if (viewMode !== "single" || !selectedEntity) return;

    refetchRangeTotals({
      entityType: selectedEntity.entity_type,
      entityKey: selectedEntity.entity_key,
      dateFrom: dateRange.from,
      dateTo: dateRange.to,

      // ✅ serve per calcolare i totals filtrati dentro il hook
      fasciaPrezzo: ctx.fascia_prezzo ?? null,
    });

    refetchSeries({
      entityType: selectedEntity.entity_type,
      entityKey: selectedEntity.entity_key,
      dateFrom: dateRange.from,
      dateTo: dateRange.to,
      includeBreakdown: showBreakdown,
      granularity: granularityMode,

      fascia: ctx.fascia,
      categoria: ctx.categoria,
      famiglia: ctx.famiglia,
      fasciaPrezzo: ctx.fascia_prezzo ?? null,
    });

    refetchSeasonality({
      entityType: selectedEntity.entity_type,
      entityKey: selectedEntity.entity_key,
    });

    refetchComponents({
      entityType: selectedEntity.entity_type,
      entityKey: selectedEntity.entity_key,
    });

    if (selectedEntity.entity_type !== "fascia_prezzo" && selectedEntity.entity_type !== "articolo") {
      refetchFuture({
        entityType: selectedEntity.entity_type,
        entityKey: selectedEntity.entity_key,
        anchorTo,
        windows: [7, 14, 30, 60, 90],
        fasciaPrezzo: ctx.fascia_prezzo ?? null,
      });
    }

    refetchRolling({
      entityType: selectedEntity.entity_type,
      entityKey: selectedEntity.entity_key,
      anchorTo,
    });

    refetchStockAndReorder({
      entityType: selectedEntity.entity_type,
      entityKey: selectedEntity.entity_key,
      fasciaPrezzo: ctx.fascia_prezzo ?? null,
    });
  }, [
    viewMode,
    selectedEntity,
    dateRange.from,
    dateRange.to,
    showBreakdown,
    anchorTo,
    refetchSeries,
    refetchRangeTotals,
    refetchSeasonality,
    refetchComponents,
    refetchFuture,
    refetchRolling,
    refetchStockAndReorder,
    granularityMode,
    hasFpFilter,
    clearRangeTotals,
    ctx.fascia,
    ctx.categoria,
    ctx.famiglia,
    ctx.fascia_prezzo,
  ]);

  // Fetch compare
  useEffect(() => {
    if (viewMode !== "compare") return;

    refetchCompare({
      items: compareItems,
      dateFrom: dateRange.from,
      dateTo: dateRange.to,
    });
  }, [viewMode, compareItems, dateRange.from, dateRange.to, refetchCompare]);

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-bold leading-tight">Analytics</h1>
          <p className="text-xs text-muted-foreground leading-snug">
            Analizza vendite e trend per famiglia, categoria, fascia e fascia prezzo
          </p>
        </div>

        <div className="flex items-center gap-3">
          <Tabs value={viewMode} onValueChange={(v) => setViewMode(v as ViewMode)}>
            <TabsList className="h-9">
              <TabsTrigger className="h-8" value="single">
                Singola
              </TabsTrigger>
              <TabsTrigger className="h-8" value="compare">
                Confronta
              </TabsTrigger>
            </TabsList>
          </Tabs>
        </div>
      </div>

      <Card className="p-3">
        <div className="flex flex-col gap-3 lg:flex-row lg:items-end lg:justify-between">
          <div className="flex-1 min-w-[280px]">
            {viewMode === "single" ? (
              <AnalyticsEntitySearch onSelect={handleEntitySelect} selectedItem={selectedEntity} />
            ) : (
              <CompareEntitySelector selectedItems={compareItems} onChange={setCompareItems} />
            )}
          </div>
        </div>
      </Card>

      {viewMode === "single" && selectedEntity && (
        <EntitySummaryCard
          selectedEntity={selectedEntity}
          onSelect={handleEntitySelect}
          seriesData={filteredTotalSeries}
          dateFrom={dateRange.from}
          dateTo={dateRange.to}
          minAvailableDate={bounds?.min ?? null}
          maxAvailableDate={bounds?.max ?? null}
          rangeTotals={rangeTotals}
          rangeTotalsLoading={rangeTotalsLoading}
        />
      )}

      {viewMode === "single" && selectedEntity && (
        <AnalyticsOperationalKpis
          rolling={rollingTotals}
          selectedRange={selectedRangeTotals}
          stockQty={stockAndReorder?.stockQty ?? null}
          reorderQty={selectedEntity.entity_type === "articolo" ? null : (stockAndReorder?.reorderQty ?? null)}
          futureRows={futureRows || []}
          futureLoading={futureLoading}
          dateFrom={dateRange.from}
          dateTo={dateRange.to}
          loading={rollingLoading || stockLoading || futureLoading}
        />
      )}

      {viewMode === "single" && selectedEntity && (
        <SalesHistoryChart
          data={filteredTotalSeries}
          breakdownData={filteredBreakdown}
          granularity={granularity}
          granularityMode={granularityMode}
          granularityModeSelectValue={granularityModeSelectValue}
          onGranularityModeChange={setGranularityMode}
          granularitySelectDisabled={!selectedEntity || viewMode !== "single"}
          showBreakdown={
            selectedEntity?.entity_type === "fascia_prezzo" || selectedEntity?.entity_type === "articolo"
              ? false
              : showBreakdown
          }
          onToggleBreakdown={(v) => {
            if (selectedEntity?.entity_type === "fascia_prezzo" || selectedEntity?.entity_type === "articolo") return;
            setShowBreakdown(v);
          }}
          dateFrom={dateRange.from}
          dateTo={dateRange.to}
          anchorTo={anchorTo}
          minAvailableDate={bounds?.min ?? undefined}
          onDateRangeChange={({ from, to }) => setDateRangeSafe({ from, to })}
          dayFilter={dayFilter}
          onDayFilterChange={setDayFilter}
          holidayNameFilter={holidayNameFilter}
          onHolidayNameFilterChange={setHolidayNameFilter}
          onResetControls={() => {
            rangeTouchedRef.current = false;
            setDayFilter("ALL");
            setHolidayNameFilter("");
            setShowBreakdown(false);
            setGranularityMode("auto");
            setDateRange(getDefaultDateRange180(anchorTo));
          }}
          entityType={selectedEntity.entity_type}
          entityKey={selectedEntity.entity_key}
          fasciaPrezzo={ctx.fascia_prezzo ?? null}
        />
      )}

      {viewMode === "single" && selectedEntity && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <WeeklySeasonalityChart data={filteredTotalSeries} />
          <SeasonalityChart data={seasonalityData} />
        </div>
      )}

      {(seriesError ||
        errorAll ||
        seasonalityError ||
        componentsError ||
        compareError ||
        futureError ||
        rollingError ||
        stockError ||
        rangeTotalsError) && (
        <Card className="p-4 border border-destructive/40 space-y-2">
          <p className="text-sm font-semibold text-destructive">Errori:</p>
          {seriesError && <p className="text-sm text-destructive">• Series: {seriesError}</p>}
          {errorAll && <p className="text-sm text-destructive">• Bounds: {errorAll}</p>}
          {seasonalityError && <p className="text-sm text-destructive">• Seasonality: {seasonalityError}</p>}
          {componentsError && <p className="text-sm text-destructive">• Components: {componentsError}</p>}
          {compareError && <p className="text-sm text-destructive">• Compare: {compareError}</p>}
          {futureError && <p className="text-sm text-destructive">• Future windows: {futureError}</p>}
          {rollingError && <p className="text-sm text-destructive">• Rolling KPI: {rollingError}</p>}
          {stockError && <p className="text-sm text-destructive">• Stock/Riordino: {stockError}</p>}
          {rangeTotalsError && <p className="text-sm text-destructive">• Range totals: {rangeTotalsError}</p>}
        </Card>
      )}

      {viewMode === "compare" && <CompareSalesChart series={compareSeries} loading={compareLoading} />}
    </div>
  );
}

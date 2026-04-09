// src/pages/AssortmentPlanner.tsx

import { useEffect, useMemo, useState, useDeferredValue } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import { Loader2, Download, X } from "lucide-react";

import { usePlannerHeatmapNodes } from "@/features/planner/hooks/usePlannerHeatmapNodes";
import { usePlannerHeatmapCells } from "@/features/planner/hooks/usePlannerHeatmapCells";
import { usePlannerHeatmapRanges } from "@/features/planner/hooks/usePlannerHeatmapRanges";
import { usePlannerCurrentWeek } from "@/features/planner/hooks/usePlannerCurrentWeek";

import { usePlannerSpaceBudget } from "@/features/planner/hooks/usePlannerSpaceBudget";
import { SpaceBudgetTimeline } from "@/features/planner/components/SpaceBudgetTimeline";

import { usePlannerAssortmentCalendar } from "@/features/planner/hooks/usePlannerAssortmentCalendar";
import { AssortmentCalendar } from "@/features/planner/components/AssortmentCalendar";

import { HeatmapTreeTable } from "@/features/planner/components/HeatmapTreeTable";
import { HeatmapNodeChart } from "@/features/planner/components/HeatmapNodeChart";

import { exportToXlsx } from "@/features/planner/utils/exportExcel";
import { fetchAllPaged } from "@/features/planner/utils/fetchPaged";

import { HeatMetric, HeatNode, PlannerMode, SpaceBudgetLevel } from "@/features/planner/types";

import { apiGet } from "@/lib/apiClient";

function flattenVisibleIds(
  ids: string[],
  nodesById: Map<string, HeatNode>,
  childrenByParent: Map<string | null, string[]>,
  openMap: Record<string, boolean>,
): string[] {
  const result: string[] = [];
  for (const id of ids) {
    const node = nodesById.get(id);
    if (!node) continue;
    result.push(id);
    const childIds = childrenByParent.get(id) ?? [];
    if (childIds.length > 0 && openMap[id]) {
      result.push(...flattenVisibleIds(childIds, nodesById, childrenByParent, openMap));
    }
  }
  return result;
}

const METRIC_OPTIONS: { value: HeatMetric; label: string }[] = [
  { value: "avg_qty", label: "Qty" },
  { value: "avg_rev", label: "€ vendite" },
  { value: "share_rev", label: "Share €" },
  { value: "stock_target", label: "Stock target" },
  { value: "space_m2", label: "Spazio (m²)" },
];

type AnyRow = Record<string, any>;

function enrichHeatExportRows(rows: AnyRow[], nodesById: Map<string, HeatNode>) {
  return rows.map((r) => {
    const n = nodesById.get(r.node_id);

    return {
      // ✅ gerarchia completa (priorità: nodi -> fallback colonne db)
      fascia: n?.fascia ?? r.fascia ?? null,
      categoria: n?.categoria ?? r.categoria ?? null,
      famiglia: n?.famiglia ?? r.famiglia ?? null,
      fascia_prezzo: n?.fascia_prezzo ?? r.fascia_prezzo ?? null,

      // identificativi
      mode: r.mode,
      level: r.level,
      node_id: r.node_id,
      parent_id: r.parent_id ?? n?.parent_id ?? null,
      label: n?.label ?? r.label,

      // chiave settimana
      week_52: r.week_52,

      // numeri
      avg_qty: r.avg_qty,
      avg_rev: r.avg_rev,
      share_rev: r.share_rev,
      sigma_qty: r.sigma_qty,
      avg_days_active: r.avg_days_active,
      avg_days_zero: r.avg_days_zero,
      min_qty: r.min_qty,
      max_qty: r.max_qty,
      min_rev: r.min_rev,
      max_rev: r.max_rev,
      stock_target: r.stock_target,
      space_m2: r.space_m2,
      color_score: r.color_score,
      updated_at: r.updated_at,
    };
  });
}

function todayYmd() {
  const d = new Date();
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}

// ⚙️ Qui puoi scegliere tabella o view
const HEAT_EXPORT_SOURCE = "t_core_planner__heat_cells";
const ASSORT_EXPORT_SOURCE = "t_core_planner__assortment_calendar";

// colonne export: esplicite (stabili)
const HEAT_EXPORT_SELECT =
  "mode,fascia,categoria,famiglia,fascia_prezzo,week_52,stock_target,avg_qty,avg_rev,min_qty,max_qty,min_rev,max_rev,space_m2,updated_at";

const ASSORT_EXPORT_SELECT = "mode,level,node_id,week_52,state,space_m2_raw,space_share,stock_target,updated_at";

function Folder({
  title,
  right,
  defaultOpen = true,
  children,
}: {
  title: string;
  right?: React.ReactNode;
  defaultOpen?: boolean;
  children: React.ReactNode;
}) {
  return (
    <Card>
      <CardContent className="p-0">
        <details open={defaultOpen} className="group">
          <summary className="list-none cursor-pointer select-none px-4 py-3 flex items-center justify-between gap-3 border-b border-border">
            <div className="font-medium">{title}</div>
            <div className="flex items-center gap-2">{right}</div>
          </summary>
          <div className="p-4">{children}</div>
        </details>
      </CardContent>
    </Card>
  );
}

export default function AssortmentPlanner() {
  // Heatmap controls
  const [metric, setMetric] = useState<HeatMetric>("avg_qty");
  const [showRange, setShowRange] = useState(false);

  // Space Budget controls
  const [spaceMode, setSpaceMode] = useState<PlannerMode>("week");
  const [spaceLevel, setSpaceLevel] = useState<SpaceBudgetLevel>("famiglia");
  const [spaceAsPercent, setSpaceAsPercent] = useState(true);

  // Assortment Calendar controls
  const [calMode, setCalMode] = useState<PlannerMode>("week");
  const [calLevel, setCalLevel] = useState<SpaceBudgetLevel>("famiglia");

  // open state
  const [openMapWeek, setOpenMapWeek] = useState<Record<string, boolean>>({});
  const [openMapRoll4, setOpenMapRoll4] = useState<Record<string, boolean>>({});

  // multi-selezione nodi
  const [selectedWeekNodeIds, setSelectedWeekNodeIds] = useState<string[]>([]);
  const [selectedRoll4NodeIds, setSelectedRoll4NodeIds] = useState<string[]>([]);

  // Export state
  const [exporting, setExporting] = useState<string | null>(null);
  const [exportProgress, setExportProgress] = useState<{ label: string; fetched: number } | null>(null);

  // Current week
  const { currentWeek52, isLoading: weekLoading, error: weekError } = usePlannerCurrentWeek();

  // Space Budget
  const spaceBudget = usePlannerSpaceBudget(spaceMode, spaceLevel);

  // Assortment Calendar
  const assortmentCalendar = usePlannerAssortmentCalendar(calMode, calLevel);

  // WEEK nodes
  const weekNodes = usePlannerHeatmapNodes("week");
  const {
    rootIds: rootIdsWeek,
    nodesById: nodesByIdWeek,
    childrenByParent: childrenByParentWeek,
    isLoading: nodesLoadingWeek,
    error: nodesErrorWeek,
  } = weekNodes;

  // ROLL4 nodes
  const roll4Nodes = usePlannerHeatmapNodes("roll4");
  const {
    rootIds: rootIdsRoll4,
    nodesById: nodesByIdRoll4,
    childrenByParent: childrenByParentRoll4,
    isLoading: nodesLoadingRoll4,
    error: nodesErrorRoll4,
  } = roll4Nodes;

  // Visible ids
  const visibleNodeIdsWeek = useMemo(() => {
    return flattenVisibleIds(rootIdsWeek, nodesByIdWeek, childrenByParentWeek, openMapWeek);
  }, [rootIdsWeek, nodesByIdWeek, childrenByParentWeek, openMapWeek]);

  const visibleNodeIdsRoll4 = useMemo(() => {
    return flattenVisibleIds(rootIdsRoll4, nodesByIdRoll4, childrenByParentRoll4, openMapRoll4);
  }, [rootIdsRoll4, nodesByIdRoll4, childrenByParentRoll4, openMapRoll4]);

  const deferredVisibleWeek = useDeferredValue(visibleNodeIdsWeek);
  const deferredVisibleRoll4 = useDeferredValue(visibleNodeIdsRoll4);

  // Cells & ranges
  const weekCells = usePlannerHeatmapCells("week", deferredVisibleWeek);
  const weekRanges = usePlannerHeatmapRanges("week", showRange ? deferredVisibleWeek : []);
  const roll4Cells = usePlannerHeatmapCells("roll4", deferredVisibleRoll4);

  // Errors / loading
  const topError =
    weekError?.message ||
    nodesErrorWeek?.message ||
    nodesErrorRoll4?.message ||
    weekCells.error ||
    roll4Cells.error ||
    weekRanges.error ||
    spaceBudget.error ||
    assortmentCalendar.error;

  const topLoading = weekLoading;

  // Selection
  const toggleSelected = (mode: PlannerMode, nodeId: string) => {
    if (mode === "week") {
      setSelectedWeekNodeIds((prev) => (prev.includes(nodeId) ? prev.filter((x) => x !== nodeId) : [...prev, nodeId]));
    } else {
      setSelectedRoll4NodeIds((prev) => (prev.includes(nodeId) ? prev.filter((x) => x !== nodeId) : [...prev, nodeId]));
    }
  };

  const clearSelected = (mode: PlannerMode) => {
    if (mode === "week") setSelectedWeekNodeIds([]);
    else setSelectedRoll4NodeIds([]);
  };

  // ─────────────────────────────────────────────────────────────
  // Export
  // ─────────────────────────────────────────────────────────────
  const exportHeatmapMode = async (mode: PlannerMode) => {
    try {
      // ⚠️ La pivot ha senso SOLO per la vista Week
      if (mode !== "week") {
        alert("Export pivot disponibile solo per Heatmap Week");
        return;
      }

      const key = `heatmap_week_pivot_${metric}`;
      setExporting(key);
      setExportProgress({ label: "fetching", fetched: 0 });

      // 👉 CHIAMATA RPC (pivot SQL)
      const pageSize = 1000; // tipicamente coincide col cap server (1000). Puoi provare 2000 ma spesso verrà comunque tagliato a 1000.
      const all: AnyRow[] = [];
      let page = 0;

      while (true) {
        const resp = await apiGet("/api/v1/planner/heatmap-week-pivot", { metric, page, page_size: pageSize });
        const chunk = ((resp?.items) ?? []) as AnyRow[];
        all.push(...chunk);

        setExportProgress({ label: `fetching (${all.length})`, fetched: all.length });

        if (chunk.length < pageSize) break; // finito
        page += 1;
      }

      const rows = all;
      setExportProgress({ label: "writing_xlsx", fetched: rows.length });

      await exportToXlsx(`planner_${key}_${todayYmd()}`, [{ name: "heatmap_week", rows }]);
    } catch (e: any) {
      console.error(e);
      alert(e?.message ?? "Errore export heatmap pivot");
    } finally {
      setExporting(null);
      setExportProgress(null);
    }
  };

  const exportCalendarCurrent = async () => {
    try {
      const key = `calendar_${calMode}_${calLevel}`;
      setExporting(key);
      setExportProgress({ label: key, fetched: 0 });

      const rows = await fetchAllPaged<AnyRow>({
        table: ASSORT_EXPORT_SOURCE,
        select: ASSORT_EXPORT_SELECT,
        pageSize: 8000,
        orderBy: { column: "node_id", ascending: true },
        filters: (q) => q.eq("mode", calMode).eq("level", calLevel),
        onProgress: ({ fetched }) => setExportProgress({ label: key, fetched }),
      });

      setExportProgress({ label: "writing_xlsx", fetched: rows.length });

      await exportToXlsx(`planner_${key}_${todayYmd()}`, [{ name: key, rows }]);
    } catch (e: any) {
      console.error(e);
      alert(e?.message ?? "Errore export calendar");
    } finally {
      setExporting(null);
      setExportProgress(null);
    }
  };

  const exportSpaceBudgetCurrent = async () => {
    try {
      const key = `space_budget_${spaceMode}_${spaceLevel}`;
      setExporting(key);
      setExportProgress({ label: key, fetched: spaceBudget.rows.length });

      await exportToXlsx(`planner_${key}_${todayYmd()}`, [{ name: key, rows: spaceBudget.rows as any[] }]);
    } catch (e: any) {
      console.error(e);
      alert(e?.message ?? "Errore export space budget");
    } finally {
      setExporting(null);
      setExportProgress(null);
    }
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between gap-3">
        <div className="flex flex-col">
          <h1 className="text-2xl font-bold text-foreground">Assortment Planner</h1>
          <div className="text-sm text-muted-foreground">
            Settimana corrente: <strong>W{String(currentWeek52).padStart(2, "0")}</strong>
          </div>
          {exportProgress && (
            <div className="text-xs text-muted-foreground mt-1">
              Export: <span className="font-medium">{exportProgress.label}</span> — righe:{" "}
              <span className="tabular-nums">{exportProgress.fetched.toLocaleString("it-IT")}</span>
            </div>
          )}
        </div>
      </div>

      {topError && (
        <Card className="border-destructive">
          <CardContent className="py-4">
            <p className="text-destructive text-sm">{topError}</p>
          </CardContent>
        </Card>
      )}

      {topLoading && (
        <Card>
          <CardContent className="py-12 flex items-center justify-center">
            <Loader2 className="w-6 h-6 animate-spin text-muted-foreground" />
            <span className="ml-2 text-muted-foreground">Caricamento...</span>
          </CardContent>
        </Card>
      )}

      {/* Heatmap Week */}
      <Folder
        title="Heatmap Week"
        right={
          <>
            {weekCells.loading && <Loader2 className="w-4 h-4 animate-spin text-muted-foreground" />}
            {nodesLoadingWeek && <Loader2 className="w-4 h-4 animate-spin text-muted-foreground" />}

            <button
              type="button"
              onClick={() => exportHeatmapMode("week")}
              disabled={exporting != null}
              className="inline-flex items-center gap-2 rounded-md border border-border bg-background px-3 py-2 text-xs hover:bg-muted disabled:opacity-50"
              title="Esporta Heatmap Week (flat)"
            >
              <Download className="w-4 h-4" />
              Export
            </button>
          </>
        }
        defaultOpen
      >
        <div className="flex flex-wrap items-center gap-4 mb-4">
          <div className="flex items-center gap-2">
            <span className="text-sm text-muted-foreground">Metrica:</span>
            <Select value={metric} onValueChange={(v) => setMetric(v as HeatMetric)}>
              <SelectTrigger className="w-[170px]">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {METRIC_OPTIONS.map((opt) => (
                  <SelectItem key={opt.value} value={opt.value}>
                    {opt.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="flex items-center gap-2">
            <Switch id="show-range" checked={showRange} onCheckedChange={setShowRange} />
            <Label htmlFor="show-range" className="text-sm text-muted-foreground cursor-pointer">
              Range (min/max) — solo Week
            </Label>
            {showRange && weekRanges.loading && <Loader2 className="w-3 h-3 animate-spin text-muted-foreground" />}
          </div>

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => clearSelected("week")}
              className="inline-flex items-center gap-2 rounded-md border border-border bg-background px-3 py-2 text-xs hover:bg-muted disabled:opacity-50"
              disabled={selectedWeekNodeIds.length === 0}
              title="Svuota selezione"
            >
              <X className="w-4 h-4" />
              Clear selection
            </button>
            <span className="text-xs text-muted-foreground">
              Selezionati: <span className="tabular-nums">{selectedWeekNodeIds.length}</span>
            </span>
          </div>
        </div>

        <div className="border border-border rounded-md mb-4">
          <HeatmapNodeChart
            title="Andamento (Week)"
            nodeIds={selectedWeekNodeIds}
            nodesById={nodesByIdWeek}
            cellsByNode={weekCells.cellsByNode}
            metric={metric}
            currentWeek52={currentWeek52}
          />
        </div>

        {nodesLoadingWeek ? null : rootIdsWeek.length === 0 ? (
          <div className="text-center text-muted-foreground">Nessun dato disponibile (week)</div>
        ) : (
          <HeatmapTreeTable
            rootIds={rootIdsWeek}
            nodesById={nodesByIdWeek}
            childrenByParent={childrenByParentWeek}
            openMap={openMapWeek}
            setOpenMap={setOpenMapWeek}
            cellsByNode={weekCells.cellsByNode}
            metric={metric}
            currentWeek52={currentWeek52}
            rangesByNode={weekRanges.rangesByNode}
            showRange={showRange}
            selectedNodeIds={selectedWeekNodeIds}
            onToggleSelectNode={(nodeId) => toggleSelected("week", nodeId)}
          />
        )}
      </Folder>

      {/* Heatmap Roll4 */}
      <Folder
        title="Heatmap Roll4"
        right={
          <>
            {roll4Cells.loading && <Loader2 className="w-4 h-4 animate-spin text-muted-foreground" />}
            {nodesLoadingRoll4 && <Loader2 className="w-4 h-4 animate-spin text-muted-foreground" />}

            <button
              type="button"
              onClick={() => exportHeatmapMode("roll4")}
              disabled={exporting != null}
              className="inline-flex items-center gap-2 rounded-md border border-border bg-background px-3 py-2 text-xs hover:bg-muted disabled:opacity-50"
              title="Esporta Heatmap Roll4 (flat)"
            >
              <Download className="w-4 h-4" />
              Export
            </button>
          </>
        }
        defaultOpen={false}
      >
        <div className="flex items-center gap-2 mb-4">
          <button
            type="button"
            onClick={() => clearSelected("roll4")}
            className="inline-flex items-center gap-2 rounded-md border border-border bg-background px-3 py-2 text-xs hover:bg-muted disabled:opacity-50"
            disabled={selectedRoll4NodeIds.length === 0}
            title="Svuota selezione"
          >
            <X className="w-4 h-4" />
            Clear selection
          </button>
          <span className="text-xs text-muted-foreground">
            Selezionati: <span className="tabular-nums">{selectedRoll4NodeIds.length}</span>
          </span>
        </div>

        <div className="border border-border rounded-md mb-4">
          <HeatmapNodeChart
            title="Andamento (Roll4)"
            nodeIds={selectedRoll4NodeIds}
            nodesById={nodesByIdRoll4}
            cellsByNode={roll4Cells.cellsByNode}
            metric={metric}
            currentWeek52={currentWeek52}
          />
        </div>

        {nodesLoadingRoll4 ? null : rootIdsRoll4.length === 0 ? (
          <div className="text-center text-muted-foreground">Nessun dato disponibile (roll4)</div>
        ) : (
          <HeatmapTreeTable
            rootIds={rootIdsRoll4}
            nodesById={nodesByIdRoll4}
            childrenByParent={childrenByParentRoll4}
            openMap={openMapRoll4}
            setOpenMap={setOpenMapRoll4}
            cellsByNode={roll4Cells.cellsByNode}
            metric={metric}
            currentWeek52={currentWeek52}
            rangesByNode={{}}
            showRange={false}
            selectedNodeIds={selectedRoll4NodeIds}
            onToggleSelectNode={(nodeId) => toggleSelected("roll4", nodeId)}
          />
        )}
      </Folder>

      {/* Assortment Calendar */}
      <Folder
        title="Assortment Calendar"
        right={
          <>
            {assortmentCalendar.loading && <Loader2 className="w-4 h-4 animate-spin text-muted-foreground" />}

            <button
              type="button"
              onClick={exportCalendarCurrent}
              disabled={exporting != null}
              className="inline-flex items-center gap-2 rounded-md border border-border bg-background px-3 py-2 text-xs hover:bg-muted disabled:opacity-50"
              title="Esporta Calendar (vista corrente)"
            >
              <Download className="w-4 h-4" />
              Export
            </button>
          </>
        }
        defaultOpen={false}
      >
        <div className="flex items-center gap-3 mb-4">
          <Select value={calMode} onValueChange={(v) => setCalMode(v as PlannerMode)}>
            <SelectTrigger className="w-[120px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="week">week</SelectItem>
              <SelectItem value="roll4">roll4</SelectItem>
            </SelectContent>
          </Select>

          <Select value={calLevel} onValueChange={(v) => setCalLevel(v as SpaceBudgetLevel)}>
            <SelectTrigger className="w-[140px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="famiglia">famiglia</SelectItem>
              <SelectItem value="categoria">categoria</SelectItem>
            </SelectContent>
          </Select>
        </div>

        {assortmentCalendar.rows.length === 0 && !assortmentCalendar.loading ? (
          <div className="text-sm text-muted-foreground">Nessun dato Calendar (controlla refresh + RPC).</div>
        ) : (
          <AssortmentCalendar
            rows={assortmentCalendar.rows}
            currentWeek52={currentWeek52}
            topN={60}
            nodesById={calMode === "week" ? nodesByIdWeek : nodesByIdRoll4}
            onSelect={(nodeId, week52) => {
              console.log("Selected", { nodeId, week52 });
            }}
          />
        )}
      </Folder>

      {/* Space Budget Timeline */}
      <Folder
        title="Space Budget Timeline"
        right={
          <>
            {spaceBudget.loading && <Loader2 className="w-4 h-4 animate-spin text-muted-foreground" />}

            <button
              type="button"
              onClick={exportSpaceBudgetCurrent}
              disabled={exporting != null}
              className="inline-flex items-center gap-2 rounded-md border border-border bg-background px-3 py-2 text-xs hover:bg-muted disabled:opacity-50"
              title="Esporta Space Budget (vista corrente)"
            >
              <Download className="w-4 h-4" />
              Export
            </button>
          </>
        }
        defaultOpen={false}
      >
        <div className="flex items-center gap-3 mb-4">
          <Select value={spaceMode} onValueChange={(v) => setSpaceMode(v as PlannerMode)}>
            <SelectTrigger className="w-[120px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="week">week</SelectItem>
              <SelectItem value="roll4">roll4</SelectItem>
            </SelectContent>
          </Select>

          <Select value={spaceLevel} onValueChange={(v) => setSpaceLevel(v as SpaceBudgetLevel)}>
            <SelectTrigger className="w-[140px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="famiglia">famiglia</SelectItem>
              <SelectItem value="categoria">categoria</SelectItem>
            </SelectContent>
          </Select>

          <div className="flex items-center gap-2">
            <Switch id="space-percent" checked={spaceAsPercent} onCheckedChange={setSpaceAsPercent} />
            <Label htmlFor="space-percent" className="text-sm text-muted-foreground cursor-pointer">
              {spaceAsPercent ? "% budget" : "m² raw"}
            </Label>
          </div>
        </div>

        {spaceBudget.rows.length === 0 && !spaceBudget.loading ? (
          <div className="text-sm text-muted-foreground">Nessun dato Space Budget (controlla refresh + RPC).</div>
        ) : (
          <SpaceBudgetTimeline
            rows={spaceBudget.rows}
            showAsPercent={spaceAsPercent}
            topN={12}
            currentWeek52={currentWeek52}
          />
        )}
      </Folder>
    </div>
  );
}

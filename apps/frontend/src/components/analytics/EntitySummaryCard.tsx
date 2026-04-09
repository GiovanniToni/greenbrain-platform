// src/components/analytics/EntitySummaryCard.tsx
import React, { useEffect, useMemo, useState, useCallback } from "react";
import { ChevronDown, ChevronRight } from "lucide-react";

import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import type { CatalogItem } from "@/hooks/useAnalyticsCatalog";
import type { SeriesDataPoint } from "@/hooks/useAnalyticsSeries";
import type { RangeTotals } from "@/hooks/useAnalyticsRangeTotals";
import { useAnalyticsEntitySummary } from "@/hooks/useAnalyticsEntitySummary";

export type SummaryTotals = {
  qty_tot: number;
  imponibile_tot: number;
  num_articoli_tot: number;
};

export type SummaryNode = {
  entity_type: "fascia" | "categoria" | "famiglia" | "fascia_prezzo" | "articolo";
  entity_key: string;
  label: string;
  qty_tot: number;
  imponibile_tot?: number;
  num_articoli_tot?: number;
  children?: SummaryNode[];

  pot_size?: string | number | null;
  prezzo?: number | string | null;
  extra?: any;
};

export type EntitySummaryTree = {
  entity_type: "famiglia" | "categoria" | "fascia" | "fascia_prezzo";
  entity_key: string;
  date_from: string;
  date_to: string;
  totals: SummaryTotals;
  tree: SummaryNode[] | SummaryNode;
};

function fmtInt(n?: number | null) {
  if (n == null) return "n/d";
  return Number(n).toLocaleString("it-IT", { maximumFractionDigits: 0 });
}
function fmtDec(n?: number | null, decimals = 1) {
  if (n == null) return "n/d";
  return Number(n).toLocaleString("it-IT", { minimumFractionDigits: decimals, maximumFractionDigits: decimals });
}
function fmtMoney(n?: number | null) {
  if (n == null) return "n/d";
  return Number(n).toLocaleString("it-IT", { maximumFractionDigits: 2 });
}
function norm(s: any) {
  return String(s ?? "")
    .trim()
    .toLowerCase();
}
function isoDay(v: any) {
  return String(v ?? "").slice(0, 10);
}
function n(v: any): number {
  const x = Number(v);
  return Number.isFinite(x) ? x : 0;
}

const ENTITY_TYPE_LABELS: Record<string, string> = {
  famiglia: "Famiglia",
  categoria: "Categoria",
  fascia: "Fascia",
  fascia_prezzo: "Fascia Prezzo",
  articolo: "Articolo",
};

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
  "50 - 59€",
  "60 - 69€",
  "70 - 99,99€",
  "100 - 149,99€",
  "150 - 199,99€",
  "200€ - >",
];
const FP_INDEX = new Map(FASCIA_PREZZO_ORDER.map((l, i) => [norm(l), i]));

function sortAlphaIT(a: string, b: string) {
  return (a ?? "").localeCompare(b ?? "", "it-IT", { sensitivity: "base" });
}

function parsePotSize(p: any): number | null {
  if (p == null) return null;
  const s = String(p).trim();
  if (!s) return null;
  const m = s.replace(",", ".").match(/(\d+(\.\d+)?)/);
  if (!m) return null;
  const num = Number(m[1]);
  return Number.isFinite(num) ? num : null;
}

const TYPE_PRIORITY: Record<string, number> = {
  fascia: 1,
  categoria: 2,
  famiglia: 3,
  fascia_prezzo: 4,
  articolo: 5,
};

function sortChildren(children: SummaryNode[]) {
  const valid = children.filter((node) => {
    if (!isValidNode(node)) {
      console.warn("[EntitySummaryCard] sortChildren: skipping invalid node", node);
      return false;
    }
    return true;
  });
  return [...valid].sort((a, b) => {
    const ta = TYPE_PRIORITY[a.entity_type] ?? 99;
    const tb = TYPE_PRIORITY[b.entity_type] ?? 99;
    if (ta !== tb) return ta - tb;

    if (a.entity_type === "fascia_prezzo") {
      const ia = FP_INDEX.has(norm(a.label)) ? (FP_INDEX.get(norm(a.label)) as number) : 999;
      const ib = FP_INDEX.has(norm(b.label)) ? (FP_INDEX.get(norm(b.label)) as number) : 999;
      if (ia !== ib) return ia - ib;
      return sortAlphaIT(a.label, b.label);
    }

    if (a.entity_type === "articolo") {
      const pa = parsePotSize((a as any).pot_size ?? (a as any).extra?.pot_size);
      const pb = parsePotSize((b as any).pot_size ?? (b as any).extra?.pot_size);

      const aHas = pa != null;
      const bHas = pb != null;

      if (aHas && bHas && pa !== pb) return (pa as number) - (pb as number);
      if (aHas && !bHas) return -1;
      if (!aHas && bHas) return 1;

      const pra = Number((a as any).prezzo ?? (a as any).extra?.prezzo ?? (a as any).extra?.prezzo_iva_inclusa);
      const prb = Number((b as any).prezzo ?? (b as any).extra?.prezzo ?? (b as any).extra?.prezzo_iva_inclusa);
      const aPr = Number.isFinite(pra) ? pra : Number.POSITIVE_INFINITY;
      const bPr = Number.isFinite(prb) ? prb : Number.POSITIVE_INFINITY;
      if (aPr !== bPr) return aPr - bPr;

      return sortAlphaIT(a.label, b.label);
    }

    return sortAlphaIT(a.label, b.label);
  });
}

type HierCtx = {
  fascia?: string | null;
  fascia_label?: string | null;
  categoria?: string | null;
  categoria_label?: string | null;
  famiglia?: string | null;
  famiglia_label?: string | null;
  fascia_prezzo?: string | null;
  fascia_prezzo_label?: string | null;
};

function nodeId(node: SummaryNode) {
  return `${node.entity_type}::${node.entity_key}`;
}

function isValidNode(node: any): node is SummaryNode {
  return node != null && typeof node.entity_type === "string" && node.entity_type.length > 0;
}

function StatTile({ label, value, sub, emphasis }: { label: string; value: string; sub?: string; emphasis?: boolean }) {
  return (
    <div className={`rounded-md border px-3 py-2 ${emphasis ? "bg-primary/10 border-primary/30" : "bg-muted/40"}`}>
      <p className="text-[10px] uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className={`text-base font-semibold tabular-nums ${emphasis ? "text-primary" : ""}`}>{value}</p>
      {sub ? <p className="text-[11px] text-muted-foreground truncate">{sub}</p> : null}
    </div>
  );
}

function SkeletonTile({ label }: { label: string }) {
  return (
    <div className="rounded-md border px-3 py-2 bg-muted/30">
      <p className="text-[10px] uppercase tracking-wide text-muted-foreground">{label}</p>
      <div className="mt-1 h-5 w-20 rounded bg-muted/60 animate-pulse" />
      <div className="mt-2 h-3 w-28 rounded bg-muted/60 animate-pulse" />
    </div>
  );
}

function computeLastN(rows: SeriesDataPoint[], nDays: number): { qty: number; imp: number; count: number } {
  const slice = rows.slice(Math.max(0, rows.length - nDays));
  const qty = slice.reduce((s, r) => s + Number(r.qty_venduta_tot ?? 0), 0);
  const imp = slice.reduce((s, r) => s + Number((r as any).imponibile_netto_tot ?? 0), 0);
  return { qty, imp, count: slice.length };
}

function pctChange(curr: number, prev: number) {
  if (!Number.isFinite(curr) || !Number.isFinite(prev)) return null;
  if (prev === 0 && curr === 0) return 0;
  if (prev === 0 && curr !== 0) return null;
  return ((curr - prev) / Math.abs(prev)) * 100;
}

/**
 * ✅ Normalizza la selezione “come da search”:
 * - click fascia_prezzo nel tree => seleziona FAMIGLIA mantenendo gerarchia + filtro fascia_prezzo
 */
function normalizeSelectionForUI(node: SummaryNode, nextCtx: HierCtx): CatalogItem {
  const base: any = {
    entity_type: node.entity_type,
    entity_key: node.entity_key,
    label: node.label,
    ...nextCtx,
  };

  if (node.entity_type === "fascia_prezzo" && nextCtx.famiglia) {
    return {
      entity_type: "famiglia",
      entity_key: nextCtx.famiglia,
      label: nextCtx.famiglia_label ?? nextCtx.famiglia,

      fascia: nextCtx.fascia ?? null,
      fascia_label: nextCtx.fascia_label ?? null,
      categoria: nextCtx.categoria ?? null,
      categoria_label: nextCtx.categoria_label ?? null,
      famiglia: nextCtx.famiglia ?? null,
      famiglia_label: nextCtx.famiglia_label ?? null,
      fascia_prezzo: nextCtx.fascia_prezzo ?? null,
      fascia_prezzo_label: nextCtx.fascia_prezzo_label ?? null,
    } as any;
  }

  return base as CatalogItem;
}

function buildSelectionFromBreadcrumb(
  clicked: { type: string; key: string; label: string },
  selectedEntity: CatalogItem,
): CatalogItem {
  const e: any = selectedEntity as any;

  const base: any = {
    entity_type: clicked.type,
    entity_key: clicked.key,
    label: clicked.label,

    fascia: e.fascia ?? null,
    fascia_label: e.fascia_label ?? null,
    categoria: e.categoria ?? null,
    categoria_label: e.categoria_label ?? null,
    famiglia: e.famiglia ?? null,
    famiglia_label: e.famiglia_label ?? null,
    fascia_prezzo: e.fascia_prezzo ?? null,
    fascia_prezzo_label: e.fascia_prezzo_label ?? null,
  };

  if (clicked.type === "fascia") {
    base.fascia = clicked.key;
    base.fascia_label = clicked.label;
    base.categoria = null;
    base.categoria_label = null;
    base.famiglia = null;
    base.famiglia_label = null;
    base.fascia_prezzo = null;
    base.fascia_prezzo_label = null;
  }

  if (clicked.type === "categoria") {
    base.categoria = clicked.key;
    base.categoria_label = clicked.label;
    base.famiglia = null;
    base.famiglia_label = null;
    base.fascia_prezzo = null;
    base.fascia_prezzo_label = null;
  }

  if (clicked.type === "famiglia") {
    base.famiglia = clicked.key;
    base.famiglia_label = clicked.label;
    base.fascia_prezzo = null;
    base.fascia_prezzo_label = null;
  }

  if (clicked.type === "fascia_prezzo") {
    if (e.famiglia) {
      return {
        entity_type: "famiglia",
        entity_key: e.famiglia,
        label: e.famiglia_label ?? e.famiglia,
        fascia: e.fascia ?? null,
        fascia_label: e.fascia_label ?? null,
        categoria: e.categoria ?? null,
        categoria_label: e.categoria_label ?? null,
        famiglia: e.famiglia ?? null,
        famiglia_label: e.famiglia_label ?? null,
        fascia_prezzo: clicked.key,
        fascia_prezzo_label: clicked.label,
      } as any;
    }
  }

  return base as CatalogItem;
}

function TreeNode({
  node,
  ctx,
  openMap,
  setOpenMap,
  onSelect,
}: {
  node: SummaryNode;
  ctx: HierCtx;
  openMap: Record<string, boolean>;
  setOpenMap: React.Dispatch<React.SetStateAction<Record<string, boolean>>>;
  onSelect: (item: CatalogItem) => void;
}) {
  if (!isValidNode(node)) {
    console.warn("[EntitySummaryCard] TreeNode: received invalid node", node);
    return null;
  }
  const id = nodeId(node);
  const hasChildren = !!(node.children && node.children.length > 0);
  const isOpen = !!openMap[id];

  const nextCtx: HierCtx = { ...ctx };
  if (node.entity_type === "fascia") {
    nextCtx.fascia = node.entity_key;
    nextCtx.fascia_label = node.label;
  } else if (node.entity_type === "categoria") {
    nextCtx.categoria = node.entity_key;
    nextCtx.categoria_label = node.label;
  } else if (node.entity_type === "famiglia") {
    nextCtx.famiglia = node.entity_key;
    nextCtx.famiglia_label = node.label;
  } else if (node.entity_type === "fascia_prezzo") {
    nextCtx.fascia_prezzo = node.entity_key;
    nextCtx.fascia_prezzo_label = node.label;
  }

  const handleClick = () => {
    const normalized = normalizeSelectionForUI(node, nextCtx);
    onSelect(normalized);
  };

  return (
    <div className="border-l border-border/50 pl-2">
      <div className="flex items-center justify-between gap-2 py-1 hover:bg-muted/50 rounded px-1">
        <div className="flex items-center gap-1 flex-1 min-w-0">
          {hasChildren ? (
            <Button
              variant="ghost"
              size="icon"
              className="h-5 w-5 shrink-0"
              onClick={(e) => {
                e.stopPropagation();
                setOpenMap((prev) => ({ ...prev, [id]: !prev[id] }));
              }}
              aria-label={isOpen ? "Contrai" : "Espandi"}
            >
              {isOpen ? <ChevronDown className="w-3 h-3" /> : <ChevronRight className="w-3 h-3" />}
            </Button>
          ) : (
            <span className="w-5 shrink-0" />
          )}

          <button className="text-left truncate hover:underline focus:outline-none" onClick={handleClick}>
            <span className="text-sm font-medium">{node.label}</span>
            <span className="ml-1 text-[10px] text-muted-foreground uppercase">{node.entity_type}</span>
          </button>
        </div>

        {/* niente metriche in modalità gerarchia */}
        <div className="w-6 shrink-0" />
      </div>

      {hasChildren && isOpen ? (
        <div className="ml-2">
          {sortChildren(node.children ?? []).map((c) => (
            <TreeNode
              key={nodeId(c)}
              node={c}
              ctx={nextCtx}
              openMap={openMap}
              setOpenMap={setOpenMap}
              onSelect={onSelect}
            />
          ))}
        </div>
      ) : null}
    </div>
  );
}

export type EntitySummaryCardProps = {
  selectedEntity: CatalogItem;
  onSelect: (item: CatalogItem) => void;
  seriesData?: SeriesDataPoint[];
  dateFrom?: string;
  dateTo?: string;
  minAvailableDate?: string | null;
  maxAvailableDate?: string | null;

  rangeTotals?: RangeTotals | null;
  rangeTotalsLoading?: boolean;
};

function collectArticleKeys(root: SummaryNode[] | SummaryNode | null): string[] {
  if (!root) return [];
  const out: string[] = [];

  const walk = (n: SummaryNode) => {
    if (!isValidNode(n)) {
      console.warn("[EntitySummaryCard] collectArticleKeys: skipping invalid node", n);
      return;
    }
    if (n.entity_type === "articolo") out.push(String(n.entity_key ?? "").trim());
    for (const c of n.children ?? []) walk(c);
  };

  const arr = Array.isArray(root) ? root : [root];
  arr.forEach(walk);

  return Array.from(new Set(out.filter(Boolean)));
}

function patchArticleTotalsInTree(
  root: SummaryNode[] | SummaryNode,
  totalsByKey: Map<string, { qty: number; imp: number }>,
): SummaryNode[] | SummaryNode {
  const patchNode = (n0: SummaryNode): SummaryNode => {
    if (!isValidNode(n0)) return n0;
    let n = n0;

    if (n.entity_type === "articolo") {
      const k = String(n.entity_key ?? "").trim();
      const t = totalsByKey.get(k);
      if (t) {
        n = {
          ...n,
          qty_tot: t.qty,
          imponibile_tot: t.imp,
        };
      }
    }

    if (n.children && n.children.length > 0) {
      return { ...n, children: n.children.map(patchNode) };
    }

    return n;
  };

  if (Array.isArray(root)) return root.map(patchNode);
  return patchNode(root);
}

export function EntitySummaryCard(props: EntitySummaryCardProps) {
  const {
    selectedEntity,
    onSelect,
    seriesData,
    dateFrom,
    dateTo,
    minAvailableDate,
    maxAvailableDate,
    rangeTotals,
    rangeTotalsLoading,
  } = props;

  const breadcrumb = useMemo(() => {
    const e: any = selectedEntity as any;

    const parts: { type: string; key: string; label: string; isSelected: boolean }[] = [];
    const push = (type: string, key?: string | null, label?: string | null, isSelected = false) => {
      if (!key && !label) return;
      parts.push({ type, key: key ?? label ?? "", label: label ?? key ?? "", isSelected });
    };

    push("fascia", e.fascia ?? null, e.fascia_label ?? null, selectedEntity.entity_type === "fascia");
    push("categoria", e.categoria ?? null, e.categoria_label ?? null, selectedEntity.entity_type === "categoria");
    push("famiglia", e.famiglia ?? null, e.famiglia_label ?? null, selectedEntity.entity_type === "famiglia");

    push(
      "fascia_prezzo",
      e.fascia_prezzo ?? null,
      e.fascia_prezzo_label ?? null,
      selectedEntity.entity_type === "fascia_prezzo",
    );

    const already = parts.some((p) => p.key === selectedEntity.entity_key || p.label === selectedEntity.label);
    if (!already) push(selectedEntity.entity_type, selectedEntity.entity_key, selectedEntity.label, true);
    else {
      for (const p of parts) {
        if (p.key === selectedEntity.entity_key || p.label === selectedEntity.label) p.isSelected = true;
      }
    }

    const seen = new Set<string>();
    return parts.filter((p) => {
      const k = (p.label ?? "").toLowerCase();
      if (!k) return false;
      if (seen.has(k)) return false;
      seen.add(k);
      return true;
    });
  }, [selectedEntity]);

  const baseFromSeries = useMemo(() => {
    const rows = seriesData ?? [];
    const numDays = rows.length;

    const totalQty = rows.reduce((s, r) => s + (r.qty_venduta_tot || 0), 0);
    const totalImp = rows.reduce((s, r) => s + ((r as any).imponibile_netto_tot || 0), 0);

    let activeDays = 0;
    let zeroDays = 0;
    let minDay: { date: string; qty: number } | null = null;
    let maxDay: { date: string; qty: number } | null = null;

    for (const r of rows) {
      const q = r.qty_venduta_tot || 0;
      if (q > 0) activeDays++;
      if (q === 0) zeroDays++;

      if (!minDay || q < minDay.qty) minDay = { date: r.data, qty: q };
      if (!maxDay || q > maxDay.qty) maxDay = { date: r.data, qty: q };
    }

    const avgQty = numDays > 0 ? totalQty / numDays : null;
    const avgImp = numDays > 0 ? totalImp / numDays : null;
    const avgPrice = totalQty > 0 ? totalImp / totalQty : null;

    return { numDays, totalQty, totalImp, activeDays, zeroDays, avgQty, avgImp, avgPrice, minDay, maxDay };
  }, [seriesData]);

  const base = useMemo(() => {
    if (rangeTotals) {
      const days = Number((rangeTotals as any).days ?? 0) || 0;
      const qty = Number((rangeTotals as any).qty_tot ?? 0) || 0;
      const imp = Number((rangeTotals as any).imp_tot ?? 0) || 0;

      const avgQty = days > 0 ? qty / days : null;
      const avgImp = days > 0 ? imp / days : null;
      const avgPrice = qty > 0 ? imp / qty : null;

      const minDay = (rangeTotals as any).min_day
        ? { date: (rangeTotals as any).min_day, qty: Number((rangeTotals as any).min_qty ?? 0) || 0 }
        : null;
      const maxDay = (rangeTotals as any).max_day
        ? { date: (rangeTotals as any).max_day, qty: Number((rangeTotals as any).max_qty ?? 0) || 0 }
        : null;

      const activeDays = Number((rangeTotals as any).active_days ?? 0) || 0;
      const zeroDays = Number((rangeTotals as any).zero_days ?? 0) || 0;

      return {
        numDays: days,
        totalQty: qty,
        totalImp: imp,
        activeDays,
        zeroDays,
        avgQty,
        avgImp,
        avgPrice,
        minDay,
        maxDay,
        source: "rpc" as const,
      };
    }

    return {
      ...baseFromSeries,
      source: "series" as const,
    };
  }, [rangeTotals, baseFromSeries]);

  const extraKpis = useMemo(() => {
    const rows = (seriesData ?? []).filter((r) => r && r.data);
    if (rows.length < 14) return null;

    const last7 = computeLastN(rows, 7);
    const prev7 = computeLastN(rows.slice(0, Math.max(0, rows.length - 7)), 7);

    const last30 = computeLastN(rows, 30);
    const prev30 = computeLastN(rows.slice(0, Math.max(0, rows.length - 30)), 30);

    const qty7 = pctChange(last7.qty, prev7.qty);
    const imp7 = pctChange(last7.imp, prev7.imp);
    const qty30 = pctChange(last30.qty, prev30.qty);
    const imp30 = pctChange(last30.imp, prev30.imp);

    return { qty7, imp7, qty30, imp30, last7, last30 };
  }, [seriesData]);

  const activityRate = useMemo(() => {
    if (!base.numDays || base.numDays <= 0) return null;
    return (base.activeDays / base.numDays) * 100;
  }, [base.numDays, base.activeDays]);

  const [openDetails, setOpenDetails] = useState(false);
  const [openMap, setOpenMap] = useState<Record<string, boolean>>({});

  const { data: tree, loading: treeLoading, error: treeError, refetch: refetchTree } = useAnalyticsEntitySummary();

  useEffect(() => {
    if (!openDetails) return;
    if (!dateFrom || !dateTo) return;

    const e: any = selectedEntity as any;

    refetchTree({
      p_entity_type: selectedEntity.entity_type,
      p_entity_key: selectedEntity.entity_key,
      p_date_from: dateFrom,
      p_date_to: dateTo,

      p_fascia: e.fascia ?? null,
      p_categoria: e.categoria ?? null,
      p_famiglia: e.famiglia ?? null,
      p_fascia_prezzo: e.fascia_prezzo ?? null,
    });
  }, [openDetails, selectedEntity, dateFrom, dateTo, refetchTree]);

  const buildOpenMapForSelectedPath = useCallback((summary: EntitySummaryTree | null, selected: CatalogItem) => {
    const map: Record<string, boolean> = {};
    if (!summary) return map;

    const roots = Array.isArray(summary.tree) ? (summary.tree as SummaryNode[]) : ([summary.tree] as SummaryNode[]);
    const e: any = selected as any;

    const sel = {
      fascia: e.fascia ?? (selected.entity_type === "fascia" ? selected.entity_key : null),
      categoria: e.categoria ?? (selected.entity_type === "categoria" ? selected.entity_key : null),
      famiglia: e.famiglia ?? (selected.entity_type === "famiglia" ? selected.entity_key : null),
      fascia_prezzo: e.fascia_prezzo ?? (selected.entity_type === "fascia_prezzo" ? selected.entity_key : null),
      articolo: selected.entity_type === "articolo" ? selected.entity_key : null,
    };

    const shouldOpen = (nd: SummaryNode) => nd.entity_type !== "articolo";

    const matchNode = (nd: SummaryNode) => {
      if (nd.entity_type === "fascia" && sel.fascia) return norm(nd.entity_key) === norm(sel.fascia);
      if (nd.entity_type === "categoria" && sel.categoria) return norm(nd.entity_key) === norm(sel.categoria);
      if (nd.entity_type === "famiglia" && sel.famiglia) return norm(nd.entity_key) === norm(sel.famiglia);
      if (nd.entity_type === "fascia_prezzo" && sel.fascia_prezzo)
        return norm(nd.entity_key) === norm(sel.fascia_prezzo);
      if (nd.entity_type === "articolo" && sel.articolo) return norm(nd.entity_key) === norm(sel.articolo);
      return false;
    };

    const dfs = (nd: SummaryNode): boolean => {
      if (!isValidNode(nd)) {
        console.warn("[EntitySummaryCard] buildOpenMapForSelectedPath: skipping invalid node", nd);
        return false;
      }
      const hit = matchNode(nd);
      const kids = nd.children ?? [];
      let childHit = false;
      for (const c of kids) if (dfs(c)) childHit = true;

      if ((hit || childHit) && shouldOpen(nd)) map[nodeId(nd)] = true;
      return hit || childHit;
    };

    roots.forEach(dfs);
    return map;
  }, []);

  useEffect(() => {
    if (!openDetails) return;
    setOpenMap(buildOpenMapForSelectedPath(tree as any, selectedEntity));
  }, [openDetails, tree, selectedEntity, buildOpenMapForSelectedPath]);

  const effectiveTree = tree as any;

  const nodes = useMemo(() => {
    if (!effectiveTree) return [];
    const raw: any[] = Array.isArray(effectiveTree.tree) ? effectiveTree.tree : [effectiveTree.tree];
    return raw.filter((n) => {
      if (!isValidNode(n)) {
        console.warn("[EntitySummaryCard] nodes: dropping invalid tree entry", n);
        return false;
      }
      return true;
    });
  }, [effectiveTree]);

  const showLoadingSummary = !!rangeTotalsLoading && !rangeTotals;

  return (
    <Card className="p-4">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-2 mb-3">
        <div className="min-w-0">
          <h3 className="text-base font-semibold truncate">
            {ENTITY_TYPE_LABELS[selectedEntity.entity_type] ?? selectedEntity.entity_type}: {selectedEntity.label}
          </h3>

          {/* Breadcrumb */}
          <div className="flex flex-wrap items-center gap-1 text-xs text-muted-foreground mt-1">
            {breadcrumb.map((p, idx) => (
              <span key={idx} className="flex items-center gap-1">
                {idx > 0 && <span className="text-muted-foreground/60">›</span>}
                <button
                  className={`hover:underline ${p.isSelected ? "font-semibold text-foreground" : ""}`}
                  onClick={() => {
                    if (!p.key) return;
                    onSelect(
                      buildSelectionFromBreadcrumb({ type: p.type, key: p.key, label: p.label }, selectedEntity),
                    );
                  }}
                >
                  {p.label}
                </button>
              </span>
            ))}
          </div>

          {/* Bounds + range */}
          <div className="mt-1 text-[11px] text-muted-foreground">
            {dateFrom && dateTo ? (
              <span>
                Range: <span className="tabular-nums">{dateFrom}</span> → <span className="tabular-nums">{dateTo}</span>
              </span>
            ) : (
              <span>Range: n/d</span>
            )}
            <span className="mx-2">•</span>
            <span>
              Dati: <span className="tabular-nums">{minAvailableDate ?? "n/d"}</span> →{" "}
              <span className="tabular-nums">{maxAvailableDate ?? "n/d"}</span>
            </span>
            <span className="mx-2">•</span>
            <span className="tabular-nums">src: {base.source === "rpc" ? "rangeTotals" : "seriesData"}</span>
          </div>
        </div>

        <div className="shrink-0">
          <Button variant="ghost" size="sm" className="h-7 text-xs" onClick={() => setOpenDetails((v) => !v)}>
            {openDetails ? (
              <>
                <ChevronDown className="w-3 h-3 mr-1" /> Nascondi dettagli
              </>
            ) : (
              <>
                <ChevronRight className="w-3 h-3 mr-1" /> Mostra dettagli
              </>
            )}
          </Button>
        </div>
      </div>

      {/* METRICHE BASE + KPI */}
      <div className="bg-muted/30 rounded-lg p-3 border border-border/30 mb-3">
        <div className="flex items-center justify-between gap-2 mb-2">
          <p className="text-sm font-semibold leading-tight">Riepilogo (range)</p>
          <p className="text-xs text-muted-foreground tabular-nums shrink-0">
            {showLoadingSummary ? "…" : `${fmtInt(base.numDays)} gg`}
          </p>
        </div>

        {showLoadingSummary ? (
          <div className="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-8 gap-2">
            <SkeletonTile label="Qty totale" />
            <SkeletonTile label="€ totale" />
            <SkeletonTile label="€/u medio" />
            <SkeletonTile label="Tasso attività" />
            <SkeletonTile label="Trend 30gg" />
            <SkeletonTile label="Trend 7gg" />
            <SkeletonTile label="Min giorno" />
            <SkeletonTile label="Max giorno" />
          </div>
        ) : base.numDays === 0 ? (
          <p className="text-xs text-muted-foreground">Nessun dato nel range selezionato.</p>
        ) : (
          <div className="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-8 gap-2">
            <StatTile label="Qty totale" value={fmtInt(base.totalQty)} sub={`avg ${fmtDec(base.avgQty)} / gg`} />
            <StatTile
              label="€ totale"
              value={`€ ${fmtMoney(base.totalImp)}`}
              sub={`€/gg ${fmtMoney(base.avgImp)} · €/u ${fmtMoney(base.avgPrice)}`}
              emphasis
            />
            <StatTile label="€/u medio" value={`€ ${fmtMoney(base.avgPrice)}`} sub={`(imp/qty)`} />
            <StatTile
              label="Tasso attività"
              value={activityRate == null ? "n/d" : `${fmtDec(activityRate, 0)}%`}
              sub={`attivi ${fmtInt(base.activeDays)} · zero ${fmtInt(base.zeroDays)}`}
            />

            <StatTile
              label="Trend 30gg"
              value={
                extraKpis?.qty30 == null ? "n/d" : `${extraKpis.qty30 >= 0 ? "+" : ""}${fmtDec(extraKpis.qty30, 0)}%`
              }
              sub={extraKpis?.imp30 == null ? "" : `€ ${extraKpis.imp30 >= 0 ? "+" : ""}${fmtDec(extraKpis.imp30, 0)}%`}
            />

            <StatTile
              label="Trend 7gg"
              value={extraKpis?.qty7 == null ? "n/d" : `${extraKpis.qty7 >= 0 ? "+" : ""}${fmtDec(extraKpis.qty7, 0)}%`}
              sub={extraKpis?.imp7 == null ? "" : `€ ${extraKpis.imp7 >= 0 ? "+" : ""}${fmtDec(extraKpis.imp7, 0)}%`}
            />

            <StatTile
              label="Min giorno"
              value={base.minDay ? fmtInt(base.minDay.qty) : "n/d"}
              sub={base.minDay?.date ?? ""}
            />
            <StatTile
              label="Max giorno"
              value={base.maxDay ? fmtInt(base.maxDay.qty) : "n/d"}
              sub={base.maxDay?.date ?? ""}
              emphasis
            />
          </div>
        )}
      </div>

      {/* DETTAGLI (tree lazy) */}
      {openDetails && (
        <div className="border-t pt-3 max-h-80 overflow-y-auto">
          {treeLoading ? (
            <p className="text-sm text-muted-foreground">Caricamento dettagli...</p>
          ) : treeError ? (
            <p className="text-sm text-destructive">{treeError}</p>
          ) : !effectiveTree ? (
            <p className="text-sm text-muted-foreground">Nessun dettaglio disponibile.</p>
          ) : nodes.length === 0 ? (
            <p className="text-sm text-muted-foreground">Nessun dato nel range.</p>
          ) : (
            sortChildren(nodes as SummaryNode[]).map((nd) => (
              <TreeNode
                key={nodeId(nd)}
                node={nd}
                ctx={{}}
                openMap={openMap}
                setOpenMap={setOpenMap}
                onSelect={onSelect}
              />
            ))
          )}
        </div>
      )}
    </Card>
  );
}

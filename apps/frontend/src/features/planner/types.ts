// ─────────────────────────────────────────────────────────────
// Planner Types & Helpers
// ─────────────────────────────────────────────────────────────

export type PlannerMode = "week" | "roll4";

export type PlannerLevel = "fascia" | "categoria" | "famiglia" | "fascia_prezzo";

export type HeatNode = {
  node_id: string;
  parent_id: string | null;
  level: PlannerLevel;
  label: string;
  fascia: string | null;
  categoria: string | null;
  famiglia: string | null;
  fascia_prezzo: string | null;
};

export type HeatCell = {
  node_id: string;
  week_52: number;

  avg_qty: number;
  avg_rev: number;
  share_rev: number;

  sigma_qty: number | null;
  avg_days_active: number | null;
  avg_days_zero: number | null;

  min_qty?: number | null;
  max_qty?: number | null;
  min_rev?: number | null;
  max_rev?: number | null;

  // ✅ Sprint 3
  stock_target?: number | null;
  space_m2?: number | null;

  color_score: number | null; // 0..1
};

// range per tooltip
export type HeatRange = {
  node_id: string;
  week_52: number;
  min_qty: number | null;
  max_qty: number | null;
  min_rev: number | null;
  max_rev: number | null;
};

// ✅ Sprint 3 metriche
export type HeatMetric = "avg_qty" | "avg_rev" | "share_rev" | "stock_target" | "space_m2";

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────

export function buildChildrenIndex(nodes: HeatNode[]): Map<string | null, string[]> {
  const map = new Map<string | null, string[]>();
  for (const node of nodes) {
    const parentId = node.parent_id;
    if (!map.has(parentId)) {
      map.set(parentId, []);
    }
    map.get(parentId)!.push(node.node_id);
  }
  return map;
}

export function buildNodesById(nodes: HeatNode[]): Map<string, HeatNode> {
  const map = new Map<string, HeatNode>();
  for (const node of nodes) {
    map.set(node.node_id, node);
  }
  return map;
}

export function clampWeek52(n: number): number {
  if (!Number.isFinite(n)) return 1;
  const rounded = Math.round(n);
  if (rounded < 1) return 1;
  if (rounded > 52) return 52;
  return rounded;
}

// ✅ NEW: Space Budget + Assortment Calendar
export type SpaceBudgetLevel = "famiglia" | "categoria";

export type SpaceBudgetRow = {
  node_id: string;
  week_52: number;
  space_m2_raw: number;
  space_share: number;
};

export type AssortmentState = "OFF" | "LOW" | "MED" | "HIGH";

export type AssortmentCalendarRow = {
  node_id: string;
  week_52: number;
  state: AssortmentState;
  space_m2_raw: number;
  space_share: number;
  stock_target?: number | null;
};

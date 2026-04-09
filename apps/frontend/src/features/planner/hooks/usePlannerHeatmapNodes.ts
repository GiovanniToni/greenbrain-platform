import { useQuery } from "@tanstack/react-query";
import { apiGet } from "@/lib/apiClient";
import { HeatNode, PlannerMode, buildNodesById, buildChildrenIndex } from "../types";

const IT_COLLATOR = new Intl.Collator("it-IT", { sensitivity: "base" });

type RpcResponse = { nodes: HeatNode[] } | HeatNode[];

function extractNodes(data: RpcResponse | null): HeatNode[] {
  if (!data) return [];
  if (Array.isArray(data)) return data;
  if (typeof data === "object" && Array.isArray((data as any).nodes)) {
    return (data as any).nodes;
  }
  return [];
}

async function fetchNodes(mode: PlannerMode): Promise<HeatNode[]> {
  const resp = await apiGet("/api/v1/planner/heatmap-nodes", { mode });
  return extractNodes(resp?.items ?? []);
}

// ✅ Ordine custom fasce di prezzo
const PRICE_BAND_ORDER: Record<string, number> = {
  "0 - 2,99€": 1,
  "3 - 4,99€": 2,
  "5 - 9,99€": 3,
  "10 - 14,99€": 4,
  "15 - 19,99€": 5,
  "20 - 24,99€": 6,
  "25 - 29,99€": 7,
  "30 - 39,99€": 8,
  "40 - 49,99€": 9,
  "50 - 59,99€": 10,
  "60 - 69,99€": 11,
  "70 - 99,99€": 12,
  "100 - 149,99€": 13,
  "150 - 199,99€": 14,
  "200€ - >": 15,
};

function priceBandRank(label: string): number {
  return PRICE_BAND_ORDER[label] ?? 999; // sconosciuti in fondo
}

export function usePlannerHeatmapNodes(mode: PlannerMode) {
  const query = useQuery<HeatNode[], Error>({
    queryKey: ["planner-heatmap-nodes", mode],
    queryFn: () => fetchNodes(mode),
    staleTime: 10 * 60 * 1000, // 10 minutes
  });

  const nodes = query.data ?? [];
  const nodesById = buildNodesById(nodes);

  // Build children index with sorting:
  // - fascia_prezzo: ordine custom
  // - altri livelli: alfabetico it-IT
  const childrenByParent = buildChildrenIndex(nodes);

  for (const [, childIds] of childrenByParent.entries()) {
    childIds.sort((a, b) => {
      const nodeA = nodesById.get(a);
      const nodeB = nodesById.get(b);

      const labelA = nodeA?.label ?? "";
      const labelB = nodeB?.label ?? "";

      // ✅ se sono fasce di prezzo, usa ranking custom
      if (nodeA?.level === "fascia_prezzo" && nodeB?.level === "fascia_prezzo") {
        const ra = priceBandRank(labelA);
        const rb = priceBandRank(labelB);
        if (ra !== rb) return ra - rb;
        // tie-breaker: alfabetico
        return IT_COLLATOR.compare(labelA, labelB);
      }

      // fallback: alfabetico per tutti gli altri livelli
      return IT_COLLATOR.compare(labelA, labelB);
    });
  }

  // Root nodes are those with parent_id === null
  const rootIds = childrenByParent.get(null) ?? [];

  return {
    nodes,
    nodesById,
    childrenByParent,
    rootIds,
    isLoading: query.isLoading,
    error: query.error,
  };
}

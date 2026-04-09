import { useCallback, useEffect, useRef, useState } from "react";
import { apiPost } from "@/lib/apiClient";
import { HeatRange, PlannerMode } from "../types";

const CHUNK_SIZE = 250;

type RangesByNode = Record<string, Record<number, HeatRange>>;

function chunk<T>(arr: T[], size: number): T[][] {
  const result: T[][] = [];
  for (let i = 0; i < arr.length; i += size) {
    result.push(arr.slice(i, i + size));
  }
  return result;
}

function extractRanges(data: unknown): HeatRange[] {
  if (!data) return [];
  if (Array.isArray(data)) return data as HeatRange[];
  if (typeof data === "object" && Array.isArray((data as any).ranges)) {
    return (data as any).ranges as HeatRange[];
  }
  return [];
}

function rangesRpcName(mode: PlannerMode): string {
  if (mode === "week") return "core_planner__get_heatmap_week_ranges";
  return "core_planner__get_heatmap_roll4_ranges";
}

export function usePlannerHeatmapRanges(mode: PlannerMode, visibleNodeIds: string[]) {
  const [rangesByNode, setRangesByNode] = useState<RangesByNode>({});
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | undefined>(undefined);

  const fetchedRef = useRef<Set<string>>(new Set());
  const modeRef = useRef<PlannerMode>(mode);

  useEffect(() => {
    if (modeRef.current !== mode) {
      modeRef.current = mode;
      fetchedRef.current.clear();
      setRangesByNode({});
      setError(undefined);
    }
  }, [mode]);

  const fetchMissing = useCallback(async () => {
    if (visibleNodeIds.length === 0) return;

    const uniqueIds = Array.from(
      new Set(visibleNodeIds.filter((id) => id && typeof id === "string" && !fetchedRef.current.has(id))),
    );

    if (uniqueIds.length === 0) return;

    setLoading(true);
    setError(undefined);

    for (const id of uniqueIds) fetchedRef.current.add(id);

    try {
      const chunks = chunk(uniqueIds, CHUNK_SIZE);
      const allRanges: HeatRange[] = [];
      const rpcName = rangesRpcName(mode);

      const endpointMap: Record<string, string> = {
        core_planner__get_heatmap_week_ranges: "/api/v1/planner/heatmap-week-ranges",
        core_planner__get_heatmap_roll4_ranges: "/api/v1/planner/heatmap-roll4-ranges",
      };
      const endpoint = endpointMap[rpcName];
      for (const chunkIds of chunks) {
        const resp = await apiPost(endpoint, { node_ids: chunkIds });
        allRanges.push(...extractRanges(resp?.items ?? []));
      }

      setRangesByNode((prev) => {
        const next = { ...prev };
        for (const range of allRanges) {
          if (!range.node_id) continue;
          if (!next[range.node_id]) next[range.node_id] = {};
          next[range.node_id][range.week_52] = range;
        }
        return next;
      });
    } catch (e: any) {
      const msg = e?.message || (typeof e === "string" ? e : "Errore caricamento ranges");
      setError(msg);

      for (const id of uniqueIds) fetchedRef.current.delete(id);
    } finally {
      setLoading(false);
    }
  }, [mode, visibleNodeIds]);

  useEffect(() => {
    fetchMissing();
  }, [fetchMissing]);

  return { rangesByNode, loading, error };
}

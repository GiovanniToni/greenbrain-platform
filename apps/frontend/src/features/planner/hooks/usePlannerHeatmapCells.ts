import { useCallback, useEffect, useRef, useState } from "react";
import { apiPost } from "@/lib/apiClient";
import { HeatCell, PlannerMode } from "../types";

const CHUNK_SIZE = 250;

type CellsByNode = Record<string, Record<number, HeatCell>>;

function chunk<T>(arr: T[], size: number): T[][] {
  const result: T[][] = [];
  for (let i = 0; i < arr.length; i += size) {
    result.push(arr.slice(i, i + size));
  }
  return result;
}

function extractCells(data: unknown): HeatCell[] {
  if (!data) return [];
  if (Array.isArray(data)) return data as HeatCell[];
  if (typeof data === "object" && Array.isArray((data as any).cells)) {
    return (data as any).cells as HeatCell[];
  }
  return [];
}

export function usePlannerHeatmapCells(
  mode: PlannerMode,
  visibleNodeIds: string[]
) {
  const [cellsByNode, setCellsByNode] = useState<CellsByNode>({});
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | undefined>(undefined);

  // Track which node_ids have been fetched for current mode
  const fetchedRef = useRef<Set<string>>(new Set());
  const modeRef = useRef<PlannerMode>(mode);

  // Reset cache when mode changes
  useEffect(() => {
    if (modeRef.current !== mode) {
      modeRef.current = mode;
      fetchedRef.current.clear();
      setCellsByNode({});
      setError(undefined);
    }
  }, [mode]);

  const fetchMissing = useCallback(async () => {
    // Deduplicate and filter falsy/already-fetched
    const uniqueIds = Array.from(
      new Set(
        visibleNodeIds.filter(
          (id) => id && typeof id === "string" && !fetchedRef.current.has(id)
        )
      )
    );

    if (uniqueIds.length === 0) return;

    setLoading(true);
    setError(undefined);

    // Mark as fetched immediately to avoid duplicate requests
    for (const id of uniqueIds) {
      fetchedRef.current.add(id);
    }

    try {
      const chunks = chunk(uniqueIds, CHUNK_SIZE);
      const allCells: HeatCell[] = [];

      for (const chunkIds of chunks) {
        const resp = await apiPost("/api/v1/planner/heatmap-cells", {
          mode,
          node_ids: chunkIds,
        });
        allCells.push(...extractCells(resp?.items ?? []));
      }

      // Merge into cache
      setCellsByNode((prev) => {
        const next = { ...prev };
        for (const cell of allCells) {
          if (!cell.node_id) continue;
          if (!next[cell.node_id]) {
            next[cell.node_id] = {};
          }
          next[cell.node_id][cell.week_52] = cell;
        }
        return next;
      });
    } catch (e: any) {
      const msg =
        e?.message || (typeof e === "string" ? e : "Errore caricamento cells");
      setError(msg);

      // Remove from fetched so retry is possible
      for (const id of uniqueIds) {
        fetchedRef.current.delete(id);
      }
    } finally {
      setLoading(false);
    }
  }, [mode, visibleNodeIds]);

  useEffect(() => {
    fetchMissing();
  }, [fetchMissing]);

  return { cellsByNode, loading, error };
}

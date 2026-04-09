import { useQuery } from "@tanstack/react-query";
import { apiGet } from "@/lib/apiClient";
import { PlannerMode, SpaceBudgetLevel, SpaceBudgetRow } from "../types";

type RpcResponse = { rows: SpaceBudgetRow[] } | SpaceBudgetRow[];

function extractRows(data: unknown): SpaceBudgetRow[] {
  if (!data) return [];
  if (Array.isArray(data)) return data as SpaceBudgetRow[];
  if (typeof data === "object" && Array.isArray((data as any).rows)) {
    return (data as any).rows as SpaceBudgetRow[];
  }
  return [];
}

async function fetchSpaceBudget(mode: PlannerMode, level: SpaceBudgetLevel): Promise<SpaceBudgetRow[]> {
  const resp = await apiGet("/api/v1/planner/space-budget", { mode, level });
  return extractRows(resp?.items ?? []);
}

export function usePlannerSpaceBudget(mode: PlannerMode, level: SpaceBudgetLevel) {
  const query = useQuery<SpaceBudgetRow[], Error>({
    queryKey: ["planner-space-budget", mode, level],
    queryFn: () => fetchSpaceBudget(mode, level),
    staleTime: 10 * 60 * 1000,
  });

  return {
    rows: query.data ?? [],
    loading: query.isLoading,
    error: query.error?.message,
  };
}

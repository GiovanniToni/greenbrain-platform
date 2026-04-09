import { useQuery } from "@tanstack/react-query";
import { apiGet } from "@/lib/apiClient";
import { AssortmentCalendarRow, PlannerMode, SpaceBudgetLevel } from "../types";

type RpcResponse = { rows: AssortmentCalendarRow[] } | AssortmentCalendarRow[];

function extractRows(data: unknown): AssortmentCalendarRow[] {
  if (!data) return [];
  if (Array.isArray(data)) return data as AssortmentCalendarRow[];
  if (typeof data === "object" && Array.isArray((data as any).rows)) {
    return (data as any).rows as AssortmentCalendarRow[];
  }
  return [];
}

async function fetchAssortmentCalendar(mode: PlannerMode, level: SpaceBudgetLevel): Promise<AssortmentCalendarRow[]> {
  const resp = await apiGet("/api/v1/planner/assortment-calendar", { mode, level });
  return extractRows(resp?.items ?? []);
}

export function usePlannerAssortmentCalendar(mode: PlannerMode, level: SpaceBudgetLevel) {
  const query = useQuery<AssortmentCalendarRow[], Error>({
    queryKey: ["planner-assortment-calendar", mode, level],
    queryFn: () => fetchAssortmentCalendar(mode, level),
    staleTime: 10 * 60 * 1000,
  });

  return {
    rows: query.data ?? [],
    loading: query.isLoading,
    error: query.error?.message,
  };
}

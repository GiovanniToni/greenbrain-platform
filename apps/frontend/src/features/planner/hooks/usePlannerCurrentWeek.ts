import { useQuery } from "@tanstack/react-query";
import { apiGet } from "@/lib/apiClient";
import { clampWeek52 } from "../types";

async function fetchCurrentWeek52(): Promise<number> {
  const data = await apiGet("/api/v1/planner/current-week");
  const raw = typeof data === "object" && data !== null ? data.week_52 ?? data : data;
  return clampWeek52(Number(raw));
}

export function usePlannerCurrentWeek() {
  const query = useQuery<number, Error>({
    queryKey: ["planner-current-week52"],
    queryFn: fetchCurrentWeek52,
    staleTime: 60 * 60 * 1000, // 1 hour
  });

  return {
    currentWeek52: query.data ?? 1,
    isLoading: query.isLoading,
    error: query.error,
  };
}

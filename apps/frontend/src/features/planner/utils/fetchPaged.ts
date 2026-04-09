// src/features/planner/utils/fetchPaged.ts
import { apiGet } from "@/lib/apiClient";

// ─── table → backend endpoint map ───────────────────────────────────────────
const TABLE_ENDPOINT: Record<string, string> = {
  t_core_planner__assortment_calendar: "/api/v1/planner/assortment-calendar-export",
};

// Tiny filter interpreter: extracts { eq: [col, val] } pairs from a proxy
function extractEqFilters(filters?: (q: any) => any): Record<string, string> {
  if (!filters) return {};
  const collected: Record<string, string> = {};
  const proxy = new Proxy(
    {},
    {
      get(_t, prop) {
        if (prop === "eq") {
          return (col: string, val: any) => {
            collected[col] = String(val);
            return proxy;
          };
        }
        return () => proxy;
      },
    },
  );
  filters(proxy);
  return collected;
}

export type FetchPagedOptions = {
  table: string;
  select: string;
  pageSize?: number;
  orderBy?: { column: string; ascending?: boolean };
  orderBy2?: { column: string; ascending?: boolean };
  filters?: (q: any) => any;
  onProgress?: (info: { fetched: number; page: number }) => void;
};

export async function fetchAllPaged<T = any>({
  table,
  pageSize = 5000,
  filters,
  onProgress,
}: FetchPagedOptions): Promise<T[]> {
  const endpoint = TABLE_ENDPOINT[table];
  if (!endpoint) throw new Error(`fetchAllPaged: no backend endpoint mapped for table '${table}'`);

  const eqFilters = extractEqFilters(filters);

  const out: T[] = [];
  let page = 0;

  while (true) {
    const resp = await apiGet(endpoint, { ...eqFilters, page, page_size: pageSize });
    const rows = ((resp?.items) ?? []) as T[];
    out.push(...rows);
    onProgress?.({ fetched: out.length, page: page + 1 });
    if (rows.length < pageSize) break;
    page += 1;
  }

  return out;
}

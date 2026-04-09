import { useCallback, useRef, useState } from "react";
import { apiGet } from "@/lib/apiClient";

export type CatalogNodeType = "fascia" | "categoria" | "famiglia" | "fascia_prezzo" | "articolo";

export type CatalogTreeNode = {
  node_type: CatalogNodeType;
  node_key: string;
  label: string;
  extra?: any;
};

export function useCatalogTree() {
  const [loadingKey, setLoadingKey] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  // cache in-memory: key -> children[]
  const cacheRef = useRef<Record<string, CatalogTreeNode[]>>({});

  const fetchChildren = useCallback(
    async (args: {
      level: CatalogNodeType;
      fascia?: string | null;
      categoria?: string | null;
      famiglia?: string | null;
      fascia_prezzo?: string | null;
      limit?: number;
    }) => {
      const { level, fascia, categoria, famiglia, fascia_prezzo, limit } = args;

      const cacheKey = JSON.stringify({ level, fascia, categoria, famiglia, fascia_prezzo, limit: limit ?? 500 });
      if (cacheRef.current[cacheKey]) return cacheRef.current[cacheKey];

      setLoadingKey(cacheKey);
      setError(null);

      try {
        const resp = await apiGet("/api/v1/catalog/children", {
          level,
          ...(fascia != null && { fascia }),
          ...(categoria != null && { categoria }),
          ...(famiglia != null && { famiglia }),
          ...(fascia_prezzo != null && { fascia_prezzo }),
          limit: limit ?? 500,
        });

        const out = ((resp?.items || []) as any[]).map((r) => ({
          node_type: r.node_type as CatalogNodeType,
          node_key: String(r.node_key),
          label: String(r.label),
          extra: r.extra ?? null,
        })) as CatalogTreeNode[];

        cacheRef.current[cacheKey] = out;
        return out;
      } catch (e: any) {
        setError(e?.message ?? "Errore caricamento catalogo");
        return [];
      } finally {
        setLoadingKey(null);
      }
    },
    [],
  );

  const clearCache = useCallback(() => {
    cacheRef.current = {};
    setError(null);
    setLoadingKey(null);
  }, []);

  return { fetchChildren, loadingKey, error, clearCache };
}

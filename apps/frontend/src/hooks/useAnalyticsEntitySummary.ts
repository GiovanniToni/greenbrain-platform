import { useCallback, useRef, useState } from "react";
import { apiGet } from "@/lib/apiClient";

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
  date_from: string; // ISO
  date_to: string; // ISO
  totals: SummaryTotals;
  tree: SummaryNode[] | SummaryNode;
};

type RefetchParams = {
  p_entity_type: string;
  p_entity_key: string;
  p_date_from: string;
  p_date_to: string;
  p_top_n?: number;

  // contesto opzionale
  p_fascia?: string | null;
  p_categoria?: string | null;
  p_famiglia?: string | null;
  p_fascia_prezzo?: string | null;
};

function norm(v: any) {
  return String(v ?? "")
    .trim()
    .toLowerCase();
}

function makeCacheKey(p: RefetchParams) {
  return [
    norm(p.p_entity_type),
    norm(p.p_entity_key),
    norm(p.p_date_from),
    norm(p.p_date_to),
    String(p.p_top_n ?? 10),
    norm(p.p_fascia ?? ""),
    norm(p.p_categoria ?? ""),
    norm(p.p_famiglia ?? ""),
    norm(p.p_fascia_prezzo ?? ""),
  ].join("|");
}

export function useAnalyticsEntitySummary() {
  const [data, setData] = useState<EntitySummaryTree | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // ✅ CACHE in-memory (per evitare refetch quando apri/chiudi o cambi selection nel dettaglio)
  const cacheRef = useRef<Map<string, EntitySummaryTree | null>>(new Map());

  const refetch = useCallback(async (params: RefetchParams) => {
    const { p_entity_type, p_entity_key, p_date_from, p_date_to } = params;

    if (!p_entity_type || !p_entity_key || !p_date_from || !p_date_to) {
      setData(null);
      return;
    }

    const key = makeCacheKey(params);

    // ✅ HIT cache -> risposta immediata
    if (cacheRef.current.has(key)) {
      setData(cacheRef.current.get(key) ?? null);
      setError(null);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const { p_top_n = 10, p_fascia = null, p_categoria = null, p_famiglia = null, p_fascia_prezzo = null } = params;

      const rpcData = await apiGet("/api/v1/analytics/entity-summary", {
        p_entity_type,
        p_entity_key,
        p_date_from,
        p_date_to,
        p_top_n,
        ...(p_fascia != null && { p_fascia }),
        ...(p_categoria != null && { p_categoria }),
        ...(p_famiglia != null && { p_famiglia }),
        ...(p_fascia_prezzo != null && { p_fascia_prezzo }),
      });

      const out = (rpcData ?? null) as EntitySummaryTree | null;

      // ✅ salva in cache
      cacheRef.current.set(key, out);

      setData(out);
    } catch (e: any) {
      setError(e?.message ?? "Errore caricamento summary");
      setData(null);
    } finally {
      setLoading(false);
    }
  }, []);

  return { data, loading, error, refetch };
}

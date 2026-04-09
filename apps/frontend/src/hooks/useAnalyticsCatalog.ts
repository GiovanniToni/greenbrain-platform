import { useState, useCallback, useRef } from "react";
import { apiGet } from "@/lib/apiClient";

export interface CatalogItem {
  entity_type: string;
  entity_key: string;
  label: string;
  score?: number;

  // gerarchia (serve per aprire l’albero)
  fascia?: string | null;
  categoria?: string | null;
  famiglia?: string | null;
  fascia_prezzo?: string | null;

  // se entity_type = "articolo"
  codart?: string | null;
  articolo_nome?: string | null;
  pot_size?: string | null;
  prezzo_iva_inclusa?: number | null;
}

export function useAnalyticsCatalog() {
  const [items, setItems] = useState<CatalogItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // serve per ignorare risposte vecchie (evita "race conditions")
  const reqIdRef = useRef(0);

  const search = useCallback(async (term: string) => {
    const t = (term ?? "").trim();

    if (t.length < 2) {
      setItems([]);
      setError(null);
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);
    const myReqId = ++reqIdRef.current;

    try {
      const resp = await apiGet("/api/v1/catalog/search", { term: t, limit: 50 });

      if (myReqId !== reqIdRef.current) return;

      setItems((resp?.items ?? []) as CatalogItem[]);
    } catch (err) {
      if (myReqId !== reqIdRef.current) return;
      console.error("Catalog error:", err);
      setError("Errore nel caricamento del catalogo");
      setItems([]);
    } finally {
      if (myReqId !== reqIdRef.current) return;
      setLoading(false);
    }
  }, []);

  const list = useCallback(async (entityType: string, limit = 500) => {
    const et = (entityType ?? "").trim();
    if (!et) {
      setItems([]);
      setError(null);
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);
    const myReqId = ++reqIdRef.current;

    try {
      const resp = await apiGet("/api/v1/catalog/list", { entity_type: et, limit });

      if (myReqId !== reqIdRef.current) return;

      setItems((resp?.items ?? []) as CatalogItem[]);
    } catch (err) {
      if (myReqId !== reqIdRef.current) return;
      console.error("Catalog list error:", err);
      setError("Errore nel caricamento del catalogo");
      setItems([]);
    } finally {
      if (myReqId !== reqIdRef.current) return;
      setLoading(false);
    }
  }, []);

  const clear = useCallback(() => {
    reqIdRef.current++;
    setItems([]);
    setError(null);
    setLoading(false);
  }, []);

  return { items, loading, error, search, list, clear };
}

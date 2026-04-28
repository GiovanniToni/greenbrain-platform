import { useState, useCallback } from "react";
import { apiGet } from "@/lib/apiClient";

export interface ComponentArticle {
  codart: string;
  articolo_nome: string;
  pot_size: string | null;
  fascia_prezzo_iva_inc: string | null;
  prezzo_iva_inclusa: number | null;
}

interface ComponentsParams {
  entityType: string;
  entityKey: string;
}

export function useAnalyticsComponents() {
  const [rows, setRows] = useState<ComponentArticle[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(async (params: ComponentsParams) => {
    const { entityType, entityKey } = params;

    if (!entityType || !entityKey || entityType === "articolo") {
      setRows([]);
      setError(null);
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const resp = await apiGet("/api/v1/analytics/components", {
        entity_type: entityType,
        entity_key: entityKey,
      });

      setRows(
        ((resp?.items || []) as any[]).map((row) => ({
          codart: row.codart,
          articolo_nome: row.articolo_nome,
          pot_size: row.pot_size,
          fascia_prezzo_iva_inc: row.fascia_prezzo_iva_inc,
          prezzo_iva_inclusa: row.prezzo_iva_inclusa != null ? parseFloat(row.prezzo_iva_inclusa) : null,
        })),
      );
    } catch (err) {
      console.error("Components error:", err);
      setError("Errore nel caricamento dei componenti");
      setRows([]);
    } finally {
      setLoading(false);
    }
  }, []);

  return { rows, loading, error, refetch };
}

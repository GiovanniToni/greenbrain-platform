import { useEffect, useState } from "react";
import { apiGet } from "@/lib/apiClient";

export type ReorderSuggestionRow = {
  famiglia: string;
  fascia_prezzo_iva_inc: string;
  categoria_corretta: string | null;
  fascia_corretta: string | null;
  pot_sizes_text: string | null;
  qty_giacenza: number;
  qty_da_ordinare: number;
  rischio_stockout_prima_di_arrivo: boolean;

  // extra (se li vuoi usare ora o dopo)
  demand_lead?: number;
  demand_cycle?: number;
  in_assortimento?: boolean;
};

function n(v: any) {
  const x = Number(v);
  return Number.isFinite(x) ? x : 0;
}

export function useDashboardReorderSuggestions(limit = 12) {
  const [rows, setRows] = useState<ReorderSuggestionRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;

    (async () => {
      setLoading(true);
      setError(null);

      let resp: any;
      try {
        resp = await apiGet("/api/v1/dashboard/reorder-suggestions", { limit });
      } catch (error: any) {
        if (!alive) return;
        console.error("reorder suggestions error:", error);
        setRows([]);
        setError(error.message ?? "Errore caricamento suggerimenti riordino");
        setLoading(false);
        return;
      }

      if (!alive) return;

      setRows(
        ((resp?.items) ?? []).map((r: any) => ({
          famiglia: String(r.famiglia ?? ""),
          fascia_prezzo_iva_inc: String(r.fascia_prezzo_iva_inc ?? ""),
          categoria_corretta: r.categoria_corretta ?? null,
          fascia_corretta: r.fascia_corretta ?? null,
          pot_sizes_text: r.pot_sizes_text ?? null,
          qty_giacenza: n(r.qty_giacenza),
          qty_da_ordinare: n(r.qty_da_ordinare),
          rischio_stockout_prima_di_arrivo: !!r.rischio_stockout_prima_di_arrivo,
          demand_lead: r.demand_lead == null ? undefined : n(r.demand_lead),
          demand_cycle: r.demand_cycle == null ? undefined : n(r.demand_cycle),
          in_assortimento: r.in_assortimento == null ? undefined : !!r.in_assortimento,
        })),
      );

      setLoading(false);
    })();

    return () => {
      alive = false;
    };
  }, [limit]);

  return { rows, loading, error };
}

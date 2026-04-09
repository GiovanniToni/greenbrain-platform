import { useState, useEffect } from "react";
import { apiGet } from "@/lib/apiClient";

export interface OrderSuggestion {
  famiglia: string | null;
  fascia_prezzo_iva_inc: string | null;
  categoria_corretta: string | null;
  fascia_corretta: string | null;
  pot_sizes_text: string | null;
  in_assortimento: boolean | null;
  qty_giacenza: number | null;
  demand_lead: number | null;
  demand_cycle: number | null;
  stock_after_lead: number | null;
  required_on_arrival: number | null;
  qty_da_ordinare: number | null;
  rischio_stockout_prima_di_arrivo: boolean | null;
}

export function useOrderSuggestions() {
  const [data, setData] = useState<OrderSuggestion[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;

    async function fetchData() {
      setLoading(true);
      setError(null);

      let resp: any;
      try {
        resp = await apiGet("/api/v1/planner/order-suggestions");
      } catch (err: any) {
        if (!alive) return;
        console.error("Order suggestions fetch error:", err);
        setError(err.message ?? "Errore caricamento suggerimenti ordine");
        setData([]);
        setLoading(false);
        return;
      }

      if (!alive) return;

      setData(((resp?.items) as OrderSuggestion[]) || []);

      setLoading(false);
    }

    fetchData();

    return () => {
      alive = false;
    };
  }, []);

  return { data, loading, error };
}

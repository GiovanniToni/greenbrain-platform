import { useCallback, useState } from "react";
import { apiGet } from "@/lib/apiClient";

export type RollingTotals = {
  d7: { qty: number; imp: number };
  d10: { qty: number; imp: number };
  d30: { qty: number; imp: number };
  d60: { qty: number; imp: number }; // ✅ NEW
  d90: { qty: number; imp: number };
};

function isoDay(v: any): string {
  return String(v ?? "").slice(0, 10);
}

function parseISODate(iso: string) {
  return new Date(`${isoDay(iso)}T00:00:00`);
}

function formatDateISO(d: Date) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function addDaysISO(iso: string, days: number) {
  const d = parseISODate(iso);
  d.setDate(d.getDate() + days);
  return formatDateISO(d);
}

function n(v: any): number {
  const x = Number(v);
  return Number.isFinite(x) ? x : 0;
}

// ✅ manca nel file: normalizza chiave come nelle viste *_lc
function normKey(v: any): string {
  return String(v ?? "")
    .trim()
    .toLowerCase();
}

function pickTotalSourceLC(entityType: string) {
  if (entityType === "famiglia") return "core_analytics__series_daily_famiglia_lc";
  if (entityType === "categoria") return "core_analytics__series_daily_categoria_lc";
  if (entityType === "fascia") return "core_analytics__series_daily_fascia_lc";
  if (entityType === "fascia_prezzo") return "core_analytics__series_daily_fascia_prezzo_lc";
  return null;
}

export function useAnalyticsRollingTotals() {
  const [data, setData] = useState<RollingTotals | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(async (params: { entityType: string; entityKey: string; anchorTo: string; fasciaPrezzo?: string | null }) => {
    const { entityType, entityKey, anchorTo, fasciaPrezzo } = params;

    if (!entityType || !entityKey || !anchorTo) {
      setData(null);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const to = isoDay(anchorTo);
      const from = addDaysISO(to, -89); // ✅ 90 giorni inclusivi -> coperta anche finestra 60gg

      // ✅ articolo: view dedicata
      if (entityType === "articolo") {
        const resp = await apiGet("/api/v1/analytics/series", {
          entity_type: "articolo",
          granularity: "day",
          entity_key: entityKey,
          date_from: from,
          date_to: to,
        });

        const r = ((resp?.items) || []) as any[];
        const dayMap = new Map<string, { qty: number; imp: number }>();

        for (const x of r) {
          dayMap.set(isoDay(x.data), { qty: n(x.qty_venduta), imp: n(x.imponibile_netto) });
        }

        const sumLastN = (days: number) => {
          let qty = 0;
          let imp = 0;
          for (let i = days - 1; i >= 0; i--) {
            const d = addDaysISO(to, -i);
            const v = dayMap.get(d);
            if (v) {
              qty += v.qty;
              imp += v.imp;
            }
          }
          return { qty, imp };
        };

        setData({
          d7: sumLastN(7),
          d10: sumLastN(10),
          d30: sumLastN(30),
          d60: sumLastN(60),
          d90: sumLastN(90),
        });
        return;
      }

      // ✅ altri entityType: viste LC
      if (!pickTotalSourceLC(entityType)) throw new Error(`EntityType non supportato: ${entityType}`);

      const resp = await apiGet("/api/v1/analytics/series", {
        entity_type: entityType,
        granularity: "day",
        entity_key: normKey(entityKey),
        date_from: from,
        date_to: to,
        ...(fasciaPrezzo ? { fascia_prezzo: fasciaPrezzo } : {}),
      });

      const r = ((resp?.items) || []) as any[];
      const dayMap = new Map<string, { qty: number; imp: number }>();

      for (const x of r) {
        const qty = fasciaPrezzo ? n(x.qty_venduta ?? x.qty_venduta_tot) : n(x.qty_venduta_tot ?? x.qty_venduta);
        const imp = n(x.imponibile_netto_tot ?? x.imponibile_netto);
        dayMap.set(isoDay(x.data), { qty, imp });
      }

      const sumLastN = (days: number) => {
        let qty = 0;
        let imp = 0;
        for (let i = days - 1; i >= 0; i--) {
          const d = addDaysISO(to, -i);
          const v = dayMap.get(d);
          if (v) {
            qty += v.qty;
            imp += v.imp;
          }
        }
        return { qty, imp };
      };

      setData({
        d7: sumLastN(7),
        d10: sumLastN(10),
        d30: sumLastN(30),
        d60: sumLastN(60),
        d90: sumLastN(90),
      });
    } catch (e: any) {
      setError(e?.message ?? "Errore rolling totals");
      setData(null);
    } finally {
      setLoading(false);
    }
  }, []);

  return { data, loading, error, refetch };
}

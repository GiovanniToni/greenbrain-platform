import { useMemo, useState } from "react";
import { AlertTriangle, ShoppingCart, ChevronDown, ChevronUp } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { useDashboardReorderSuggestions } from "@/hooks/useDashboardReorderSuggestions";

function fmtInt(n: number) {
  return Number(n ?? 0).toLocaleString("it-IT", { maximumFractionDigits: 0 });
}

type Props = {
  kpis: {
    reordersWeek: number;
    reorderRiskLines: number;
    reorderQtyTot: number;
  };
  kpiLoading?: boolean;

  // ✅ nuove props
  defaultHeightClass?: string;
  expandedHeightClass?: string;
};

export function ReorderSuggestionsCard({
  kpis,
  kpiLoading = false,
  defaultHeightClass = "h-[420px]",
  expandedHeightClass = "h-[640px]",
}: Props) {
  const [expanded, setExpanded] = useState(false);
  const { rows, loading } = useDashboardReorderSuggestions(12);

  const heightClass = expanded ? expandedHeightClass : defaultHeightClass;

  // lista: usa il resto dell’altezza disponibile
  const listHeightClass = expanded ? "max-h-[520px]" : "max-h-[280px]";

  const showMismatch = !loading && !kpiLoading && (kpis.reordersWeek ?? 0) > 0 && rows.length === 0;

  const headerTitle = useMemo(() => {
    if (loading) return "Caricamento...";
    return "Riordini";
  }, [loading]);

  return (
    <Card className={cn("p-4 flex flex-col", heightClass)}>
      {/* Header */}
      <div className="flex items-center justify-between mb-3">
        <div>
          <h3 className="font-semibold text-lg">{headerTitle}</h3>
          <p className="text-xs text-muted-foreground">KPI + Top suggerimenti</p>
        </div>

        <div className="flex items-center gap-2">
          <Button type="button" variant="ghost" size="sm" className="h-8 px-2" onClick={() => setExpanded((v) => !v)}>
            {expanded ? (
              <span className="flex items-center gap-1 text-xs">
                Comprimi <ChevronUp className="h-4 w-4" />
              </span>
            ) : (
              <span className="flex items-center gap-1 text-xs">
                Espandi <ChevronDown className="h-4 w-4" />
              </span>
            )}
          </Button>

          <div className="p-2 rounded-lg bg-primary/10">
            <ShoppingCart className="h-5 w-5 text-primary" />
          </div>
        </div>
      </div>

      {/* KPI mini */}
      <div className="grid grid-cols-3 gap-2 mb-3">
        <div className="rounded-lg bg-muted/40 p-2">
          <div className="text-[11px] text-muted-foreground">Righe</div>
          <div className="text-sm font-semibold tabular-nums">{kpiLoading ? "…" : fmtInt(kpis.reordersWeek)}</div>
        </div>
        <div className="rounded-lg bg-muted/40 p-2">
          <div className="text-[11px] text-muted-foreground">A rischio</div>
          <div
            className={cn(
              "text-sm font-semibold tabular-nums",
              (kpis.reorderRiskLines ?? 0) > 0 ? "text-destructive" : "",
            )}
          >
            {kpiLoading ? "…" : fmtInt(kpis.reorderRiskLines)}
          </div>
        </div>
        <div className="rounded-lg bg-muted/40 p-2">
          <div className="text-[11px] text-muted-foreground">Qty tot</div>
          <div className="text-sm font-semibold tabular-nums">{kpiLoading ? "…" : fmtInt(kpis.reorderQtyTot)}</div>
        </div>
      </div>

      {showMismatch ? (
        <div className="mb-3 rounded-md border border-destructive/30 bg-destructive/5 px-3 py-2 text-xs text-destructive">
          KPI riordini &gt; 0 ma la lista è vuota. Probabile view/permessi su{" "}
          <code>dashboard__reorder_suggestions_top</code>.
        </div>
      ) : null}

      {/* Lista scrollabile */}
      <div className={cn("space-y-2 overflow-y-auto pr-1", listHeightClass)}>
        {!loading && rows.length === 0 ? (
          <p className="text-muted-foreground text-center py-8">Nessun riordino suggerito 🎉</p>
        ) : (
          (loading ? Array.from({ length: 6 }) : rows).map((r: any, idx: number) => {
            if (loading) return <div key={idx} className="h-14 rounded-md bg-muted animate-pulse" />;

            const risk = !!r.rischio_stockout_prima_di_arrivo;

            return (
              <div
                key={idx}
                className="flex items-center justify-between p-3 rounded-lg bg-muted/50 hover:bg-muted transition-colors"
              >
                <div className="flex-1 min-w-0">
                  <p className="font-medium text-sm truncate">
                    {r.famiglia} · {r.fascia_prezzo_iva_inc}
                  </p>
                  <p className="text-xs text-muted-foreground truncate">
                    giacenza {fmtInt(r.qty_giacenza)} · vasi {r.pot_sizes_text ?? "n/d"}
                  </p>
                </div>

                <div className="flex flex-col items-end ml-3">
                  <span className="font-semibold text-sm tabular-nums">{fmtInt(r.qty_da_ordinare)}</span>
                  <span
                    className={cn(
                      "text-xs flex items-center gap-1",
                      risk ? "text-destructive" : "text-muted-foreground",
                    )}
                  >
                    {risk ? <AlertTriangle className="h-3 w-3" /> : null}
                    {risk ? "rischio" : "ok"}
                  </span>
                </div>
              </div>
            );
          })
        )}
      </div>

      <div className="mt-auto pt-2 text-[11px] text-muted-foreground">
        Mostrati: {loading ? "…" : rows.length} · puoi scorrere o espandere
      </div>
    </Card>
  );
}

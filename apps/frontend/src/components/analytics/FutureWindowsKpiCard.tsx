import { Card } from "@/components/ui/card";
import { FutureWindowRow } from "@/hooks/useAnalyticsFutureWindowsKpi";

export function FutureWindowsKpiCard({
  rows,
  loading,
  error,
}: {
  rows: FutureWindowRow[];
  loading: boolean;
  error: string | null;
}) {
  return (
    <Card className="p-4">
      <div className="mb-3">
        <h3 className="font-semibold text-sm">Prossimi giorni (anni passati)</h3>
        <p className="text-xs text-muted-foreground">totale qty nei giorni successivi</p>
      </div>

      {loading ? (
        <p className="text-sm text-muted-foreground">Caricamento…</p>
      ) : error ? (
        <p className="text-sm text-destructive">{error}</p>
      ) : rows.length === 0 ? (
        <p className="text-sm text-muted-foreground">Seleziona un'entità per vedere la statistica.</p>
      ) : (
        <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-5 gap-4">
          {rows.map((r) => (
            <div key={r.window_days} className="rounded-lg border p-3 text-center">
              <p className="text-lg font-bold">{r.window_days} giorni</p>
              <p className="text-xs text-muted-foreground">Min: {r.min_qty.toLocaleString("it-IT", { maximumFractionDigits: 0 })}</p>
              <p className="text-xs text-muted-foreground">Max: {r.max_qty.toLocaleString("it-IT", { maximumFractionDigits: 0 })}</p>
              <p className="text-xs text-muted-foreground">Media: {r.avg_qty.toLocaleString("it-IT", { maximumFractionDigits: 0 })}</p>
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}

// src/components/analytics/SeasonalityChart.tsx
import { Card } from "@/components/ui/card";
import { AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer } from "recharts";
import { SeasonalityDataPoint } from "@/hooks/useAnalyticsSeasonality";

interface SeasonalityChartProps {
  data: SeasonalityDataPoint[];
}

function n(v: any): number {
  const x = Number(v);
  return Number.isFinite(x) ? x : 0;
}

export function SeasonalityChart({ data }: SeasonalityChartProps) {
  const CustomTooltip = ({ active, payload }: any) => {
    if (!active || !payload?.length) return null;

    const point = payload[0]?.payload as SeasonalityDataPoint | undefined;
    if (!point) return null;

    const avgQty = n(point.avg_qty_per_day);
    const sumQty = n(point.sum_qty);
    const avgRev = n(point.avg_rev_per_day ?? 0);
    const sumRev = n(point.sum_rev ?? 0);

    return (
      <div className="bg-card border border-border rounded-lg p-3 shadow-lg">
        <p className="font-medium text-sm">{point.month_name}</p>

        <p className="text-xs text-muted-foreground">
          Media/giorno: {avgQty.toLocaleString("it-IT", { maximumFractionDigits: 1 })}
        </p>
        <p className="text-xs text-muted-foreground">
          Totale: {sumQty.toLocaleString("it-IT", { maximumFractionDigits: 0 })}
        </p>

        <div className="mt-2 pt-2 border-t border-border">
          <p className="text-xs text-muted-foreground">
            Ricavo medio/giorno: {avgRev.toLocaleString("it-IT", { maximumFractionDigits: 0 })} €
          </p>
          <p className="text-xs text-muted-foreground">
            Ricavo totale: {sumRev.toLocaleString("it-IT", { maximumFractionDigits: 0 })} €
          </p>
        </div>
      </div>
    );
  };

  if (!data || data.length === 0) {
    return (
      <Card className="p-6">
        <h3 className="text-sm font-medium text-muted-foreground mb-4">Stagionalità Annua</h3>
        <div className="h-48 flex items-center justify-center text-muted-foreground">
          Seleziona un&apos;entità per visualizzare i dati
        </div>
      </Card>
    );
  }

  // piccola safety: ordina per month_num (nel caso arrivi non ordinato)
  const sorted = [...data].sort((a, b) => n(a.month_num) - n(b.month_num));

  return (
    <Card className="p-6">
      <h3 className="text-sm font-medium text-muted-foreground mb-4">Stagionalità Annua</h3>

      <div className="h-48">
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart data={sorted} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
            <XAxis dataKey="month_name" tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
            <YAxis tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
            <Tooltip content={<CustomTooltip />} />
            <Area
              type="monotone"
              dataKey="avg_qty_per_day"
              name="Media/giorno"
              stroke="hsl(var(--accent))"
              fill="hsl(var(--accent) / 0.2)"
              strokeWidth={2}
              isAnimationActive={false}
            />
          </AreaChart>
        </ResponsiveContainer>
      </div>
    </Card>
  );
}

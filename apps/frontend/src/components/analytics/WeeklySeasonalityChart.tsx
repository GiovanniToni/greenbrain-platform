import { Card } from "@/components/ui/card";
import {
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

interface WeeklySeasonalityChartProps {
  data: Array<{
    dow: number;
    day_name: string;
    avg_qty_per_day: number;
    sum_qty?: number;
    avg_rev_per_day?: number;
    sum_rev?: number;
    n_days?: number;
  }>;
}

function n(v: any) {
  const x = Number(v);
  return Number.isFinite(x) ? x : 0;
}

export function WeeklySeasonalityChart({ data }: WeeklySeasonalityChartProps) {
  const rows = [...(data || [])].sort((a, b) => n(a.dow) - n(b.dow));

  const CustomTooltip = ({ active, payload }: any) => {
    if (!active || !payload?.length) return null;
    const p = payload[0]?.payload;
    if (!p) return null;

    return (
      <div className="bg-card border border-border rounded-lg p-3 shadow-lg">
        <p className="font-medium text-sm">{p.day_name}</p>
        <p className="text-xs text-muted-foreground">
          Media/giorno: {n(p.avg_qty_per_day).toLocaleString("it-IT", { maximumFractionDigits: 2 })}
        </p>
        <p className="text-xs text-muted-foreground">
          Totale: {n(p.sum_qty).toLocaleString("it-IT", { maximumFractionDigits: 0 })}
        </p>
        <div className="mt-2 pt-2 border-t border-border">
          <p className="text-xs text-muted-foreground">
            Ricavo medio/giorno: {n(p.avg_rev_per_day).toLocaleString("it-IT", { maximumFractionDigits: 0 })} €
          </p>
          <p className="text-xs text-muted-foreground">
            Giorni osservati: {n(p.n_days).toLocaleString("it-IT", { maximumFractionDigits: 0 })}
          </p>
        </div>
      </div>
    );
  };

  if (!rows || rows.length === 0) {
    return (
      <Card className="p-6">
        <h3 className="text-sm font-medium text-muted-foreground mb-4">Stagionalità Settimanale</h3>
        <div className="h-48 flex items-center justify-center text-muted-foreground">
          Seleziona un'entità per visualizzare i dati
        </div>
      </Card>
    );
  }

  return (
    <Card className="p-6">
      <h3 className="text-sm font-medium text-muted-foreground mb-4">Stagionalità Settimanale</h3>
      <div className="h-48">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={rows} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
            <CartesianGrid strokeDasharray="3 3" className="stroke-muted" />
            <XAxis dataKey="day_name" tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
            <YAxis tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
            <Tooltip content={<CustomTooltip />} />
            <Bar
              dataKey="avg_qty_per_day"
              name="Media qty/giorno"
              fill="hsl(var(--primary) / 0.8)"
              radius={[6, 6, 0, 0]}
              isAnimationActive={false}
            />
          </BarChart>
        </ResponsiveContainer>
      </div>
    </Card>
  );
}

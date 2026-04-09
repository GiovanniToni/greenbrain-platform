import { useMemo } from "react";
import { Card } from "@/components/ui/card";
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer } from "recharts";
import { SeriesDataPoint } from "@/hooks/useAnalyticsSeries";

interface WeeklySeasonalityChartProps {
  data: SeriesDataPoint[];
}

const DOW_SHORT = ["Dom", "Lun", "Mar", "Mer", "Gio", "Ven", "Sab"];

export function WeeklySeasonalityChart({ data }: WeeklySeasonalityChartProps) {
  const weekly = useMemo(() => {
    // avg qty per giorno della settimana sul dataset corrente (già filtrato + brush)
    const sums = new Array(7).fill(0);
    const counts = new Array(7).fill(0);

    for (const r of data) {
      const d = r.dow;
      if (d == null) continue;
      sums[d] += r.qty_venduta_tot || 0;
      counts[d] += 1;
    }

    return DOW_SHORT.map((name, dow) => ({
      dow,
      name,
      avg_qty: counts[dow] > 0 ? sums[dow] / counts[dow] : 0,
      days: counts[dow],
    }));
  }, [data]);

  const CustomTooltip = ({ active, payload }: any) => {
    if (!active || !payload?.length) return null;
    const p = payload[0]?.payload;
    return (
      <div className="bg-card border border-border rounded-lg p-3 shadow-lg">
        <p className="font-medium text-sm">{p?.name}</p>
        <p className="text-xs text-muted-foreground">
          Media: {p?.avg_qty?.toLocaleString("it-IT", { maximumFractionDigits: 2 })}
        </p>
        <p className="text-xs text-muted-foreground">Giorni osservati: {p?.days}</p>
      </div>
    );
  };

  if (!data || data.length === 0) {
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
          <BarChart data={weekly} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
            <XAxis dataKey="name" tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
            <YAxis tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
            <Tooltip content={<CustomTooltip />} />
            <Bar dataKey="avg_qty" name="Media qty" fill="hsl(var(--primary) / 0.8)" radius={[6, 6, 0, 0]} />
          </BarChart>
        </ResponsiveContainer>
      </div>
    </Card>
  );
}

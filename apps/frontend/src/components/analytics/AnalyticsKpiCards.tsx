import { Card } from "@/components/ui/card";
import { TrendingUp, Calendar, Percent, Target, Activity } from "lucide-react";
import { SeriesDataPoint } from "@/hooks/useAnalyticsSeries";

interface AnalyticsKpiCardsProps {
  data: SeriesDataPoint[];
  dateFrom: string;
  dateTo: string;
}

function safePct(n: number) {
  if (!isFinite(n)) return 0;
  return n;
}

export function AnalyticsKpiCards({ data }: AnalyticsKpiCardsProps) {
  const totalQty = data.reduce((sum, d) => sum + (d.qty_venduta_tot ?? d.qty_venduta ?? 0), 0);
  const numDays = data.length;
  const avgQtyPerDay = numDays > 0 ? totalQty / numDays : 0;

  // Weekend
  const weekendData = data.filter((d) => d.dow === 0 || d.dow === 6);
  const weekendQty = weekendData.reduce((sum, d) => sum + (d.qty_venduta_tot ?? d.qty_venduta ?? 0), 0);
  const weekendPct = totalQty > 0 ? (weekendQty / totalQty) * 100 : 0;

  // Forecast coverage + error metrics
  const withFc = data.filter((d) => d.qty_forecast_tot != null);
  const forecastCoverage = numDays > 0 ? (withFc.length / numDays) * 100 : 0;

  // consideriamo solo giorni con vendite > 0 e forecast presente
  const validErr = data.filter((d) => (d.qty_venduta_tot ?? d.qty_venduta ?? 0) > 0 && d.qty_forecast_tot != null);

  const mape =
    validErr.length > 0
      ? validErr.reduce((acc, d) => {
          const actual = d.qty_venduta_tot ?? d.qty_venduta;
          const fc = d.qty_forecast_tot as number;
          return acc + Math.abs(fc - actual) / actual;
        }, 0) / validErr.length
      : 0;

  const bias =
    validErr.length > 0
      ? validErr.reduce((acc, d) => {
          const actual = d.qty_venduta_tot ?? d.qty_venduta;
          const fc = d.qty_forecast_tot as number;
          return acc + (fc - actual) / actual;
        }, 0) / validErr.length
      : 0;

  const kpis = [
    {
      label: "Qty Totale",
      value: totalQty.toLocaleString("it-IT", { maximumFractionDigits: 0 }),
      icon: TrendingUp,
      color: "text-primary",
    },
    {
      label: "Media/Giorno",
      value: avgQtyPerDay.toLocaleString("it-IT", { maximumFractionDigits: 2 }),
      icon: Calendar,
      color: "text-accent",
    },
    {
      label: "% Weekend",
      value: safePct(weekendPct).toLocaleString("it-IT", { maximumFractionDigits: 1 }) + "%",
      icon: Percent,
      color: "text-amber-600",
    },
    {
      label: "Forecast coverage",
      value: safePct(forecastCoverage).toLocaleString("it-IT", { maximumFractionDigits: 0 }) + "%",
      icon: Target,
      color: "text-muted-foreground",
    },
    {
      label: "MAPE (errore %)",
      value: safePct(mape * 100).toLocaleString("it-IT", { maximumFractionDigits: 1 }) + "%",
      icon: Activity,
      color: "text-muted-foreground",
    },
    {
      label: "Bias (over/under)",
      value: (bias >= 0 ? "+" : "") + safePct(bias * 100).toLocaleString("it-IT", { maximumFractionDigits: 1 }) + "%",
      icon: Activity,
      color: bias >= 0 ? "text-emerald-600" : "text-rose-600",
    },
  ];

  return (
    <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
      {kpis.map((kpi) => (
        <Card key={kpi.label} className="p-4">
          <div className="flex items-center gap-3">
            <div className={`p-2 rounded-lg bg-muted ${kpi.color}`}>
              <kpi.icon className="w-4 h-4" />
            </div>
            <div>
              <p className="text-xs text-muted-foreground">{kpi.label}</p>
              <p className="text-lg font-semibold">{kpi.value}</p>
            </div>
          </div>
        </Card>
      ))}
    </div>
  );
}

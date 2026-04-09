import { Card } from "@/components/ui/card";
import { AnalyticsProMetrics } from "@/hooks/useAnalyticsProMetrics";
import { TrendingUp, TrendingDown, Target, AlertTriangle } from "lucide-react";

interface ForecastMetricsCardProps {
  metrics: AnalyticsProMetrics;
}

function formatPct(value: number | null): string {
  if (value == null) return "N/A";
  return value.toLocaleString("it-IT", { maximumFractionDigits: 1 }) + "%";
}

function formatNumber(value: number): string {
  return value.toLocaleString("it-IT", { maximumFractionDigits: 0 });
}

export function ForecastMetricsCard({ metrics }: ForecastMetricsCardProps) {
  const {
    forecastCoveragePct,
    mapePct,
    wapePct,
    biasPct,
    topUnderForecastDays,
    topOverForecastDays,
    totalDays,
    daysWithForecast,
  } = metrics;

  const hasForecast = daysWithForecast > 0;

  return (
    <Card className="p-4 space-y-4">
      <div className="flex items-center gap-2">
        <Target className="h-5 w-5 text-primary" />
        <h3 className="font-semibold text-lg">Metriche Forecast</h3>
      </div>

      {!hasForecast ? (
        <div className="text-muted-foreground text-sm flex items-center gap-2">
          <AlertTriangle className="h-4 w-4" />
          Nessun dato forecast disponibile nel range selezionato
        </div>
      ) : (
        <>
          {/* Main metrics grid */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <div className="space-y-1">
              <p className="text-xs text-muted-foreground">Copertura Forecast</p>
              <p className="text-xl font-bold">{formatPct(forecastCoveragePct)}</p>
              <p className="text-xs text-muted-foreground">
                {daysWithForecast}/{totalDays} giorni
              </p>
            </div>

            <div className="space-y-1">
              <p className="text-xs text-muted-foreground">MAPE</p>
              <p className="text-xl font-bold">{formatPct(mapePct)}</p>
              <p className="text-xs text-muted-foreground">Errore % medio</p>
            </div>

            <div className="space-y-1">
              <p className="text-xs text-muted-foreground">WAPE</p>
              <p className="text-xl font-bold">{formatPct(wapePct)}</p>
              <p className="text-xs text-muted-foreground">Errore % pesato</p>
            </div>

            <div className="space-y-1">
              <p className="text-xs text-muted-foreground">Bias</p>
              <p className={`text-xl font-bold ${biasPct != null && biasPct > 0 ? 'text-orange-500' : biasPct != null && biasPct < 0 ? 'text-blue-500' : ''}`}>
                {formatPct(biasPct)}
              </p>
              <p className="text-xs text-muted-foreground">
                {biasPct != null && biasPct > 0 ? 'Over-forecast' : biasPct != null && biasPct < 0 ? 'Under-forecast' : ''}
              </p>
            </div>
          </div>

          {/* Top deviations */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 pt-2 border-t">
            {/* Under-forecast */}
            <div className="space-y-2">
              <div className="flex items-center gap-1 text-sm font-medium">
                <TrendingUp className="h-4 w-4 text-green-500" />
                Top Under-forecast (venduto &gt; previsto)
              </div>
              {topUnderForecastDays.length === 0 ? (
                <p className="text-xs text-muted-foreground">Nessun giorno</p>
              ) : (
                <ul className="text-xs space-y-1">
                  {topUnderForecastDays.map((d) => (
                    <li key={d.data} className="flex justify-between">
                      <span>{d.data}</span>
                      <span className="text-green-600">+{formatNumber(d.deviation)}</span>
                    </li>
                  ))}
                </ul>
              )}
            </div>

            {/* Over-forecast */}
            <div className="space-y-2">
              <div className="flex items-center gap-1 text-sm font-medium">
                <TrendingDown className="h-4 w-4 text-red-500" />
                Top Over-forecast (previsto &gt; venduto)
              </div>
              {topOverForecastDays.length === 0 ? (
                <p className="text-xs text-muted-foreground">Nessun giorno</p>
              ) : (
                <ul className="text-xs space-y-1">
                  {topOverForecastDays.map((d) => (
                    <li key={d.data} className="flex justify-between">
                      <span>{d.data}</span>
                      <span className="text-red-600">-{formatNumber(d.deviation)}</span>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </div>
        </>
      )}
    </Card>
  );
}

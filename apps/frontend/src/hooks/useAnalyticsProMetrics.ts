import { useMemo } from 'react';
import { SeriesDataPoint } from './useAnalyticsSeries';

export interface ForecastDayDeviation {
  data: string;
  actual: number;
  forecast: number;
  deviation: number; // actual - forecast (positive = under-forecast, negative = over-forecast)
}

export interface AnalyticsProMetrics {
  /** % giorni con forecast disponibile (qty_forecast_tot != null) */
  forecastCoveragePct: number | null;
  /** Mean Absolute Percentage Error sui giorni con forecast e vendite > 0 */
  mapePct: number | null;
  /** Weighted Absolute Percentage Error: sum(|f-a|)/sum(a) * 100 */
  wapePct: number | null;
  /** Bias: (sum(f-a)/sum(a)) * 100 */
  biasPct: number | null;
  /** Top 5 giorni con maggior under-forecast (actual > forecast) */
  topUnderForecastDays: ForecastDayDeviation[];
  /** Top 5 giorni con maggior over-forecast (forecast > actual) */
  topOverForecastDays: ForecastDayDeviation[];
  /** Numero totale di giorni analizzati */
  totalDays: number;
  /** Numero di giorni con forecast */
  daysWithForecast: number;
}

export function useAnalyticsProMetrics(totalSeries: SeriesDataPoint[]): AnalyticsProMetrics {
  return useMemo(() => {
    // Default values for empty/invalid input
    const defaultResult: AnalyticsProMetrics = {
      forecastCoveragePct: null,
      mapePct: null,
      wapePct: null,
      biasPct: null,
      topUnderForecastDays: [],
      topOverForecastDays: [],
      totalDays: 0,
      daysWithForecast: 0,
    };

    if (!totalSeries || totalSeries.length === 0) {
      return defaultResult;
    }

    const totalDays = totalSeries.length;

    // Filter days with valid forecast
    const daysWithForecast = totalSeries.filter(
      (d) => d.qty_forecast_tot != null
    );

    const daysWithForecastCount = daysWithForecast.length;

    // 1. Forecast Coverage %
    const forecastCoveragePct = totalDays > 0 
      ? (daysWithForecastCount / totalDays) * 100 
      : null;

    // Filter days valid for error calculation (forecast exists AND actual > 0)
    const validForErrorCalc = daysWithForecast.filter(
      (d) => d.qty_venduta_tot > 0 && d.qty_forecast_tot != null
    );

    let mapePct: number | null = null;
    let wapePct: number | null = null;
    let biasPct: number | null = null;

    if (validForErrorCalc.length > 0) {
      // 2. MAPE: Mean Absolute Percentage Error
      // MAPE = (1/n) * sum(|actual - forecast| / actual) * 100
      let sumAbsPercentageError = 0;
      for (const d of validForErrorCalc) {
        const actual = d.qty_venduta_tot;
        const forecast = d.qty_forecast_tot!;
        sumAbsPercentageError += Math.abs(actual - forecast) / actual;
      }
      mapePct = (sumAbsPercentageError / validForErrorCalc.length) * 100;

      // 3. WAPE: Weighted Absolute Percentage Error
      // WAPE = sum(|forecast - actual|) / sum(actual) * 100
      let sumAbsError = 0;
      let sumActual = 0;
      for (const d of validForErrorCalc) {
        const actual = d.qty_venduta_tot;
        const forecast = d.qty_forecast_tot!;
        sumAbsError += Math.abs(forecast - actual);
        sumActual += actual;
      }
      wapePct = sumActual > 0 ? (sumAbsError / sumActual) * 100 : null;

      // 4. Bias: (sum(forecast - actual) / sum(actual)) * 100
      // Positive bias = over-forecasting, Negative bias = under-forecasting
      let sumError = 0;
      sumActual = 0;
      for (const d of validForErrorCalc) {
        const actual = d.qty_venduta_tot;
        const forecast = d.qty_forecast_tot!;
        sumError += forecast - actual;
        sumActual += actual;
      }
      biasPct = sumActual > 0 ? (sumError / sumActual) * 100 : null;
    }

    // 5. Top Under-forecast days (actual > forecast, deviation = actual - forecast > 0)
    // 6. Top Over-forecast days (forecast > actual, deviation = forecast - actual > 0)
    const deviations: ForecastDayDeviation[] = daysWithForecast
      .filter((d) => d.qty_forecast_tot != null)
      .map((d) => ({
        data: d.data,
        actual: d.qty_venduta_tot,
        forecast: d.qty_forecast_tot!,
        deviation: d.qty_venduta_tot - d.qty_forecast_tot!, // positive = under-forecast
      }));

    // Under-forecast: actual > forecast (deviation > 0), sorted descending
    const topUnderForecastDays = deviations
      .filter((d) => d.deviation > 0)
      .sort((a, b) => b.deviation - a.deviation)
      .slice(0, 5);

    // Over-forecast: forecast > actual (deviation < 0), sorted by most negative
    const topOverForecastDays = deviations
      .filter((d) => d.deviation < 0)
      .sort((a, b) => a.deviation - b.deviation) // most negative first
      .slice(0, 5)
      .map((d) => ({
        ...d,
        deviation: Math.abs(d.deviation), // show as positive for display
      }));

    return {
      forecastCoveragePct,
      mapePct,
      wapePct,
      biasPct,
      topUnderForecastDays,
      topOverForecastDays,
      totalDays,
      daysWithForecast: daysWithForecastCount,
    };
  }, [totalSeries]);
}

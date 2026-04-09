import { Package, TrendingUp, CalendarDays } from "lucide-react";
import { KpiCard } from "@/components/dashboard/KpiCard";
import { WeatherCard } from "@/components/dashboard/WeatherCard";
import { EventsCard } from "@/components/dashboard/EventsCard";
import { MonthlyCalendar } from "@/components/dashboard/MonthlyCalendar";
import { MonthlySalesChart } from "@/components/dashboard/MonthlySalesChart";
import { useDashboardKpis } from "@/hooks/useDashboardKpis";
import { ReorderSuggestionsCard } from "@/components/dashboard/ReorderSuggestionsCard";

type KpiCardItem = {
  title: string;
  value: string;
  change?: string;
  changeType?: "positive" | "negative" | "neutral";
  icon: any;
};

export default function Dashboard() {
  const { kpis, loading } = useDashboardKpis();

  const salesKpis: KpiCardItem[] = [
    {
      title: "Vendite (ultimi 7gg)",
      value: loading ? "..." : `€${kpis.salesWeek.toLocaleString("it-IT")}`,
      change: kpis.salesTrend !== null ? `${kpis.salesTrend >= 0 ? "+" : ""}${kpis.salesTrend}% vs sett. prec.` : "—",
      changeType: kpis.salesTrend === null ? "neutral" : kpis.salesTrend >= 0 ? "positive" : "negative",
      icon: TrendingUp,
    },
    {
      title: "Vendite (YTD)",
      value: loading ? "..." : `€${kpis.salesYtd.toLocaleString("it-IT")}`,
      change:
        kpis.salesYtdTrend !== null
          ? `${kpis.salesYtdTrend >= 0 ? "+" : ""}${kpis.salesYtdTrend}% vs YTD anno prec.`
          : "—",
      changeType: kpis.salesYtdTrend === null ? "neutral" : kpis.salesYtdTrend >= 0 ? "positive" : "negative",
      icon: CalendarDays,
    },
    {
      title: "Prodotti monitorati",
      value: loading ? "..." : String(kpis.productsMonitored ?? 0),
      change: "ultimo stock upload",
      changeType: "neutral",
      icon: Package,
    },
  ];

  return (
    // ✅ meno spazio verticale (prima era space-y-6)
    <div className="space-y-4">
      {/* ✅ header rimosso */}

      {/* ✅ Layout a 2 colonne: sinistra 8/12, destra 4/12 */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-4">
        {/* =========================
            COLONNA SINISTRA (8/12)
           ========================= */}
        <div className="lg:col-span-8 space-y-4">
          {/* TOP: calendario + meteo affiancati (stessa altezza) */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <MonthlyCalendar variant="compact" />
            <WeatherCard variant="compact" />
          </div>

          {/* KPI */}
          <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-3">
            {salesKpis.map((kpi, index) => (
              <KpiCard key={index} {...kpi} variant="compact" />
            ))}
          </div>

          {/* Grafico (sotto KPI, a sinistra) */}
          <MonthlySalesChart />
        </div>

        {/* =========================
            COLONNA DESTRA (4/12)
           ========================= */}
        <div className="lg:col-span-4 space-y-4">
          {/* Eventi sopra (stessa altezza delle card top) */}
          <EventsCard variant="compact" />

          {/* Riordini sotto */}
          <ReorderSuggestionsCard
            kpis={{
              reordersWeek: kpis.reordersWeek,
              reorderRiskLines: kpis.reorderRiskLines,
              reorderQtyTot: kpis.reorderQtyTot,
            }}
            kpiLoading={loading}
          />
        </div>
      </div>
    </div>
  );
}

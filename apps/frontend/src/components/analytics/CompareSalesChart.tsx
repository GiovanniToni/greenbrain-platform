import { useMemo, useState, useCallback } from "react";
import { Card } from "@/components/ui/card";
import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, Legend, Brush, CartesianGrid } from "recharts";
import { CompareSeries } from "@/hooks/useAnalyticsCompareSeries";
import { format, parseISO } from "date-fns";
import { it } from "date-fns/locale";

const COLORS = [
  "hsl(var(--primary))",
  "hsl(210, 70%, 50%)",
  "hsl(150, 60%, 45%)",
  "hsl(35, 90%, 55%)",
  "hsl(280, 60%, 55%)",
];

interface CompareSalesChartProps {
  series: CompareSeries[];
  loading?: boolean;
  brushRange?: { startIndex: number; endIndex: number } | null;
  onBrushChange?: (range: { startIndex: number; endIndex: number }) => void;
}

function formatDateLabel(dateStr: string) {
  try {
    return format(parseISO(dateStr), "d MMM yyyy", { locale: it });
  } catch {
    return dateStr;
  }
}

function formatShortDate(dateStr: string) {
  try {
    return format(parseISO(dateStr), "d/M", { locale: it });
  } catch {
    return dateStr;
  }
}

export function CompareSalesChart({ series, loading, brushRange, onBrushChange }: CompareSalesChartProps) {
  const [internalBrush, setInternalBrush] = useState<{ startIndex: number; endIndex: number } | null>(null);

  const effectiveBrush = brushRange ?? internalBrush;

  const handleBrushChange = useCallback(
    (brushData: any) => {
      if (brushData && brushData.startIndex !== undefined && brushData.endIndex !== undefined) {
        const range = { startIndex: brushData.startIndex, endIndex: brushData.endIndex };
        if (onBrushChange) {
          onBrushChange(range);
        } else {
          setInternalBrush(range);
        }
      }
    },
    [onBrushChange],
  );

  // Merge all series into a single dataset indexed by date
  const chartData = useMemo(() => {
    if (!series || series.length === 0) return [];

    const dateMap = new Map<string, Record<string, number | null>>();

    series.forEach((s) => {
      s.points.forEach((p) => {
        if (!dateMap.has(p.data)) {
          dateMap.set(p.data, { data: p.data as any });
        }
        const entry = dateMap.get(p.data)!;
        entry[s.key] = p.qty;
      });
    });

    const sorted = Array.from(dateMap.values()).sort((a, b) => {
      const dateA = a.data as unknown as string;
      const dateB = b.data as unknown as string;
      return dateA.localeCompare(dateB);
    });

    return sorted;
  }, [series]);

  if (loading) {
    return (
      <Card className="p-6">
        <div className="text-muted-foreground">Caricamento confronto...</div>
      </Card>
    );
  }

  if (!series || series.length < 2) {
    return (
      <Card className="p-6">
        <p className="text-muted-foreground text-sm">Seleziona almeno 2 entità per confrontare le vendite.</p>
      </Card>
    );
  }

  if (chartData.length === 0) {
    return (
      <Card className="p-6">
        <p className="text-muted-foreground text-sm">Nessun dato disponibile per il periodo selezionato.</p>
      </Card>
    );
  }

  return (
    <Card className="p-6">
      <div className="mb-4">
        <h3 className="text-lg font-semibold">Confronto Vendite</h3>
        <p className="text-sm text-muted-foreground">Quantità vendute giornaliere per le entità selezionate</p>
      </div>

      <div className="h-[400px]">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={chartData} margin={{ top: 10, right: 30, left: 0, bottom: 0 }}>
            <CartesianGrid strokeDasharray="3 3" className="stroke-muted" />
            <XAxis
              dataKey="data"
              tickFormatter={formatShortDate}
              tick={{ fontSize: 11 }}
              className="text-muted-foreground"
            />
            <YAxis tick={{ fontSize: 11 }} className="text-muted-foreground" />
            <Tooltip
              content={({ active, payload, label }) => {
                if (!active || !payload || payload.length === 0) return null;
                return (
                  <div className="rounded-lg border bg-background p-3 shadow-md">
                    <p className="font-medium mb-2">{formatDateLabel(label)}</p>
                    {payload.map((entry: any, idx: number) => {
                      const seriesItem = series.find((s) => s.key === entry.dataKey);
                      return (
                        <div key={idx} className="flex items-center gap-2 text-sm">
                          <span className="w-3 h-3 rounded-full" style={{ backgroundColor: entry.color }} />
                          <span className="text-muted-foreground">{seriesItem?.label ?? entry.dataKey}:</span>
                          <span className="font-medium">
                            {entry.value?.toLocaleString("it-IT", { maximumFractionDigits: 0 }) ?? "-"}
                          </span>
                        </div>
                      );
                    })}
                  </div>
                );
              }}
            />
            <Legend
              formatter={(value) => {
                const seriesItem = series.find((s) => s.key === value);
                return seriesItem?.label ?? value;
              }}
            />
            {series.map((s, idx) => (
              <Line
                key={s.key}
                type="monotone"
                dataKey={s.key}
                stroke={COLORS[idx % COLORS.length]}
                strokeWidth={2}
                dot={false}
                activeDot={{ r: 4 }}
              />
            ))}
            <Brush
              dataKey="data"
              height={30}
              stroke="hsl(var(--primary))"
              tickFormatter={formatShortDate}
              startIndex={effectiveBrush?.startIndex}
              endIndex={effectiveBrush?.endIndex}
              onChange={handleBrushChange}
            />
          </LineChart>
        </ResponsiveContainer>
      </div>
    </Card>
  );
}

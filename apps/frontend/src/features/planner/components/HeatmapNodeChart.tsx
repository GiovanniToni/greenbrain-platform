import { useMemo } from "react";
import {
  ResponsiveContainer,
  LineChart,
  Line,
  CartesianGrid,
  Tooltip,
  XAxis,
  YAxis,
  ReferenceLine,
  Legend,
} from "recharts";
import { HeatCell, HeatMetric, HeatNode } from "../types";

type Props = {
  title: string;
  nodeIds: string[];
  nodesById: Map<string, HeatNode>;
  cellsByNode: Record<string, Record<number, HeatCell>>;
  metric: HeatMetric;
  currentWeek52: number;
};

function wLabel(w: number) {
  return `W${String(w).padStart(2, "0")}`;
}

function getMetricValue(c: HeatCell | undefined, metric: HeatMetric): number | null {
  if (!c) return null;
  switch (metric) {
    case "avg_qty":
      return Number(c.avg_qty ?? 0);
    case "avg_rev":
      return Number(c.avg_rev ?? 0);
    case "share_rev":
      return Number(c.share_rev ?? 0) * 100;
    case "stock_target":
      return c.stock_target == null ? null : Number(c.stock_target);
    case "space_m2":
      return c.space_m2 == null ? null : Number(c.space_m2);
    default:
      return null;
  }
}

export function HeatmapNodeChart({ title, nodeIds, nodesById, cellsByNode, metric, currentWeek52 }: Props) {
  const safeIds = useMemo(() => (nodeIds ?? []).filter(Boolean), [nodeIds]);

  const { data, series } = useMemo(() => {
    // mappa id -> key breve (recharts)
    const series = safeIds.map((id, idx) => {
      const label = nodesById.get(id)?.label ?? id;
      return { id, key: `n${idx}`, label };
    });

    const data = Array.from({ length: 52 }, (_, i) => i + 1).map((w) => {
      const row: Record<string, any> = { week_52: w, week: wLabel(w) };
      for (const s of series) {
        const c = (cellsByNode[s.id] ?? {})[w];
        row[s.key] = getMetricValue(c, metric);
      }
      return row;
    });

    return { data, series };
  }, [safeIds, nodesById, cellsByNode, metric]);

  if (safeIds.length === 0) {
    return (
      <div className="p-4 text-sm text-muted-foreground">
        Seleziona uno o più nodi (click sul nome) per vedere il grafico.
      </div>
    );
  }

  return (
    <div className="w-full">
      <div className="px-4 pt-4 pb-2">
        <div className="text-sm font-medium">{title}</div>
        <div className="text-xs text-muted-foreground">
          Nodi selezionati: <span className="tabular-nums">{safeIds.length}</span>
        </div>
      </div>

      <div className="h-[300px] px-2 pb-4">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={data} margin={{ top: 10, right: 20, left: 0, bottom: 0 }}>
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis dataKey="week" interval={3} />
            <YAxis />
            <Tooltip />
            <Legend
              formatter={(value) => {
                const s = series.find((x) => x.key === value);
                return s?.label ?? String(value);
              }}
            />
            <ReferenceLine x={wLabel(currentWeek52)} strokeDasharray="4 4" />
            <ReferenceLine x={wLabel(currentWeek52 + 1)} strokeDasharray="2 2" />
            {series.map((s) => (
              <Line key={s.key} type="monotone" dataKey={s.key} dot={false} />
            ))}
          </LineChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}

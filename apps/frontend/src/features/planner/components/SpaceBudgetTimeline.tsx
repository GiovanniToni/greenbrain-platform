import { useMemo } from "react";
import { Area, AreaChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis, ReferenceLine } from "recharts";
import { SpaceBudgetRow } from "../types";

type Props = {
  rows: SpaceBudgetRow[];
  showAsPercent: boolean; // true = share, false = m²
  topN?: number; // default 12
  currentWeek52: number;
};

const SERIES_COLORS = [
  "#2563eb",
  "#dc2626",
  "#16a34a",
  "#9333ea",
  "#ea580c",
  "#0891b2",
  "#ca8a04",
  "#be123c",
  "#4f46e5",
  "#0f766e",
  "#7c2d12",
  "#64748b",
];

function wLabel(w: number) {
  return `W${String(w).padStart(2, "0")}`;
}

export function SpaceBudgetTimeline({ rows, showAsPercent, topN = 12, currentWeek52 }: Props) {
  const { data, seriesKeys } = useMemo(() => {
    const totals = new Map<string, number>();
    for (const r of rows) {
      const v = showAsPercent ? r.space_share : r.space_m2_raw;
      totals.set(r.node_id, (totals.get(r.node_id) ?? 0) + (Number(v) || 0));
    }

    const topNodes = Array.from(totals.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, topN)
      .map(([id]) => id);
    const topSet = new Set(topNodes);

    const byWeek = new Map<number, any>();
    for (const r of rows) {
      const w = r.week_52;
      if (!byWeek.has(w)) byWeek.set(w, { week_52: w, week: wLabel(w) });
      const rec = byWeek.get(w);
      const k = topSet.has(r.node_id) ? r.node_id : "Other";
      const v = showAsPercent ? r.space_share : r.space_m2_raw;
      rec[k] = (rec[k] ?? 0) + (Number(v) || 0);
    }

    const data = Array.from(byWeek.values()).sort((a, b) => a.week_52 - b.week_52);

    const keys = new Set<string>();
    for (const d of data) {
      for (const k of Object.keys(d)) {
        if (k !== "week_52" && k !== "week") keys.add(k);
      }
    }
    const arr = Array.from(keys)
      .filter((k) => k !== "Other")
      .sort();
    if (keys.has("Other")) arr.push("Other");

    return { data, seriesKeys: arr };
  }, [rows, showAsPercent, topN]);

  return (
    <div className="w-full h-[260px]">
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={data} margin={{ top: 10, right: 20, left: 0, bottom: 0 }}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis dataKey="week" interval={3} />
          <YAxis
            tickFormatter={(v) => (showAsPercent ? `${Math.round(Number(v) * 100)}%` : `${Math.round(Number(v))}`)}
          />
          <Tooltip
            formatter={(val: any) =>
              showAsPercent ? `${(Number(val) * 100).toFixed(1)}%` : `${Number(val).toFixed(1)} m²`
            }
          />
          <ReferenceLine x={wLabel(currentWeek52)} strokeDasharray="4 4" />
          <ReferenceLine x={wLabel(currentWeek52 + 1)} strokeDasharray="2 2" />
          {seriesKeys.map((k, idx) => (
            <Area
              key={k}
              type="monotone"
              dataKey={k}
              stackId="1"
              dot={false}
              stroke={SERIES_COLORS[idx % SERIES_COLORS.length]}
              fill={SERIES_COLORS[idx % SERIES_COLORS.length]}
              fillOpacity={0.28}
              strokeWidth={2}
            />
          ))}
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}

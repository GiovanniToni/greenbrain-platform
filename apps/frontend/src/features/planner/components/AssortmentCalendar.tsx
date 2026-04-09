import { useMemo } from "react";
import { cn } from "@/lib/utils";
import { AssortmentCalendarRow, AssortmentState, HeatNode } from "../types";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";

type Props = {
  rows: AssortmentCalendarRow[];
  currentWeek52: number;
  topN?: number;
  onSelect?: (nodeId: string, week52: number) => void;

  // ✅ NEW: per rendere "Nodo" leggibile (label + path)
  nodesById?: Map<string, HeatNode>;
};

const WEEKS = Array.from({ length: 52 }, (_, i) => i + 1);

function wLabel(w: number) {
  return `W${String(w).padStart(2, "0")}`;
}

function stateClass(state: AssortmentState): string {
  switch (state) {
    case "OFF":
      return "bg-muted/30";
    case "LOW":
      return "bg-primary/10";
    case "MED":
      return "bg-primary/20";
    case "HIGH":
      return "bg-primary/35";
    default:
      return "bg-muted/30";
  }
}

function parseNodeIdParts(nodeId: string): { kind?: string; parts: string[] } {
  // formato: livello::fascia::categoria::famiglia ...
  const parts = String(nodeId ?? "")
    .split("::")
    .filter(Boolean);
  if (parts.length === 0) return { parts: [] };
  return { kind: parts[0], parts: parts.slice(1) };
}

function nodeDisplay(nodeId: string, nodesById?: Map<string, HeatNode>) {
  const node = nodesById?.get(nodeId);
  if (node) {
    const crumbs = [node.fascia, node.categoria, node.famiglia, node.fascia_prezzo].filter(Boolean);
    const path = crumbs.join(" / ");
    return {
      title: node.label || nodeId,
      subtitle: path || node.level,
      meta: node.level,
    };
  }

  // fallback: parse node_id string
  const parsed = parseNodeIdParts(nodeId);
  const path = parsed.parts.join(" / ");
  return {
    title: parsed.parts[parsed.parts.length - 1] || nodeId,
    subtitle: path || (parsed.kind ?? ""),
    meta: parsed.kind ?? "",
  };
}

export function AssortmentCalendar({ rows, currentWeek52, topN = 60, onSelect, nodesById }: Props) {
  const { rowIds, byNodeWeek } = useMemo(() => {
    const byNode: Record<string, Record<number, AssortmentCalendarRow>> = {};
    const totals = new Map<string, number>();

    for (const r of rows) {
      if (!byNode[r.node_id]) byNode[r.node_id] = {};
      byNode[r.node_id][r.week_52] = r;

      totals.set(r.node_id, (totals.get(r.node_id) ?? 0) + (r.space_share ?? 0));
    }

    const top = Array.from(totals.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, topN)
      .map(([id]) => id);

    return { rowIds: top, byNodeWeek: byNode };
  }, [rows, topN]);

  if (rows.length === 0) {
    return <div className="p-4 text-muted-foreground text-sm">Nessun dato Assortment Calendar.</div>;
  }

  return (
    <div className="w-full overflow-x-auto border rounded-md">
      <table className="min-w-max text-xs border-collapse">
        <thead>
          <tr className="bg-muted/50">
            <th className="sticky left-0 z-10 bg-muted/50 px-2 py-1 text-left font-medium min-w-[260px]">Nodo</th>
            {WEEKS.map((w) => (
              <th
                key={w}
                className={cn(
                  "px-1 py-1 text-center font-medium min-w-[40px]",
                  w === currentWeek52 && "bg-accent/40",
                  w === currentWeek52 + 1 && "bg-accent/20",
                )}
              >
                {wLabel(w)}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rowIds.map((nodeId) => {
            const cells = byNodeWeek[nodeId] ?? {};
            const disp = nodeDisplay(nodeId, nodesById);

            return (
              <tr key={nodeId} className="border-t border-border/50 hover:bg-muted/20">
                <td className="sticky left-0 z-10 bg-background px-2 py-1">
                  <div className="flex flex-col leading-tight">
                    <div className="font-medium truncate max-w-[260px]">{disp.title}</div>
                    <div className="text-[11px] text-muted-foreground truncate max-w-[260px]">{disp.subtitle}</div>
                    <div className="text-[10px] text-muted-foreground/70 truncate max-w-[260px]">{nodeId}</div>
                  </div>
                </td>

                {WEEKS.map((w) => {
                  const c = cells[w];
                  const st = c?.state ?? "OFF";

                  const cellContent = (
                    <div
                      className={cn(
                        "w-full h-6 flex items-center justify-center text-[10px] cursor-pointer transition-colors select-none",
                        stateClass(st),
                        w === currentWeek52 && "ring-1 ring-accent",
                        w === currentWeek52 + 1 && "ring-1 ring-accent/50",
                      )}
                      onClick={() => onSelect?.(nodeId, w)}
                      role="button"
                      tabIndex={0}
                    >
                      {st}
                    </div>
                  );

                  if (!c) {
                    return (
                      <td key={w} className="p-0">
                        {cellContent}
                      </td>
                    );
                  }

                  return (
                    <td key={w} className="p-0">
                      <Tooltip>
                        <TooltipTrigger asChild>{cellContent}</TooltipTrigger>
                        <TooltipContent side="top" className="text-xs">
                          <p className="font-medium">State: {c.state}</p>
                          <p>Share: {(c.space_share * 100).toFixed(1)}%</p>
                          <p>Space: {c.space_m2_raw.toLocaleString("it-IT", { maximumFractionDigits: 1 })} m²</p>
                          {c.stock_target != null && (
                            <p>Stock target: {Math.round(c.stock_target).toLocaleString("it-IT")}</p>
                          )}
                        </TooltipContent>
                      </Tooltip>
                    </td>
                  );
                })}
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

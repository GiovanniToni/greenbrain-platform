import { useMemo } from "react";
import { ChevronRight, ChevronDown } from "lucide-react";
import { cn } from "@/lib/utils";
import { HeatNode, HeatCell as HeatCellType, HeatMetric, HeatRange, PlannerLevel } from "../types";
import { HeatCell } from "./HeatCell";

type Props = {
  rootIds: string[];
  nodesById: Map<string, HeatNode>;
  childrenByParent: Map<string | null, string[]>;
  openMap: Record<string, boolean>;
  setOpenMap: React.Dispatch<React.SetStateAction<Record<string, boolean>>>;
  cellsByNode: Record<string, Record<number, HeatCellType>>;
  metric: HeatMetric;
  currentWeek52: number;
  rangesByNode: Record<string, Record<number, HeatRange>>;
  showRange: boolean;

  // ✅ multi-select
  selectedNodeIds?: string[];
  onToggleSelectNode?: (nodeId: string) => void;
};

const LEVEL_INDENT: Record<PlannerLevel, number> = {
  fascia: 0,
  categoria: 1,
  famiglia: 2,
  fascia_prezzo: 3,
};

const WEEKS = Array.from({ length: 52 }, (_, i) => i + 1);

type FlatRow = {
  nodeId: string;
  node: HeatNode;
  depth: number;
  hasChildren: boolean;
};

function flattenVisible(
  ids: string[],
  nodesById: Map<string, HeatNode>,
  childrenByParent: Map<string | null, string[]>,
  openMap: Record<string, boolean>,
  depth: number,
): FlatRow[] {
  const result: FlatRow[] = [];
  for (const id of ids) {
    const node = nodesById.get(id);
    if (!node) continue;
    const childIds = childrenByParent.get(id) ?? [];
    const hasChildren = childIds.length > 0;
    result.push({ nodeId: id, node, depth, hasChildren });
    if (hasChildren && openMap[id]) {
      result.push(...flattenVisible(childIds, nodesById, childrenByParent, openMap, depth + 1));
    }
  }
  return result;
}

export function HeatmapTreeTable({
  rootIds,
  nodesById,
  childrenByParent,
  openMap,
  setOpenMap,
  cellsByNode,
  metric,
  currentWeek52,
  rangesByNode,
  showRange,
  selectedNodeIds = [],
  onToggleSelectNode,
}: Props) {
  const rows = useMemo(
    () => flattenVisible(rootIds, nodesById, childrenByParent, openMap, 0),
    [rootIds, nodesById, childrenByParent, openMap],
  );

  const selectedSet = useMemo(() => new Set(selectedNodeIds), [selectedNodeIds]);

  const toggleOpen = (nodeId: string) => {
    setOpenMap((prev) => ({ ...prev, [nodeId]: !prev[nodeId] }));
  };

  return (
    <div className="overflow-auto border border-border rounded-lg bg-card">
      <table className="text-xs w-max min-w-full border-collapse">
        <thead className="sticky top-0 z-20 bg-muted">
          <tr>
            <th className="sticky left-0 z-30 bg-muted px-3 py-2 text-left font-semibold min-w-[240px] border-b border-r border-border">
              Nodo
            </th>
            {WEEKS.map((w) => (
              <th
                key={w}
                className={cn(
                  "px-1 py-2 text-center font-medium border-b border-border min-w-[42px]",
                  w === currentWeek52 && "bg-primary/10",
                  w === currentWeek52 + 1 && "bg-primary/20",
                )}
              >
                W{String(w).padStart(2, "0")}
              </th>
            ))}
          </tr>
        </thead>

        <tbody>
          {rows.map(({ nodeId, node, depth, hasChildren }) => {
            const nodeCells = cellsByNode[nodeId] ?? {};
            const isOpen = !!openMap[nodeId];
            const indentPx = (LEVEL_INDENT[node.level] + depth) * 16;
            const isSelected = selectedSet.has(nodeId);

            return (
              <tr key={nodeId} className={cn("hover:bg-muted/40", isSelected && "bg-accent/20")}>
                <td
                  className="sticky left-0 z-10 bg-card px-2 py-1 border-r border-border whitespace-nowrap"
                  style={{ paddingLeft: `${8 + indentPx}px` }}
                >
                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      onClick={() => hasChildren && toggleOpen(nodeId)}
                      className={cn(
                        "inline-flex items-center gap-1 text-left",
                        hasChildren ? "cursor-pointer" : "cursor-default",
                      )}
                      disabled={!hasChildren}
                      title={hasChildren ? "Apri/chiudi" : ""}
                    >
                      {hasChildren ? (
                        isOpen ? (
                          <ChevronDown className="w-4 h-4 text-muted-foreground" />
                        ) : (
                          <ChevronRight className="w-4 h-4 text-muted-foreground" />
                        )
                      ) : (
                        <span className="w-4" />
                      )}
                    </button>

                    <button
                      type="button"
                      onClick={() => onToggleSelectNode?.(nodeId)}
                      className={cn(
                        "text-left",
                        onToggleSelectNode ? "cursor-pointer hover:underline" : "cursor-default",
                      )}
                      title="Seleziona (multi) per grafico"
                    >
                      <span className="truncate max-w-[180px] font-medium">{node.label}</span>
                      <span className="ml-2 text-[10px] text-muted-foreground">{node.level}</span>
                      {isSelected && <span className="ml-2 text-[10px] text-muted-foreground">✓</span>}
                    </button>
                  </div>
                </td>

                {WEEKS.map((w) => (
                  <td key={w} className="p-0 border-b border-border">
                    <HeatCell
                      cell={nodeCells[w]}
                      metric={metric}
                      isCurrent={w === currentWeek52}
                      isNext={w === currentWeek52 + 1}
                      range={rangesByNode[nodeId]?.[w]}
                      showRange={showRange}
                    />
                  </td>
                ))}
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

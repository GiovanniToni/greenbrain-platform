import { useMemo, useState } from "react";
import { X } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { AnalyticsEntitySearch } from "@/components/analytics/AnalyticsEntitySearch";
import type { CatalogItem } from "@/hooks/useAnalyticsCatalog";
import type { CompareItem } from "@/hooks/useAnalyticsCompareSeries";

interface Props {
  selectedItems: CompareItem[];
  onChange: (items: CompareItem[]) => void;
  maxItems?: number;
}

export function CompareEntitySelector({ selectedItems, onChange, maxItems = 5 }: Props) {
  const [lastSelected, setLastSelected] = useState<CatalogItem | null>(null);

  const canAddMore = selectedItems.length < maxItems;

  const handleAdd = (item: CatalogItem) => {
    // allow only famiglia/categoria/fascia
    if (!["famiglia", "categoria", "fascia"].includes(item.entity_type)) {
      return;
    }

    const key = `${item.entity_type}__${item.entity_key}`;
    const exists = selectedItems.some((x) => `${x.entity_type}__${x.entity_key}` === key);
    if (exists) return;

    if (!canAddMore) return;

    onChange([
      ...selectedItems,
      { entity_type: item.entity_type as any, entity_key: item.entity_key, label: item.label },
    ]);
    setLastSelected(item);
  };

  const removeAt = (idx: number) => {
    const next = selectedItems.slice();
    next.splice(idx, 1);
    onChange(next);
  };

  const clearAll = () => onChange([]);

  const helper = useMemo(() => {
    if (selectedItems.length === 0) return `Seleziona 2–${maxItems} entità (famiglia/categoria/fascia)`;
    if (selectedItems.length === 1) return `Aggiungi almeno un'altra entità (minimo 2)`;
    return `Puoi aggiungere fino a ${maxItems} entità`;
  }, [selectedItems.length, maxItems]);

  return (
    <div className="space-y-3">
      <div className="text-sm text-muted-foreground">{helper}</div>

      <AnalyticsEntitySearch onSelect={handleAdd} selectedItem={lastSelected} />

      {selectedItems.length > 0 && (
        <Card className="p-3">
          <div className="flex flex-wrap gap-2 items-center">
            {selectedItems.map((it, idx) => (
              <div
                key={`${it.entity_type}__${it.entity_key}`}
                className="flex items-center gap-2 rounded-full border px-3 py-1 text-sm"
              >
                <span className="text-xs text-muted-foreground">{it.entity_type}</span>
                <span className="font-medium">{it.label}</span>
                <button className="opacity-70 hover:opacity-100" onClick={() => removeAt(idx)} aria-label="remove">
                  <X className="w-4 h-4" />
                </button>
              </div>
            ))}

            <div className="ml-auto flex gap-2">
              <Button variant="outline" size="sm" onClick={clearAll}>
                Svuota
              </Button>
            </div>
          </div>

          {!canAddMore && <div className="mt-2 text-xs text-muted-foreground">Limite raggiunto ({maxItems}).</div>}
        </Card>
      )}
    </div>
  );
}

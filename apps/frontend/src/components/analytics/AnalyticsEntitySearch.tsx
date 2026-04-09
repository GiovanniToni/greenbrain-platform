import { useState, useEffect, useRef, useMemo } from "react";
import { Search } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Card } from "@/components/ui/card";
import { useAnalyticsCatalog, CatalogItem } from "@/hooks/useAnalyticsCatalog";

import { Button } from "@/components/ui/button";
import { CatalogBrowserDialog } from "@/components/analytics/CatalogBrowserDialog";

interface AnalyticsEntitySearchProps {
  onSelect: (item: CatalogItem) => void;
  selectedItem: CatalogItem | null;
}

const ENTITY_TYPE_LABELS: Record<string, string> = {
  famiglia: "Famiglia",
  categoria: "Categoria",
  fascia: "Fascia",
  fascia_prezzo: "Fascia Prezzo",
  articolo: "Articolo",
};

const ENTITY_TYPE_PRIORITY: Record<string, number> = {
  fascia: 1,
  categoria: 2,
  famiglia: 3,
  articolo: 4,
};

function escapeRegExp(s: string) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function HighlightMatch({ text, term }: { text: string; term: string }) {
  const t = (term ?? "").trim();
  if (!t) return <>{text}</>;

  // evidenziamo il match "semplice" (substring), non trigram
  const re = new RegExp(`(${escapeRegExp(t)})`, "ig");
  const parts = text.split(re);

  return (
    <>
      {parts.map((p, i) =>
        i % 2 === 1 ? (
          <mark key={i} className="bg-amber-200/60 text-foreground rounded px-0.5">
            {p}
          </mark>
        ) : (
          <span key={i}>{p}</span>
        ),
      )}
    </>
  );
}

export function AnalyticsEntitySearch({ onSelect, selectedItem }: AnalyticsEntitySearchProps) {
  const [searchTerm, setSearchTerm] = useState("");
  const [isOpen, setIsOpen] = useState(false);
  const { items, loading, error, search, clear } = useAnalyticsCatalog();
  const containerRef = useRef<HTMLDivElement>(null);

  // debounce: evita chiamate continue e aiuta coi timeout
  useEffect(() => {
    const t = searchTerm.trim();
    if (t.length < 2) {
      clear();
      setIsOpen(false);
      return;
    }

    const timer = setTimeout(() => {
      search(t);
    }, 250);

    return () => clearTimeout(timer);
  }, [searchTerm, search, clear]);

  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setIsOpen(false);
      }
    };
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  const handleSelect = (item: CatalogItem) => {
    onSelect(item);
    setSearchTerm("");
    setIsOpen(false);
  };

  // "forse intendevi": se il top result ha score alto e l'input NON coincide col label
  const suggestion = useMemo(() => {
    const t = searchTerm.trim().toLowerCase();
    if (t.length < 2) return null;
    if (!items || items.length === 0) return null;

    const top = items[0];
    const topLabel = (top.label ?? "").toLowerCase();
    const score = typeof top.score === "number" ? top.score : null;

    if (!score) return null;
    if (topLabel === t) return null;

    // soglia ragionevole (con cicln -> ciclamino stai a 0.33, quindi ok)
    if (score >= 0.25) return top;
    return null;
  }, [items, searchTerm]);

  const sortedItems = useMemo(() => {
    const t = searchTerm.trim();
    if (t.length < 2) return [];

    const arr = [...(items ?? [])];

    arr.sort((a, b) => {
      const pa = ENTITY_TYPE_PRIORITY[a.entity_type] ?? 99;
      const pb = ENTITY_TYPE_PRIORITY[b.entity_type] ?? 99;
      if (pa !== pb) return pa - pb;

      // dentro il tipo: score desc (se presente)
      const sa = typeof a.score === "number" ? a.score : -1;
      const sb = typeof b.score === "number" ? b.score : -1;
      if (sa !== sb) return sb - sa;

      // tie-breaker: label asc (IT)
      return (a.label ?? "").localeCompare(b.label ?? "", "it-IT", { sensitivity: "base" });
    });

    return arr;
  }, [items, searchTerm]);

  return (
    <div ref={containerRef} className="relative w-full">
      <div className="flex items-center gap-2">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
          <Input
            placeholder="Cerca famiglia, categoria, fascia..."
            value={searchTerm}
            onChange={(e) => {
              setSearchTerm(e.target.value);
              setIsOpen(true);
            }}
            onFocus={() => setIsOpen(true)}
            className="pl-10"
          />
        </div>

        <CatalogBrowserDialog
          onSelect={(item) => {
            handleSelect(item);
          }}
          triggerLabel="Sfoglia"
        />
      </div>

      {isOpen && searchTerm.trim().length >= 2 && (
        <Card className="absolute z-50 w-full mt-1 max-h-72 overflow-auto shadow-lg">
          {error && <div className="p-3 text-sm text-destructive border-b border-border">{error}</div>}

          {suggestion && !loading && (
            <div className="p-3 text-sm border-b border-border bg-muted/40">
              Forse intendevi{" "}
              <button className="font-semibold underline underline-offset-2" onClick={() => handleSelect(suggestion)}>
                {suggestion.label}
              </button>
              {typeof suggestion.score === "number" && (
                <span className="text-xs text-muted-foreground ml-2">
                  (match {(suggestion.score * 100).toFixed(0)}%)
                </span>
              )}
            </div>
          )}

          {loading ? (
            <div className="p-3 text-sm text-muted-foreground">Caricamento...</div>
          ) : sortedItems.length === 0 ? (
            <div className="p-3 text-sm text-muted-foreground">Nessun risultato</div>
          ) : (
            <ul className="py-1">
              {sortedItems.map((item, idx) => (
                <li
                  key={`${item.entity_type}-${item.entity_key}-${idx}`}
                  className="px-3 py-2 hover:bg-muted cursor-pointer flex justify-between items-center"
                  onClick={() => handleSelect(item)}
                >
                  <span className="text-sm">
                    <HighlightMatch text={item.label} term={searchTerm.trim()} />
                  </span>

                  <span className="text-xs text-muted-foreground bg-muted px-2 py-0.5 rounded flex items-center gap-2">
                    {ENTITY_TYPE_LABELS[item.entity_type] || item.entity_type}
                    {typeof item.score === "number" && (
                      <span className="text-[10px] opacity-70">{(item.score * 100).toFixed(0)}%</span>
                    )}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>
      )}
    </div>
  );
}

// src/components/analytics/CatalogBrowserDialog.tsx

import { useEffect, useMemo, useRef, useState } from "react";
import { Search, ChevronRight } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Card } from "@/components/ui/card";

import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion";

import { useCatalogTree, CatalogTreeNode, CatalogNodeType } from "@/hooks/useCatalogTree";
import type { CatalogItem } from "@/hooks/useAnalyticsCatalog";
import { useAnalyticsCatalog } from "@/hooks/useAnalyticsCatalog";

type Props = {
  triggerLabel?: string;
  onSelect: (item: CatalogItem) => void;
};

const TYPE_LABEL: Record<string, string> = {
  fascia: "Fascia",
  categoria: "Categoria",
  famiglia: "Famiglia",
  fascia_prezzo: "Fascia prezzo",
  articolo: "Articolo",
};

function norm(s: string) {
  return (s ?? "").trim().toLowerCase();
}

function fmtPriceEUR(v: any) {
  const n = Number(v);
  if (!isFinite(n)) return "-";
  return n.toLocaleString("it-IT", { style: "currency", currency: "EUR" });
}

/** Ordine custom fasce prezzo */
const FASCIA_PREZZO_ORDER: string[] = [
  "0 - 2,99€",
  "3 - 4,99€",
  "5 - 9,99€",
  "10 - 14,99€",
  "15 - 19,99€",
  "20 - 24,99€",
  "25 - 29,99€",
  "30 - 39,99€",
  "40 - 49,99€",
  "50 - 59,99€",
  "60 - 69,99€",
  "70 - 99,99€",
  "100 - 149,99€",
  "150 - 199,99€",
  "200€ - >",
];

const FP_INDEX = new Map(FASCIA_PREZZO_ORDER.map((l, i) => [norm(l), i]));

function sortAlphaIT(a: string, b: string) {
  return a.localeCompare(b, "it-IT", { sensitivity: "base" });
}

function sortNodesAlpha(nodes: CatalogTreeNode[]) {
  return [...nodes].sort((a, b) => sortAlphaIT(a.label, b.label));
}

function sortFascePrezzo(nodes: CatalogTreeNode[]) {
  return [...nodes].sort((a, b) => {
    const ia = FP_INDEX.has(norm(a.label)) ? (FP_INDEX.get(norm(a.label)) as number) : 999;
    const ib = FP_INDEX.has(norm(b.label)) ? (FP_INDEX.get(norm(b.label)) as number) : 999;
    if (ia !== ib) return ia - ib;
    return sortAlphaIT(a.label, b.label);
  });
}

/** Articoli: ordina per pot_size (crescente); se manca pot_size va in fondo; tie-breaker per label */
function parsePotSize(p: any): number | null {
  if (p == null) return null;
  const s = String(p).trim();
  if (!s) return null;
  const m = s.replace(",", ".").match(/(\d+(\.\d+)?)/);
  if (!m) return null;
  const n = Number(m[1]);
  return isFinite(n) ? n : null;
}

function sortArticoli(nodes: CatalogTreeNode[]) {
  return [...nodes].sort((a, b) => {
    const pa = parsePotSize(a.extra?.pot_size);
    const pb = parsePotSize(b.extra?.pot_size);

    const aHas = pa != null;
    const bHas = pb != null;

    if (aHas && bHas && pa !== pb) return (pa as number) - (pb as number);
    if (aHas && !bHas) return -1;
    if (!aHas && bHas) return 1;

    // entrambi SENZA pot_size -> ordina per prezzo crescente (poi label)
    const priceA = Number(a.extra?.prezzo_iva_inclusa);
    const priceB = Number(b.extra?.prezzo_iva_inclusa);

    const aPriceOk = Number.isFinite(priceA);
    const bPriceOk = Number.isFinite(priceB);

    if (aPriceOk && bPriceOk && priceA !== priceB) return priceA - priceB;
    if (aPriceOk && !bPriceOk) return -1;
    if (!aPriceOk && bPriceOk) return 1;

    return sortAlphaIT(a.label, b.label);
  });
}

function escapeRegExp(s: string) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/** Highlight substring match (case-insensitive), without filtering the tree */
function HighlightMatch({ text, term }: { text: string; term: string }) {
  const t = (term ?? "").trim();
  if (!t || t.length < 2) return <>{text}</>;

  const re = new RegExp(`(${escapeRegExp(t)})`, "ig");
  const parts = String(text).split(re);

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

function encId(s: string) {
  // safe-ish id: keep it stable and DOM-friendly
  return encodeURIComponent(String(s ?? "")).replace(/%/g, "_");
}

export function CatalogBrowserDialog({ triggerLabel = "Sfoglia", onSelect }: Props) {
  const [open, setOpen] = useState(false);

  // Ricerca dentro la finestra (NON filtra l'albero; apre e highlight)
  const [query, setQuery] = useState("");

  // tree data (lazy)
  const { fetchChildren, error: treeError } = useCatalogTree();

  // quick search (catalogo piatto) via RPC esistente
  const {
    items: searchItems,
    loading: searchLoading,
    error: searchError,
    search: searchCatalog,
    clear,
  } = useAnalyticsCatalog();

  // children cache: pathKey -> nodes
  const [childrenByPath, setChildrenByPath] = useState<Record<string, CatalogTreeNode[]>>({});
  const [loadingPath, setLoadingPath] = useState<string | null>(null);

  // Accordion open state
  const [openFasce, setOpenFasce] = useState<string[]>([]);
  const [openCategorie, setOpenCategorie] = useState<Record<string, string[]>>({});
  const [openFamiglie, setOpenFamiglie] = useState<Record<string, string[]>>({});
  const [openFascePrezzo, setOpenFascePrezzo] = useState<Record<string, string[]>>({});
  const [lastAutoOpenedKey, setLastAutoOpenedKey] = useState<string | null>(null);

  const scrollRef = useRef<HTMLDivElement>(null);
  const lastSearchTermRef = useRef<string>("");

  const resetTreeUI = () => {
    setOpenFasce([]);
    setOpenCategorie({});
    setOpenFamiglie({});
    setOpenFascePrezzo({});
    setLastAutoOpenedKey(null);

    setTimeout(() => {
      scrollRef.current?.scrollTo({ top: 0 });
    }, 0);
  };

  // quando apro dialog: carico fasce (root)
  useEffect(() => {
    if (!open) return;

    const loadRoot = async () => {
      const pathKey = `root:fasce`;
      if (childrenByPath[pathKey]) return;

      setLoadingPath(pathKey);
      const nodes = await fetchChildren({ level: "fascia", limit: 500 });
      setChildrenByPath((prev) => ({ ...prev, [pathKey]: nodes }));
      setLoadingPath(null);
    };

    loadRoot();
  }, [open, childrenByPath, fetchChildren]);

  // debounce search RPC
  useEffect(() => {
    const t = query.trim();
    if (!open) return;

    clear();

    if (t.length < 2) return;

    const timer = setTimeout(() => {
      searchCatalog(t);
    }, 250);

    return () => clearTimeout(timer);
  }, [query, open, searchCatalog, clear]);

  useEffect(() => {
    if (!open) return;

    const t = query.trim();

    // se l'utente cancella o scende sotto 2 char -> torna come all'inizio
    if (t.length < 2) {
      lastSearchTermRef.current = "";
      setLastAutoOpenedKey(null);
      resetTreeUI();
      return;
    }

    // se cambia il termine di ricerca (nuova ricerca) -> collassa e riparti
    if (lastSearchTermRef.current && lastSearchTermRef.current !== t) {
      setLastAutoOpenedKey(null);
      resetTreeUI();
    }
  }, [query, open]);

  // reset query quando chiudi dialog
  useEffect(() => {
    if (!open) {
      setQuery("");
    }
  }, [open]);

  const rootFasce = childrenByPath["root:fasce"] ?? [];

  const selectNode = (
    nodeType: CatalogNodeType,
    nodeKey: string,
    label: string,
    ctx?: { fascia?: string | null; categoria?: string | null; famiglia?: string | null; fascia_prezzo?: string | null },
  ) => {
    if (nodeType === "articolo") return;

    // Fascia prezzo NON è globale: in Analytics va sempre letta come filtro della famiglia.
    if (nodeType === "fascia_prezzo" && ctx?.famiglia) {
      onSelect({
        entity_type: "famiglia",
        entity_key: ctx.famiglia,
        label: ctx.famiglia,
        fascia: ctx.fascia ?? null,
        categoria: ctx.categoria ?? null,
        famiglia: ctx.famiglia ?? null,
        fascia_prezzo: nodeKey,
        fascia_prezzo_label: label,
      } as any);

      setOpen(false);
      return;
    }

    onSelect({
      entity_type: nodeType,
      entity_key: nodeKey,
      label,
      fascia: ctx?.fascia ?? null,
      categoria: ctx?.categoria ?? null,
      famiglia: ctx?.famiglia ?? null,
    } as any);

    setOpen(false);
  };

  const ensureChildren = async (args: {
    level: CatalogNodeType;
    fascia?: string | null;
    categoria?: string | null;
    famiglia?: string | null;
    fascia_prezzo?: string | null;
    pathKey: string;
    limit?: number;
  }) => {
    const { pathKey, level, fascia, categoria, famiglia, fascia_prezzo, limit } = args;
    if (childrenByPath[pathKey]) return;

    setLoadingPath(pathKey);
    const nodes = await fetchChildren({
      level,
      fascia: fascia ?? null,
      categoria: categoria ?? null,
      famiglia: famiglia ?? null,
      fascia_prezzo: fascia_prezzo ?? null,
      limit: limit ?? 500,
    });
    setChildrenByPath((prev) => ({ ...prev, [pathKey]: nodes }));
    setLoadingPath(null);
  };

  const openToHit = async (hit: CatalogItem) => {
    const fascia = (hit as any).fascia ?? null;
    const categoria = (hit as any).categoria ?? null;
    const famiglia = (hit as any).famiglia ?? null;
    const fp = (hit as any).fascia_prezzo ?? null;

    if (!fascia) return;

    // 1) apri fascia
    const fasciaAccKey = `fascia::${fascia}`;
    const nextOpenFasce = Array.from(new Set([...openFasce, fasciaAccKey]));
    setOpenFasce(nextOpenFasce);

    // 2) load categorie di fascia
    const catPathKey = `fascia:${fascia}::categorie`;
    await ensureChildren({ level: "categoria", fascia, pathKey: catPathKey, limit: 500 });

    if (!categoria) {
      // scroll al livello più profondo disponibile
      setTimeout(() => {
        const el = document.getElementById(`fas__${encId(fascia)}`);
        el?.scrollIntoView({ block: "center" });
      }, 50);
      return;
    }

    // 3) apri categoria
    const catAccKey = `categoria::${categoria}`;
    setOpenCategorie((prev) => {
      const cur = prev[catPathKey] ?? [];
      return { ...prev, [catPathKey]: Array.from(new Set([...cur, catAccKey])) };
    });

    // 4) load famiglie
    const famPathKey = `fascia:${fascia}::categoria:${categoria}::famiglie`;
    await ensureChildren({ level: "famiglia", fascia, categoria, pathKey: famPathKey, limit: 500 });

    if (!famiglia) {
      setTimeout(() => {
        const el = document.getElementById(`cat__${encId(categoria)}`);
        el?.scrollIntoView({ block: "center" });
      }, 50);
      return;
    }

    // 5) apri famiglia
    const famAccKey = `famiglia::${famiglia}`;
    setOpenFamiglie((prev) => {
      const cur = prev[famPathKey] ?? [];
      return { ...prev, [famPathKey]: Array.from(new Set([...cur, famAccKey])) };
    });

    // 6) load fasce prezzo
    const fpPathKey = `fascia:${fascia}::categoria:${categoria}::famiglia:${famiglia}::fasce_prezzo`;
    await ensureChildren({ level: "fascia_prezzo", fascia, categoria, famiglia, pathKey: fpPathKey, limit: 500 });

    if (!fp) {
      setTimeout(() => {
        const el = document.getElementById(`fam__${encId(famiglia)}`);
        el?.scrollIntoView({ block: "center" });
      }, 50);
      return;
    }

    // scroll: se ho fp, vado al suo header; altrimenti vado alla famiglia
    setTimeout(() => {
      if (fp) {
        const el = document.getElementById(`fp__${encId(fp)}`);
        el?.scrollIntoView({ block: "center" });
      } else if (famiglia) {
        const el = document.getElementById(`fam__${encId(famiglia)}`);
        el?.scrollIntoView({ block: "center" });
      }
    }, 120);
  };

  useEffect(() => {
    if (!open) return;
    const t = query.trim();
    lastSearchTermRef.current = t;
    if (t.length < 2) return;
    if (searchLoading) return;
    if (!searchItems || searchItems.length === 0) return;

    const best = [...searchItems].sort((a, b) => {
      const sa = typeof a.score === "number" ? a.score : -1;
      const sb = typeof b.score === "number" ? b.score : -1;
      return sb - sa;
    })[0];

    const key = `${best.entity_type}__${best.entity_key}__${(best as any).fascia ?? ""}__${(best as any).categoria ?? ""}__${
      (best as any).famiglia ?? ""
    }__${(best as any).fascia_prezzo ?? ""}`;

    if (key === lastAutoOpenedKey) return;

    setLastAutoOpenedKey(key);
    openToHit(best as any);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, query, searchLoading, searchItems, lastAutoOpenedKey]);

  return (
    <Dialog open={open} onOpenChange={(v) => setOpen(v)}>
      <DialogTrigger asChild>
        <Button variant="outline" className="h-10">
          {triggerLabel}
        </Button>
      </DialogTrigger>

      <DialogContent className="max-w-3xl p-0">
        {/* HEADER */}
        <DialogHeader className="px-4 py-3 border-b">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <div className="flex items-center gap-3">
                <DialogTitle className="text-base">Sfoglia catalogo (gerarchia)</DialogTitle>

                {/* Search inline chip */}
                <div className="flex items-center gap-2 rounded-md border bg-background px-2 h-8">
                  <Search className="w-4 h-4 text-muted-foreground" />
                  <Input
                    value={query}
                    onChange={(e) => setQuery(e.target.value)}
                    placeholder="Cerca…"
                    className="h-7 border-0 bg-transparent px-0 text-sm focus-visible:ring-0 focus-visible:ring-offset-0 w-[220px]"
                  />
                </div>

                {query.trim().length > 0 && (
                  <Button
                    variant="ghost"
                    size="sm"
                    className="h-8 px-2"
                    onClick={() => {
                      setQuery("");
                      clear(); // pulisce i risultati RPC
                      lastSearchTermRef.current = "";
                      resetTreeUI(); // collassa tutto
                    }}
                    aria-label="clear"
                  >
                    Pulisci
                  </Button>
                )}
              </div>

              <div className="text-xs text-muted-foreground mt-1">
                Espandi i livelli:{" "}
                <span className="font-medium">Fascia → Categoria → Famiglia → Fascia prezzo → Articoli</span>
                {query.trim().length > 0 && query.trim().length < 2 ? (
                  <span className="ml-2">(min 2 caratteri)</span>
                ) : null}
              </div>
            </div>
          </div>

          {treeError && <div className="text-xs text-destructive mt-2">{treeError}</div>}
          {searchError && <div className="text-xs text-destructive mt-1">{searchError}</div>}
        </DialogHeader>

        {/* BODY */}
        <div className="px-4 py-3">
          <Card className="p-2">
            <div ref={scrollRef} className="max-h-[66vh] overflow-auto pr-1">
              <Accordion
                type="multiple"
                value={openFasce}
                onValueChange={async (vals) => {
                  setOpenFasce(vals);

                  const newlyOpened = vals.filter((v) => !openFasce.includes(v));
                  for (const fasciaKey of newlyOpened) {
                    const fascia = fasciaKey.replace("fascia::", "");
                    const pathKey = `fascia:${fascia}::categorie`;

                    await ensureChildren({
                      level: "categoria",
                      fascia,
                      pathKey,
                      limit: 500,
                    });
                  }
                }}
                className="border rounded-md"
              >
                {sortNodesAlpha(rootFasce).map((fasciaNode) => {
                  const fascia = fasciaNode.node_key;
                  const fasciaAccKey = `fascia::${fascia}`;
                  const catPathKey = `fascia:${fascia}::categorie`;
                  const categorieRaw = childrenByPath[catPathKey] ?? [];
                  const categorie = sortNodesAlpha(categorieRaw);

                  return (
                    <AccordionItem key={fasciaAccKey} value={fasciaAccKey} className="px-2">
                      <AccordionTrigger className="py-2 text-sm pr-1">
                        <div id={`fas__${encId(fascia)}`} className="flex items-center justify-between w-full gap-3">
                          <div className="flex items-center gap-2 min-w-0">
                            <span className="font-medium truncate">
                              <HighlightMatch text={fasciaNode.label} term={query} />
                            </span>
                            <span className="text-[11px] text-muted-foreground shrink-0">
                              ({fasciaNode.extra?.count ?? categorie.length ?? 0})
                            </span>
                          </div>

                          <div className="flex items-center gap-3 shrink-0 pr-6">
                            <Button
                              variant="ghost"
                              size="sm"
                              className="h-7 px-2"
                              onClick={(e) => {
                                e.preventDefault();
                                e.stopPropagation();
                                selectNode("fascia", fasciaNode.node_key, fasciaNode.label);
                              }}
                            >
                              Seleziona <ChevronRight className="w-4 h-4 ml-1" />
                            </Button>
                          </div>
                        </div>
                      </AccordionTrigger>

                      <AccordionContent className="pb-2">
                        {loadingPath === catPathKey ? (
                          <div className="text-sm text-muted-foreground px-2 py-2">Carico categorie…</div>
                        ) : categorie.length === 0 ? (
                          <div className="text-sm text-muted-foreground px-2 py-2">Nessuna categoria.</div>
                        ) : (
                          <Accordion
                            type="multiple"
                            value={openCategorie[catPathKey] ?? []}
                            onValueChange={async (vals) => {
                              setOpenCategorie((prev) => ({ ...prev, [catPathKey]: vals }));

                              const prevVals = openCategorie[catPathKey] ?? [];
                              const newlyOpened = vals.filter((v) => !prevVals.includes(v));

                              for (const catAccKey of newlyOpened) {
                                const categoria = catAccKey.replace("categoria::", "");
                                const famPathKey = `fascia:${fascia}::categoria:${categoria}::famiglie`;

                                await ensureChildren({
                                  level: "famiglia",
                                  fascia,
                                  categoria,
                                  pathKey: famPathKey,
                                  limit: 500,
                                });
                              }
                            }}
                            className="border rounded-md mx-2"
                          >
                            {categorie.map((catNode) => {
                              const categoria = catNode.node_key;
                              const catAccKey = `categoria::${categoria}`;
                              const famPathKey = `fascia:${fascia}::categoria:${categoria}::famiglie`;
                              const famiglieRaw = childrenByPath[famPathKey] ?? [];
                              const famiglie = sortNodesAlpha(famiglieRaw);

                              return (
                                <AccordionItem key={catAccKey} value={catAccKey} className="px-2">
                                  <AccordionTrigger className="py-2 text-sm pr-1">
                                    <div
                                      id={`cat__${encId(categoria)}`}
                                      className="flex items-center justify-between w-full gap-3"
                                    >
                                      <div className="flex items-center gap-2 min-w-0">
                                        <span className="font-medium truncate">
                                          <HighlightMatch text={catNode.label} term={query} />
                                        </span>
                                        <span className="text-[11px] text-muted-foreground shrink-0">
                                          ({catNode.extra?.count ?? famiglie.length ?? 0})
                                        </span>
                                      </div>

                                      <div className="flex items-center gap-3 shrink-0 pr-6">
                                        <Button
                                          variant="ghost"
                                          size="sm"
                                          className="h-7 px-2"
                                          onClick={(e) => {
                                            e.preventDefault();
                                            e.stopPropagation();
                                            selectNode("categoria", catNode.node_key, catNode.label);
                                          }}
                                        >
                                          Seleziona <ChevronRight className="w-4 h-4 ml-1" />
                                        </Button>
                                      </div>
                                    </div>
                                  </AccordionTrigger>

                                  <AccordionContent className="pb-2">
                                    {loadingPath === famPathKey ? (
                                      <div className="text-sm text-muted-foreground px-2 py-2">Carico famiglie…</div>
                                    ) : famiglie.length === 0 ? (
                                      <div className="text-sm text-muted-foreground px-2 py-2">Nessuna famiglia.</div>
                                    ) : (
                                      <Accordion
                                        type="multiple"
                                        value={openFamiglie[famPathKey] ?? []}
                                        onValueChange={async (vals) => {
                                          setOpenFamiglie((prev) => ({ ...prev, [famPathKey]: vals }));

                                          const prevVals = openFamiglie[famPathKey] ?? [];
                                          const newlyOpened = vals.filter((v) => !prevVals.includes(v));

                                          for (const famAccKey of newlyOpened) {
                                            const famiglia = famAccKey.replace("famiglia::", "");
                                            const fpPathKey = `fascia:${fascia}::categoria:${categoria}::famiglia:${famiglia}::fasce_prezzo`;

                                            await ensureChildren({
                                              level: "fascia_prezzo",
                                              fascia,
                                              categoria,
                                              famiglia,
                                              pathKey: fpPathKey,
                                              limit: 500,
                                            });
                                          }
                                        }}
                                        className="border rounded-md mx-2"
                                      >
                                        {famiglie.map((famNode) => {
                                          const famiglia = famNode.node_key;
                                          const famAccKey = `famiglia::${famiglia}`;
                                          const fpPathKey = `fascia:${fascia}::categoria:${categoria}::famiglia:${famiglia}::fasce_prezzo`;
                                          const fascePrezzoRaw = childrenByPath[fpPathKey] ?? [];
                                          const fascePrezzo = sortFascePrezzo(fascePrezzoRaw);

                                          return (
                                            <AccordionItem key={famAccKey} value={famAccKey} className="px-2">
                                              <AccordionTrigger className="py-2 text-sm pr-1">
                                                <div
                                                  id={`fam__${encId(famiglia)}`}
                                                  className="flex items-center justify-between w-full gap-3"
                                                >
                                                  <div className="flex items-center gap-2 min-w-0">
                                                    <span className="font-medium truncate">
                                                      <HighlightMatch text={famNode.label} term={query} />
                                                    </span>
                                                    <span className="text-[11px] text-muted-foreground shrink-0">
                                                      ({famNode.extra?.count ?? fascePrezzo.length ?? 0})
                                                    </span>
                                                  </div>

                                                  <div className="flex items-center gap-3 shrink-0 pr-6">
                                                    <Button
                                                      variant="ghost"
                                                      size="sm"
                                                      className="h-7 px-2"
                                                      onClick={(e) => {
                                                        e.preventDefault();
                                                        e.stopPropagation();
                                                        selectNode("famiglia", famNode.node_key, famNode.label);
                                                      }}
                                                    >
                                                      Seleziona <ChevronRight className="w-4 h-4 ml-1" />
                                                    </Button>
                                                  </div>
                                                </div>
                                              </AccordionTrigger>

                                              <AccordionContent className="pb-2">
                                                {loadingPath === fpPathKey ? (
                                                  <div className="text-sm text-muted-foreground px-2 py-2">
                                                    Carico fasce prezzo…
                                                  </div>
                                                ) : fascePrezzo.length === 0 ? (
                                                  <div className="text-sm text-muted-foreground px-2 py-2">
                                                    Nessuna fascia prezzo.
                                                  </div>
                                                ) : (
                                                  <Accordion
                                                    type="multiple"
                                                    value={openFascePrezzo[fpPathKey] ?? []}
                                                    onValueChange={async (vals) => {
                                                      setOpenFascePrezzo((prev) => ({ ...prev, [fpPathKey]: vals }));

                                                      const prevVals = openFascePrezzo[fpPathKey] ?? [];
                                                      const newlyOpened = vals.filter((v) => !prevVals.includes(v));

                                                      for (const fpAccKey of newlyOpened) {
                                                        const fascia_prezzo = fpAccKey.replace("fascia_prezzo::", "");
                                                        const artPathKey = `fascia:${fascia}::categoria:${categoria}::famiglia:${famiglia}::fp:${fascia_prezzo}::articoli`;

                                                        await ensureChildren({
                                                          level: "articolo",
                                                          fascia,
                                                          categoria,
                                                          famiglia,
                                                          fascia_prezzo,
                                                          pathKey: artPathKey,
                                                          limit: 300,
                                                        });
                                                      }
                                                    }}
                                                    className="border rounded-md mx-2"
                                                  >
                                                    {fascePrezzo.map((fpNode) => {
                                                      const fp = fpNode.node_key;
                                                      const fpAccKey = `fascia_prezzo::${fp}`;
                                                      const artPathKey = `fascia:${fascia}::categoria:${categoria}::famiglia:${famiglia}::fp:${fp}::articoli`;
                                                      const articoliRaw = childrenByPath[artPathKey] ?? [];
                                                      const articoli = sortArticoli(articoliRaw);

                                                      return (
                                                        <AccordionItem key={fpAccKey} value={fpAccKey} className="px-2">
                                                          <AccordionTrigger className="py-2 text-sm pr-1">
                                                            <div
                                                              id={`fp__${encId(fp)}`}
                                                              className="flex items-center justify-between w-full gap-3"
                                                            >
                                                              <div className="flex items-center gap-2 min-w-0">
                                                                <span className="font-medium truncate">
                                                                  <HighlightMatch text={fpNode.label} term={query} />
                                                                </span>
                                                                <span className="text-[11px] text-muted-foreground shrink-0">
                                                                  ({fpNode.extra?.count ?? articoli.length ?? 0})
                                                                </span>
                                                              </div>

                                                              <div className="flex items-center gap-3 shrink-0 pr-6">
                                                                <Button
                                                                  variant="ghost"
                                                                  size="sm"
                                                                  className="h-7 px-2"
                                                                  onClick={(e) => {
                                                                    e.preventDefault();
                                                                    e.stopPropagation();
                                                                    selectNode(
                                                                      "fascia_prezzo",
                                                                      fpNode.node_key,
                                                                      fpNode.label,
                                                                      { fascia, categoria, famiglia, fascia_prezzo: fpNode.node_key },
                                                                    );
                                                                  }}
                                                                >
                                                                  Seleziona <ChevronRight className="w-4 h-4 ml-1" />
                                                                </Button>
                                                              </div>
                                                            </div>
                                                          </AccordionTrigger>

                                                          <AccordionContent className="pb-2">
                                                            {loadingPath === artPathKey ? (
                                                              <div className="text-sm text-muted-foreground px-2 py-2">
                                                                Carico articoli…
                                                              </div>
                                                            ) : articoli.length === 0 ? (
                                                              <div className="text-sm text-muted-foreground px-2 py-2">
                                                                Nessun articolo.
                                                              </div>
                                                            ) : (
                                                              <div className="mx-2 border rounded-md overflow-hidden">
                                                                <div className="max-h-56 overflow-auto">
                                                                  <ul className="divide-y">
                                                                    {articoli.map((a) => (
                                                                      <li
                                                                        key={`${a.node_type}::${a.node_key}`}
                                                                        className="px-3 py-2"
                                                                      >
                                                                        <div className="flex items-start justify-between gap-3">
                                                                          <div className="min-w-0">
                                                                            <div className="text-sm font-medium truncate">
                                                                              <HighlightMatch
                                                                                text={a.label}
                                                                                term={query}
                                                                              />
                                                                            </div>
                                                                            <div className="text-xs text-muted-foreground">
                                                                              {a.extra?.pot_size
                                                                                ? `Pot: ${a.extra.pot_size}`
                                                                                : "Pot: -"}
                                                                            </div>
                                                                          </div>
                                                                          <div className="text-sm font-semibold shrink-0">
                                                                            {fmtPriceEUR(a.extra?.prezzo_iva_inclusa)}
                                                                          </div>
                                                                        </div>
                                                                      </li>
                                                                    ))}
                                                                  </ul>
                                                                </div>

                                                                <div className="px-3 py-2 text-[11px] text-muted-foreground bg-muted/30">
                                                                  Articoli non selezionabili (per ora).
                                                                </div>
                                                              </div>
                                                            )}
                                                          </AccordionContent>
                                                        </AccordionItem>
                                                      );
                                                    })}
                                                  </Accordion>
                                                )}
                                              </AccordionContent>
                                            </AccordionItem>
                                          );
                                        })}
                                      </Accordion>
                                    )}
                                  </AccordionContent>
                                </AccordionItem>
                              );
                            })}
                          </Accordion>
                        )}
                      </AccordionContent>
                    </AccordionItem>
                  );
                })}
              </Accordion>

              {loadingPath === "root:fasce" && (
                <div className="text-sm text-muted-foreground px-2 py-2">Carico fasce…</div>
              )}
              {!loadingPath && rootFasce.length === 0 && (
                <div className="text-sm text-muted-foreground px-2 py-2">Nessuna fascia trovata.</div>
              )}
            </div>
          </Card>
        </div>
      </DialogContent>
    </Dialog>
  );
}

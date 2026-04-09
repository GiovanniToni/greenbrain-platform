// src/pages/Reorders.tsx
import { useMemo, useState, useEffect } from "react";
import { Bot, Send, Download, Mail, MessageSquare, AlertTriangle } from "lucide-react";

import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";

import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";

import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";

import { useOrderSuggestions, OrderSuggestion } from "@/hooks/useOrderSuggestions";

// ----------------------------
// Helpers
// ----------------------------

// Ordine fisso fasce prezzo (non alfabetico)
const PRICE_BAND_ORDER: Record<string, number> = {
  "0 - 2,99€": 1,
  "3 - 4,99€": 2,
  "5 - 9,99€": 3,
  "10 - 14,99€": 4,
  "15 - 19,99€": 5,
  "20 - 24,99€": 6,
  "25 - 29,99€": 7,
  "30 - 39,99€": 8,
  "40 - 49,99€": 9,
  "50 - 59,99€": 10,
  "60 - 69,99€": 11,
  "70 - 99,99€": 12,
  "100 - 149,99€": 13,
  "150 - 199,99€": 14,
  "200€ - >": 15,
};

function priceBandRank(label: string | null | undefined) {
  if (!label) return 999;
  const trimmed = label.trim();
  return PRICE_BAND_ORDER[trimmed] ?? 999;
}

function norm(s: string | null | undefined) {
  return (s ?? "").toLowerCase().trim();
}

function safeKey(value: string) {
  return value
    .toLowerCase()
    .trim()
    .replace(/\s+/g, "_")
    .replace(/[^a-z0-9_]/g, "");
}

function n(v: number | null | undefined) {
  return typeof v === "number" && Number.isFinite(v) ? v : 0;
}

function fmtQty(v: number | null | undefined) {
  const num = n(v);
  // restituiamo una STRINGA con 2 decimali per la UI
  return num.toFixed(2);
}

function fmtInt(v: number | null | undefined) {
  return Math.round(n(v));
}

function hasRisk(items: OrderSuggestion[]) {
  return items.some((x) => !!x.rischio_stockout_prima_di_arrivo);
}

type GroupedTree = Record<
  string, // fascia_corretta
  Record<
    string, // categoria_corretta
    Record<string, OrderSuggestion[]> // famiglia
  >
>;

function buildTree(list: OrderSuggestion[]): GroupedTree {
  const tree: GroupedTree = {};

  for (const row of list) {
    const fascia = row.fascia_corretta?.trim() || "SENZA FASCIA";
    const categoria = row.categoria_corretta?.trim() || "SENZA CATEGORIA";
    const famiglia = row.famiglia?.trim() || "SENZA FAMIGLIA";

    if (!tree[fascia]) tree[fascia] = {};
    if (!tree[fascia][categoria]) tree[fascia][categoria] = {};
    if (!tree[fascia][categoria][famiglia]) tree[fascia][categoria][famiglia] = [];

    tree[fascia][categoria][famiglia].push(row);
  }

  // ordina le righe dentro ogni famiglia per fascia prezzo (ordine fisso)
  for (const fascia of Object.keys(tree)) {
    for (const categoria of Object.keys(tree[fascia])) {
      for (const famiglia of Object.keys(tree[fascia][categoria])) {
        tree[fascia][categoria][famiglia].sort((a, b) => {
          const ra = priceBandRank(a.fascia_prezzo_iva_inc);
          const rb = priceBandRank(b.fascia_prezzo_iva_inc);
          if (ra !== rb) return ra - rb;
          return (a.fascia_prezzo_iva_inc ?? "").localeCompare(b.fascia_prezzo_iva_inc ?? "", "it");
        });
      }
    }
  }

  return tree;
}

function downloadBlob(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

// Escape XML entities
function xmlEscape(s: unknown) {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

// SpreadsheetML (Excel 2003 XML) builder
function buildExcelXml(args: {
  title?: string;
  headers: string[];
  rows: Array<{
    // values must match headers ordering
    cells: Array<{ type: "String" | "Number"; value: string | number; styleId?: string }>;
  }>;
}) {
  const { title = "Riordino", headers, rows } = args;

  // styles:
  // sHeader: header grey bold
  // sGroup: group row grey bold
  // sRisk: risk row yellow
  // sNum2: number with 2 decimals
  // sInt: integer
  // sText: text normal
  // sTextIndentN: text with indent (we generate per indent level)
  // Note: Excel XML supports ss:Indent on Alignment.

  const indentStyles = [0, 1, 2, 3, 4, 5].map(
    (i) => `
    <Style ss:ID="sTextIndent${i}">
      <Alignment ss:Vertical="Center" ss:Indent="${i}"/>
      <Font ss:Size="11"/>
    </Style>
    <Style ss:ID="sGroupIndent${i}">
      <Alignment ss:Vertical="Center" ss:Indent="${i}"/>
      <Font ss:Bold="1" ss:Size="11"/>
      <Interior ss:Color="#F7F7F7" ss:Pattern="Solid"/>
    </Style>
    <Style ss:ID="sRiskIndent${i}">
      <Alignment ss:Vertical="Center" ss:Indent="${i}"/>
      <Font ss:Bold="1" ss:Size="11"/>
      <Interior ss:Color="#FFF4CC" ss:Pattern="Solid"/>
    </Style>
  `,
  );

  const xml = `<?xml version="1.0"?>
<?mso-application progid="Excel.Sheet"?>
<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"
 xmlns:o="urn:schemas-microsoft-com:office:office"
 xmlns:x="urn:schemas-microsoft-com:office:excel"
 xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet"
 xmlns:html="http://www.w3.org/TR/REC-html40">
  <DocumentProperties xmlns="urn:schemas-microsoft-com:office:office">
    <Title>${xmlEscape(title)}</Title>
  </DocumentProperties>

  <Styles>
    <Style ss:ID="Default" ss:Name="Normal">
      <Alignment ss:Vertical="Center"/>
      <Font ss:Size="11"/>
    </Style>

    <Style ss:ID="sHeader">
      <Alignment ss:Vertical="Center"/>
      <Font ss:Bold="1" ss:Size="12"/>
      <Interior ss:Color="#EFEFEF" ss:Pattern="Solid"/>
      <Borders>
        <Border ss:Position="Bottom" ss:LineStyle="Continuous" ss:Weight="1" ss:Color="#D0D0D0"/>
        <Border ss:Position="Top" ss:LineStyle="Continuous" ss:Weight="1" ss:Color="#D0D0D0"/>
        <Border ss:Position="Left" ss:LineStyle="Continuous" ss:Weight="1" ss:Color="#D0D0D0"/>
        <Border ss:Position="Right" ss:LineStyle="Continuous" ss:Weight="1" ss:Color="#D0D0D0"/>
      </Borders>
    </Style>

    <Style ss:ID="sNum2">
      <Alignment ss:Vertical="Center" ss:Horizontal="Right"/>
      <NumberFormat ss:Format="#,##0.00"/>
    </Style>

    <Style ss:ID="sInt">
      <Alignment ss:Vertical="Center" ss:Horizontal="Right"/>
      <NumberFormat ss:Format="#,##0"/>
    </Style>

    <Style ss:ID="sText">
      <Alignment ss:Vertical="Center"/>
      <Font ss:Size="11"/>
    </Style>

    ${indentStyles.join("\n")}
  </Styles>

  <Worksheet ss:Name="${xmlEscape(title)}">
    <Table>
      <Row ss:AutoFitHeight="0" ss:Height="20">
        ${headers
          .map((h) => `<Cell ss:StyleID="sHeader"><Data ss:Type="String">${xmlEscape(h)}</Data></Cell>`)
          .join("")}
      </Row>

      ${rows
        .map((r) => {
          return `<Row>
            ${r.cells
              .map((c) => {
                const style = c.styleId ? ` ss:StyleID="${c.styleId}"` : "";
                const type = c.type;
                const value = type === "Number" ? String(c.value ?? 0) : xmlEscape(c.value);
                return `<Cell${style}><Data ss:Type="${type}">${value}</Data></Cell>`;
              })
              .join("")}
          </Row>`;
        })
        .join("\n")}
    </Table>

    <WorksheetOptions xmlns="urn:schemas-microsoft-com:office:excel">
      <FreezePanes/>
      <FrozenNoSplit/>
      <SplitHorizontal>1</SplitHorizontal>
      <TopRowBottomPane>1</TopRowBottomPane>
      <ActivePane>2</ActivePane>
      <Panes>
        <Pane>
          <Number>2</Number>
        </Pane>
      </Panes>
    </WorksheetOptions>
  </Worksheet>
</Workbook>`;

  return xml;
}

// ----------------------------
// Assistant (unchanged)
// ----------------------------
export function ReorderAssistant() {
  const [prompt, setPrompt] = useState("");

  const mockResponse = `Basandomi sui dati attuali, consiglio di dare priorità al riordino di prodotti con rischio stock-out. 
  
Verifica le quantità suggerite e considera la stagionalità corrente per ottimizzare gli ordini ai fornitori.`;

  return (
    <Card className="p-6 animate-fade-in">
      <div className="flex items-center gap-3 mb-4">
        <div className="w-10 h-10 bg-primary/10 rounded-lg flex items-center justify-center">
          <Bot className="w-5 h-5 text-primary" />
        </div>
        <div>
          <h3 className="font-semibold">Assistente di Riordino</h3>
          <p className="text-sm text-muted-foreground">Suggerimenti AI per ottimizzare gli ordini</p>
        </div>
      </div>

      <div className="bg-muted/50 rounded-lg p-4 mb-4">
        <p className="text-sm whitespace-pre-line">{mockResponse}</p>
      </div>

      <div className="flex gap-2">
        <Textarea
          placeholder="Chiedi all'assistente... es. 'Quali piante devo riordinare per San Valentino?'"
          value={prompt}
          onChange={(e) => setPrompt(e.target.value)}
          className="min-h-[60px]"
        />
        <Button size="icon" className="shrink-0" type="button">
          <Send className="w-4 h-4" />
        </Button>
      </div>
    </Card>
  );
}

// ----------------------------
// Filters
// ----------------------------
interface ReorderFiltersProps {
  searchTerm: string;
  onSearchChange: (value: string) => void;
  selectedCategory: string;
  onCategoryChange: (value: string) => void;
  categories: string[];
  showOnlyRisk: boolean;
  onShowOnlyRiskChange: (value: boolean) => void;
}

export function ReorderFilters({
  searchTerm,
  onSearchChange,
  selectedCategory,
  onCategoryChange,
  categories,
  showOnlyRisk,
  onShowOnlyRiskChange,
}: ReorderFiltersProps) {
  return (
    <Card className="p-4 animate-fade-in">
      <div className="flex flex-wrap gap-4 items-center">
        <Input
          placeholder="Cerca per famiglia..."
          className="w-64"
          value={searchTerm}
          onChange={(e) => onSearchChange(e.target.value)}
        />
        <Select value={selectedCategory} onValueChange={onCategoryChange}>
          <SelectTrigger className="w-64">
            <SelectValue placeholder="Tutte le categorie" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Tutte le categorie</SelectItem>
            {categories.map((cat) => (
              <SelectItem key={cat} value={cat}>
                {cat}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <label className="flex items-center gap-2 text-sm cursor-pointer select-none">
          <input
            type="checkbox"
            checked={showOnlyRisk}
            onChange={(e) => onShowOnlyRiskChange(e.target.checked)}
            className="rounded border-input"
          />
          <span>Solo rischio stock-out</span>
        </label>
      </div>
    </Card>
  );
}

// ----------------------------
// FIXED COLUMNS TABLE ✅ + Excel export (no libs)
// ----------------------------
interface ReorderTableProps {
  data: OrderSuggestion[];
  loading: boolean;
  error: string | null;
}

type RowKind = "fascia" | "categoria" | "famiglia" | "item";

type FlatRow = {
  kind: RowKind;
  key: string;

  fascia?: string;
  categoria?: string;
  famiglia?: string;

  label: string;
  level: number;
  expandable: boolean;
  expanded?: boolean;

  fascia_prezzo_iva_inc?: string | null;
  pot_sizes_text?: string | null;

  qty_giacenza: number;
  demand_lead: number;
  demand_cycle: number;
  qty_da_ordinare: number;

  risk: boolean;
};

function aggItems(items: OrderSuggestion[]) {
  const qty_giacenza = items.reduce((a, r) => a + n(r.qty_giacenza), 0);
  const demand_lead = items.reduce((a, r) => a + n(r.demand_lead), 0);
  const demand_cycle = items.reduce((a, r) => a + n(r.demand_cycle), 0);
  const qty_da_ordinare = items.reduce((a, r) => a + n(r.qty_da_ordinare), 0);
  const risk = hasRisk(items);
  return { qty_giacenza, demand_lead, demand_cycle, qty_da_ordinare, risk };
}

export function ReorderTable({ data, loading, error }: ReorderTableProps) {
  const tree = useMemo(() => (data.length ? buildTree(data) : ({} as GroupedTree)), [data]);
  const sortedFasce = useMemo(() => Object.keys(tree).sort((a, b) => a.localeCompare(b, "it")), [tree]);

  const [openFasce, setOpenFasce] = useState<Set<string>>(() => new Set());
  const [openCats, setOpenCats] = useState<Set<string>>(() => new Set());
  const [openFams, setOpenFams] = useState<Set<string>>(() => new Set());

  useEffect(() => {
    setOpenFasce(new Set());
    setOpenCats(new Set());
    setOpenFams(new Set());
  }, [data]);

  const flatRows: FlatRow[] = useMemo(() => {
    const out: FlatRow[] = [];

    for (const fascia of sortedFasce) {
      const fasciaNode = tree[fascia];
      const fasciaKey = `fascia:${fascia}`;
      const fasciaExpanded = openFasce.has(fasciaKey);

      const fasciaItems: OrderSuggestion[] = [];
      for (const categoria of Object.keys(fasciaNode)) {
        for (const famiglia of Object.keys(fasciaNode[categoria])) {
          fasciaItems.push(...fasciaNode[categoria][famiglia]);
        }
      }
      const fasciaAgg = aggItems(fasciaItems);

      out.push({
        kind: "fascia",
        key: fasciaKey,
        fascia,
        label: fascia,
        level: 0,
        expandable: true,
        expanded: fasciaExpanded,
        fascia_prezzo_iva_inc: "—",
        pot_sizes_text: "—",
        ...fasciaAgg,
      });

      if (!fasciaExpanded) continue;

      const sortedCats = Object.keys(fasciaNode).sort((a, b) => a.localeCompare(b, "it"));
      for (const categoria of sortedCats) {
        const catNode = fasciaNode[categoria];
        const catKey = `cat:${fascia}::${categoria}`;
        const catExpanded = openCats.has(catKey);

        const catItems: OrderSuggestion[] = [];
        for (const famiglia of Object.keys(catNode)) catItems.push(...catNode[famiglia]);
        const catAgg = aggItems(catItems);

        out.push({
          kind: "categoria",
          key: catKey,
          fascia,
          categoria,
          label: categoria,
          level: 1,
          expandable: true,
          expanded: catExpanded,
          fascia_prezzo_iva_inc: "—",
          pot_sizes_text: "—",
          ...catAgg,
        });

        if (!catExpanded) continue;

        const sortedFams = Object.keys(catNode).sort((a, b) => a.localeCompare(b, "it"));
        for (const famiglia of sortedFams) {
          const items = catNode[famiglia];
          const famKey = `fam:${fascia}::${categoria}::${famiglia}`;
          const famExpanded = openFams.has(famKey);

          const famAgg = aggItems(items);

          out.push({
            kind: "famiglia",
            key: famKey,
            fascia,
            categoria,
            famiglia,
            label: famiglia,
            level: 2,
            expandable: true,
            expanded: famExpanded,
            fascia_prezzo_iva_inc: "—",
            pot_sizes_text: "—",
            ...famAgg,
          });

          if (!famExpanded) continue;

          for (let i = 0; i < items.length; i++) {
            const r = items[i];
            out.push({
              kind: "item",
              key: `${famKey}::item:${i}`,
              fascia,
              categoria,
              famiglia,
              label: r.fascia_prezzo_iva_inc ?? "-",
              level: 3,
              expandable: false,
              fascia_prezzo_iva_inc: r.fascia_prezzo_iva_inc,
              pot_sizes_text: r.pot_sizes_text,
              qty_giacenza: n(r.qty_giacenza),
              demand_lead: n(r.demand_lead),
              demand_cycle: n(r.demand_cycle),
              qty_da_ordinare: n(r.qty_da_ordinare),
              risk: !!r.rischio_stockout_prima_di_arrivo,
            });
          }
        }
      }
    }

    return out;
  }, [tree, sortedFasce, openFasce, openCats, openFams]);

  const expandAll = () => {
    const f = new Set<string>();
    const c = new Set<string>();
    const m = new Set<string>();

    for (const fascia of sortedFasce) {
      f.add(`fascia:${fascia}`);
      const fasciaNode = tree[fascia];
      for (const categoria of Object.keys(fasciaNode)) {
        c.add(`cat:${fascia}::${categoria}`);
        for (const famiglia of Object.keys(fasciaNode[categoria])) {
          m.add(`fam:${fascia}::${categoria}::${famiglia}`);
        }
      }
    }
    setOpenFasce(f);
    setOpenCats(c);
    setOpenFams(m);
  };

  const collapseAllToFasce = () => {
    setOpenFasce(new Set());
    setOpenCats(new Set());
    setOpenFams(new Set());
  };

  const toggle = (row: FlatRow) => {
    if (!row.expandable) return;

    if (row.kind === "fascia") {
      const k = row.key;
      setOpenFasce((prev) => {
        const next = new Set(prev);
        next.has(k) ? next.delete(k) : next.add(k);
        return next;
      });
      return;
    }

    if (row.kind === "categoria") {
      const k = row.key;
      setOpenCats((prev) => {
        const next = new Set(prev);
        next.has(k) ? next.delete(k) : next.add(k);
        return next;
      });
      return;
    }

    if (row.kind === "famiglia") {
      const k = row.key;
      setOpenFams((prev) => {
        const next = new Set(prev);
        next.has(k) ? next.delete(k) : next.add(k);
        return next;
      });
      return;
    }
  };

  const buildFullExportRows = () => {
    // Flat completo: una riga per ogni item (fascia prezzo + pot size)
    const all: Array<{
      fascia: string;
      categoria: string;
      famiglia: string;
      fascia_prezzo_iva_inc: string;
      pot_sizes_text: string;
      qty_giacenza: number;
      demand_lead: number;
      demand_cycle: number;
      qty_da_ordinare: number;
      rischio: boolean;
    }> = [];

    // Parto direttamente da `data` così non dipendo da open/closed.
    // Ordine: fascia -> categoria -> famiglia -> fascia prezzo (ordine fisso)
    const sorted = data.slice().sort((a, b) => {
      const fa = (a.fascia_corretta ?? "").localeCompare(b.fascia_corretta ?? "", "it");
      if (fa !== 0) return fa;

      const ca = (a.categoria_corretta ?? "").localeCompare(b.categoria_corretta ?? "", "it");
      if (ca !== 0) return ca;

      const fam = (a.famiglia ?? "").localeCompare(b.famiglia ?? "", "it");
      if (fam !== 0) return fam;

      const ra = priceBandRank(a.fascia_prezzo_iva_inc);
      const rb = priceBandRank(b.fascia_prezzo_iva_inc);
      if (ra !== rb) return ra - rb;

      return (a.pot_sizes_text ?? "").localeCompare(b.pot_sizes_text ?? "", "it");
    });

    for (const r of sorted) {
      all.push({
        fascia: r.fascia_corretta?.trim() || "SENZA FASCIA",
        categoria: r.categoria_corretta?.trim() || "SENZA CATEGORIA",
        famiglia: r.famiglia?.trim() || "SENZA FAMIGLIA",
        fascia_prezzo_iva_inc: r.fascia_prezzo_iva_inc ?? "-",
        pot_sizes_text: r.pot_sizes_text ?? "-",
        qty_giacenza: n(r.qty_giacenza),
        demand_lead: n(r.demand_lead),
        demand_cycle: n(r.demand_cycle),
        qty_da_ordinare: n(r.qty_da_ordinare),
        rischio: !!r.rischio_stockout_prima_di_arrivo,
      });
    }

    return all;
  };

  const exportExcelLikeUI = () => {
    // ✅ esporta SEMPRE TUTTI I DATI (tabella completa), indipendente da espansione/contrazione
    const headers = [
      "Fascia",
      "Categoria",
      "Famiglia",
      "Fascia Prezzo",
      "Pot size",
      "Giacenza",
      "Previsione a 3 giorni",
      "Previsione tot dal 4 al 10 giorno",
      "Quantità da ordinare",
      "Rischio",
    ];

    const full = buildFullExportRows();

    const rows = full.map((r) => {
      const riskStyle = r.rischio ? "sRiskIndent0" : "sTextIndent0";

      return {
        cells: [
          { type: "String" as const, value: r.fascia, styleId: riskStyle },
          { type: "String" as const, value: r.categoria, styleId: riskStyle },
          { type: "String" as const, value: r.famiglia, styleId: riskStyle },
          { type: "String" as const, value: r.fascia_prezzo_iva_inc, styleId: riskStyle },
          { type: "String" as const, value: r.pot_sizes_text, styleId: riskStyle },

          // numeri con 2 decimali in Excel: usa sNum2
          { type: "Number" as const, value: r.qty_giacenza, styleId: "sNum2" },
          { type: "Number" as const, value: r.demand_lead, styleId: "sNum2" },
          { type: "Number" as const, value: r.demand_cycle, styleId: "sNum2" },

          // quantità da ordinare intera
          { type: "Number" as const, value: r.qty_da_ordinare, styleId: "sInt" },

          { type: "String" as const, value: r.rischio ? "SI" : "", styleId: riskStyle },
        ],
      };
    });

    const date = new Date().toISOString().slice(0, 10);
    const xml = buildExcelXml({
      title: "Riordino",
      headers,
      rows,
    });

    const blob = new Blob([xml], { type: "application/vnd.ms-excel;charset=utf-8" });
    downloadBlob(blob, `riordino_${date}.xls`);
  };

  // Loading / Error / Empty
  if (loading) {
    return (
      <Card className="animate-fade-in p-6">
        <div className="space-y-4">
          <Skeleton className="h-8 w-48" />
          <Skeleton className="h-14 w-full" />
          <Skeleton className="h-14 w-full" />
          <Skeleton className="h-14 w-full" />
          <Skeleton className="h-14 w-full" />
        </div>
      </Card>
    );
  }

  if (error) {
    return (
      <Card className="animate-fade-in p-6">
        <div className="flex items-center gap-3 text-destructive">
          <AlertTriangle className="w-5 h-5" />
          <div>
            <p className="font-medium">Errore nel caricamento dei dati</p>
            <p className="text-sm text-muted-foreground">{error}</p>
          </div>
        </div>
      </Card>
    );
  }

  if (data.length === 0) {
    return (
      <Card className="animate-fade-in p-6">
        <div className="text-center py-8">
          <p className="text-muted-foreground">Nessun suggerimento di riordino trovato.</p>
        </div>
      </Card>
    );
  }

  return (
    <TooltipProvider>
      <Card className="animate-fade-in">
        {/* Header actions */}
        <div className="p-4 border-b border-border flex flex-col gap-3 sm:flex-row sm:justify-between sm:items-center">
          <div className="flex items-center gap-3">
            <h3 className="font-semibold">Lista Riordino</h3>
            <Badge variant="secondary">{data.length} righe</Badge>
            <Badge variant="outline">{data.filter((x) => x.rischio_stockout_prima_di_arrivo).length} a rischio</Badge>
          </div>

          <div className="flex flex-wrap gap-2">
            <Button variant="outline" size="sm" type="button" onClick={expandAll}>
              Espandi tutto
            </Button>
            <Button variant="outline" size="sm" type="button" onClick={collapseAllToFasce}>
              Comprimi a fasce
            </Button>

            <Button variant="outline" size="sm" type="button" onClick={exportExcelLikeUI}>
              <Download className="w-4 h-4 mr-2" />
              Excel (XLS)
            </Button>

            <Tooltip>
              <TooltipTrigger asChild>
                <Button variant="outline" size="sm" disabled type="button">
                  <Mail className="w-4 h-4 mr-2" />
                  Email
                </Button>
              </TooltipTrigger>
              <TooltipContent>In arrivo</TooltipContent>
            </Tooltip>

            <Tooltip>
              <TooltipTrigger asChild>
                <Button variant="outline" size="sm" disabled type="button">
                  <MessageSquare className="w-4 h-4 mr-2" />
                  WhatsApp
                </Button>
              </TooltipTrigger>
              <TooltipContent>In arrivo</TooltipContent>
            </Tooltip>
          </div>
        </div>

        {/* ✅ ONE TABLE, FIXED COLUMNS */}
        <div className="p-4 overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead style={{ minWidth: 320 }}>Voce</TableHead>
                <TableHead style={{ minWidth: 160 }}>Fascia Prezzo</TableHead>
                <TableHead style={{ minWidth: 140 }}>Pot size</TableHead>
                <TableHead className="text-right" style={{ minWidth: 120 }}>
                  Giacenza
                </TableHead>
                <TableHead className="text-right" style={{ minWidth: 170 }}>
                  Previsione a 3 giorni
                </TableHead>
                <TableHead className="text-right" style={{ minWidth: 210 }}>
                  Previsione tot dal 4 al 10 giorno
                </TableHead>
                <TableHead className="text-right" style={{ minWidth: 170 }}>
                  Quantità da ordinare
                </TableHead>
              </TableRow>
            </TableHeader>

            <TableBody>
              {flatRows.map((row) => {
                const isGroup = row.kind !== "item";
                const risk = row.risk;
                const indentPx = row.level * 16;

                return (
                  <TableRow
                    key={row.key}
                    className={cn(risk ? "bg-amber-500/10" : undefined, isGroup ? "bg-muted/30" : undefined)}
                  >
                    <TableCell>
                      <div
                        className={cn("flex items-center gap-2", row.expandable ? "cursor-pointer select-none" : "")}
                        style={{ paddingLeft: indentPx }}
                        onClick={() => toggle(row)}
                      >
                        {row.expandable ? (
                          <span className="inline-flex w-4 justify-center text-muted-foreground">
                            {row.expanded ? "▼" : "▶"}
                          </span>
                        ) : (
                          <span className="inline-flex w-4" />
                        )}

                        {risk && <span className="w-2 h-2 rounded-full bg-amber-500" />}

                        <span className={cn(isGroup ? "font-medium" : "text-sm")}>{row.label}</span>

                        {isGroup && (
                          <Badge variant="secondary" className="ml-2">
                            {fmtInt(row.qty_da_ordinare)} ord
                          </Badge>
                        )}
                      </div>
                    </TableCell>

                    <TableCell className="text-muted-foreground">
                      {row.kind === "item" ? (row.fascia_prezzo_iva_inc ?? "-") : "—"}
                    </TableCell>

                    <TableCell className="text-sm">{row.kind === "item" ? (row.pot_sizes_text ?? "-") : "—"}</TableCell>

                    <TableCell className="text-right">{fmtQty(row.qty_giacenza)}</TableCell>
                    <TableCell className="text-right">{fmtQty(row.demand_lead)}</TableCell>
                    <TableCell className="text-right">{fmtQty(row.demand_cycle)}</TableCell>
                    <TableCell className="text-right font-medium text-primary">{fmtInt(row.qty_da_ordinare)}</TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>

          <div className="mt-3 text-xs text-muted-foreground">
            Clicca su ▶︎/▼ nella colonna “Voce” per espandere o comprimere i livelli (fascia, categoria, famiglia).
          </div>
        </div>
      </Card>
    </TooltipProvider>
  );
}

// ----------------------------
// Page (default export ✅)
// ----------------------------
export default function Reorders() {
  const { data, loading, error } = useOrderSuggestions();

  const [searchTerm, setSearchTerm] = useState("");
  const [selectedCategory, setSelectedCategory] = useState("all");
  const [showOnlyRisk, setShowOnlyRisk] = useState(false);

  const categories = useMemo(() => {
    const cats = new Set<string>();
    data.forEach((item) => {
      if (item.categoria_corretta) cats.add(item.categoria_corretta);
    });
    return Array.from(cats).sort((a, b) => a.localeCompare(b, "it"));
  }, [data]);

  const filteredData = useMemo(() => {
    return data.filter((item) => {
      if (searchTerm) {
        const q = searchTerm.toLowerCase().trim();
        const haystack = [
          norm(item.famiglia),
          norm(item.categoria_corretta),
          norm(item.fascia_corretta),
          norm(item.fascia_prezzo_iva_inc),
          norm(item.pot_sizes_text),
        ].join(" ");
        if (!haystack.includes(q)) return false;
      }

      if (selectedCategory !== "all" && item.categoria_corretta !== selectedCategory) {
        return false;
      }

      if (showOnlyRisk && !item.rischio_stockout_prima_di_arrivo) {
        return false;
      }

      return true;
    });
  }, [data, searchTerm, selectedCategory, showOnlyRisk]);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">Riordino</h1>
        <p className="text-muted-foreground">Gestisci e ottimizza i tuoi ordini ai fornitori</p>
      </div>

      <ReorderAssistant />

      <ReorderFilters
        searchTerm={searchTerm}
        onSearchChange={setSearchTerm}
        selectedCategory={selectedCategory}
        onCategoryChange={setSelectedCategory}
        categories={categories}
        showOnlyRisk={showOnlyRisk}
        onShowOnlyRiskChange={setShowOnlyRisk}
      />

      <ReorderTable data={filteredData} loading={loading} error={error} />
    </div>
  );
}

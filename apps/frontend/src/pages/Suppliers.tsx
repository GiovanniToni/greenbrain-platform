import { useState } from 'react';
import { Card } from '@/components/ui/card';
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Progress } from '@/components/ui/progress';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription,
} from '@/components/ui/dialog';
import {
  Upload, RefreshCw, FileText, Package, Truck, AlertTriangle,
  CheckCircle2, Clock, Search, Plus, ExternalLink, Mail, Phone,
} from 'lucide-react';

/* ───────── KPI Card ───────── */
function AcquistiKpi({ title, value, icon: Icon, variant = 'default' }: {
  title: string; value: string; icon: React.ElementType;
  variant?: 'default' | 'warning' | 'destructive';
}) {
  return (
    <Card className={`p-5 ${variant === 'warning' ? 'border-yellow-500/40' : variant === 'destructive' ? 'border-destructive/40' : ''}`}>
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-xs font-medium text-muted-foreground">{title}</p>
          <p className="text-2xl font-bold mt-1 tabular-nums">{value}</p>
        </div>
        <div className={`w-10 h-10 rounded-lg flex items-center justify-center shrink-0 ${
          variant === 'warning' ? 'bg-yellow-500/10' : variant === 'destructive' ? 'bg-destructive/10' : 'bg-primary/10'
        }`}>
          <Icon className={`w-5 h-5 ${
            variant === 'warning' ? 'text-yellow-600' : variant === 'destructive' ? 'text-destructive' : 'text-primary'
          }`} />
        </div>
      </div>
    </Card>
  );
}

/* ───────── TAB A — Inbox ───────── */
function InboxTab() {
  return (
    <Card>
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Fornitore</TableHead>
            <TableHead>Ricevuto</TableHead>
            <TableHead>Sorgente</TableHead>
            <TableHead>Stato</TableHead>
            <TableHead className="text-right">Righe estratte</TableHead>
            <TableHead className="text-right">Normalizzate</TableHead>
            <TableHead>Copertura</TableHead>
            <TableHead>Azioni</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {mockInboxFiles.map((f) => (
            <>
              <TableRow key={f.id}>
                <TableCell className="font-medium">{f.fornitore}</TableCell>
                <TableCell className="text-muted-foreground text-xs">{f.ricevuto}</TableCell>
                <TableCell><Badge variant="secondary">{f.sorgente}</Badge></TableCell>
                <TableCell>
                  <Badge variant={f.stato === 'OK' ? 'default' : f.stato === 'Warning' ? 'secondary' : 'destructive'}>
                    {f.stato}
                  </Badge>
                </TableCell>
                <TableCell className="text-right tabular-nums">{f.righeEstratte.toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{f.righeNormalizzate.toLocaleString()}</TableCell>
                <TableCell>
                  <div className="flex items-center gap-2">
                    <Progress value={f.copertura} className="h-2 w-16" />
                    <span className="text-xs tabular-nums">{f.copertura}%</span>
                  </div>
                </TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    <Button variant="ghost" size="sm" className="h-7 text-xs">Originale</Button>
                    <Button variant="ghost" size="sm" className="h-7 text-xs">Normalizzato</Button>
                    <Button variant="ghost" size="sm" className="h-7 text-xs">Diff</Button>
                  </div>
                </TableCell>
              </TableRow>
              {f.stato === 'Error' && (
                <TableRow key={`${f.id}-err`}>
                  <TableCell colSpan={8} className="pt-0 pb-2">
                    <p className="text-xs text-destructive ml-4">⚠ {f.errore}</p>
                  </TableCell>
                </TableRow>
              )}
            </>
          ))}
        </TableBody>
      </Table>
    </Card>
  );
}

/* ───────── TAB B — Master ───────── */
function MasterTab() {
  const [search, setSearch] = useState('');
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-3">
        <div className="relative flex-1 min-w-[200px]">
          <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
          <Input placeholder="Cerca codart / descrizione…" className="pl-8" value={search} onChange={e => setSearch(e.target.value)} />
        </div>
        <Select><SelectTrigger className="w-[160px]"><SelectValue placeholder="Fornitore" /></SelectTrigger>
          <SelectContent><SelectItem value="all">Tutti</SelectItem>{mockSuppliersExpanded.map(s => <SelectItem key={s.id} value={s.nome}>{s.nome}</SelectItem>)}</SelectContent>
        </Select>
        <Select><SelectTrigger className="w-[140px]"><SelectValue placeholder="Disponibilità" /></SelectTrigger>
          <SelectContent><SelectItem value="all">Tutti</SelectItem><SelectItem value="gt0">&gt; 0</SelectItem><SelectItem value="eq0">= 0</SelectItem></SelectContent>
        </Select>
        <Select><SelectTrigger className="w-[140px]"><SelectValue placeholder="Fascia" /></SelectTrigger>
          <SelectContent><SelectItem value="all">Tutte</SelectItem><SelectItem value="fiorite">Fiorite</SelectItem><SelectItem value="verdi">Verdi</SelectItem></SelectContent>
        </Select>
      </div>
      <Card>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>CodArt</TableHead>
              <TableHead>Descrizione</TableHead>
              <TableHead>Classificazione</TableHead>
              <TableHead>Miglior fornitore</TableHead>
              <TableHead className="text-right">Qty disp.</TableHead>
              <TableHead className="text-right">Prezzo</TableHead>
              <TableHead>Ultimo update</TableHead>
              <TableHead></TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {mockAvailabilityRows.filter(r => !search || r.descrizione.toLowerCase().includes(search.toLowerCase()) || (r.codart ?? '').toLowerCase().includes(search.toLowerCase())).map((r) => (
              <TableRow key={r.id}>
                <TableCell className="font-mono text-xs">{r.codart ?? <Badge variant="destructive" className="text-[10px]">NON MAPPATO</Badge>}</TableCell>
                <TableCell className="font-medium">{r.descrizione}</TableCell>
                <TableCell>
                  <div className="text-xs leading-tight text-muted-foreground">
                    <div>{r.fascia}</div><div>{r.categoria}</div><div>{r.famiglia}</div>
                  </div>
                </TableCell>
                <TableCell>
                  <span className="text-sm">{r.migliorFornitore}</span>
                  <span className="text-xs text-muted-foreground ml-1">({r.leadTime}gg)</span>
                </TableCell>
                <TableCell className="text-right tabular-nums">{r.qty}</TableCell>
                <TableCell className="text-right tabular-nums">{r.prezzo ? `€ ${r.prezzo.toFixed(2)}` : '—'}</TableCell>
                <TableCell className="text-xs text-muted-foreground">{r.ultimoUpdate}</TableCell>
                <TableCell><Button variant="ghost" size="sm" className="h-7 text-xs"><Plus className="w-3 h-3 mr-1" />Bozza</Button></TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Card>
    </div>
  );
}

/* ───────── TAB C — Catalogo ───────── */
function CatalogoTab() {
  const [selectedFamily, setSelectedFamily] = useState(mockCatalogFamilies[0]);
  const [altDialog, setAltDialog] = useState<typeof mockCatalogFamilies[0]['articoli'][0] | null>(null);
  const [searchFam, setSearchFam] = useState('');

  const filtered = mockCatalogFamilies.filter(f => !searchFam || f.nome.toLowerCase().includes(searchFam.toLowerCase()));

  return (
    <>
      <div className="grid grid-cols-1 lg:grid-cols-[320px_1fr] gap-4">
        {/* LEFT */}
        <Card className="p-4 space-y-3 max-h-[600px] overflow-auto">
          <div className="relative">
            <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
            <Input placeholder="Cerca famiglia…" className="pl-8" value={searchFam} onChange={e => setSearchFam(e.target.value)} />
          </div>
          {filtered.map(fam => (
            <button key={fam.id} onClick={() => setSelectedFamily(fam)}
              className={`w-full text-left p-3 rounded-md text-sm transition-colors ${selectedFamily.id === fam.id ? 'bg-primary/10 font-medium' : 'hover:bg-muted'}`}>
              <div className="flex items-center justify-between">
                <span>{fam.nome}</span>
                <Badge variant="secondary" className="text-[10px]">{fam.articoli.filter(a => a.qty > 0).length} disp.</Badge>
              </div>
              <p className="text-xs text-muted-foreground mt-0.5">{fam.fascia} › {fam.categoria}</p>
            </button>
          ))}
        </Card>
        {/* RIGHT */}
        <div className="space-y-4">
          <Card className="p-5">
            <h3 className="text-lg font-semibold">{selectedFamily.nome}</h3>
            <p className="text-sm text-muted-foreground">{selectedFamily.fascia} › {selectedFamily.categoria}</p>
            <div className="flex gap-6 mt-3">
              <div><p className="text-xs text-muted-foreground">Articoli disponibili</p><p className="text-xl font-bold">{selectedFamily.articoli.filter(a => a.qty > 0).length}/{selectedFamily.articoli.length}</p></div>
              <div><p className="text-xs text-muted-foreground">Fornitori con stock</p><p className="text-xl font-bold">{new Set(selectedFamily.articoli.flatMap(a => a.alternative.map(al => al.fornitore))).size}</p></div>
            </div>
          </Card>
          <Card>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>CodArt</TableHead>
                  <TableHead>Descrizione</TableHead>
                  <TableHead>Miglior fornitore</TableHead>
                  <TableHead className="text-right">Qty</TableHead>
                  <TableHead className="text-right">Prezzo</TableHead>
                  <TableHead></TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {selectedFamily.articoli.map(art => (
                  <TableRow key={art.codart}>
                    <TableCell className="font-mono text-xs">{art.codart}</TableCell>
                    <TableCell className="font-medium">{art.descrizione}</TableCell>
                    <TableCell>{art.migliorFornitore}</TableCell>
                    <TableCell className="text-right tabular-nums">{art.qty}</TableCell>
                    <TableCell className="text-right tabular-nums">€ {art.prezzo.toFixed(2)}</TableCell>
                    <TableCell><Button variant="outline" size="sm" className="h-7 text-xs" onClick={() => setAltDialog(art)}>Alternative</Button></TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </Card>
        </div>
      </div>

      <Dialog open={!!altDialog} onOpenChange={() => setAltDialog(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Alternative — {altDialog?.descrizione}</DialogTitle>
            <DialogDescription>Fornitori disponibili per {altDialog?.codart}</DialogDescription>
          </DialogHeader>
          <Table>
            <TableHeader><TableRow><TableHead>Fornitore</TableHead><TableHead className="text-right">Qty</TableHead><TableHead className="text-right">Prezzo</TableHead><TableHead className="text-right">Lead time</TableHead></TableRow></TableHeader>
            <TableBody>
              {altDialog?.alternative.map((a, i) => (
                <TableRow key={i}><TableCell>{a.fornitore}</TableCell><TableCell className="text-right">{a.qty}</TableCell><TableCell className="text-right">€ {a.prezzo.toFixed(2)}</TableCell><TableCell className="text-right">{a.leadTime}gg</TableCell></TableRow>
              ))}
            </TableBody>
          </Table>
        </DialogContent>
      </Dialog>
    </>
  );
}

/* ───────── TAB D — Fornitori ───────── */
function FornitoriTab() {
  const [detail, setDetail] = useState<typeof mockSuppliersExpanded[0] | null>(null);
  return (
    <>
      <Card>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Nome</TableHead>
              <TableHead>Lead time</TableHead>
              <TableHead>Giorni consegna</TableHead>
              <TableHead>Cutoff</TableHead>
              <TableHead>Min. ordine</TableHead>
              <TableHead>Ultimo update</TableHead>
              <TableHead>Metodo</TableHead>
              <TableHead>Affidabilità</TableHead>
              <TableHead></TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {mockSuppliersExpanded.map(s => (
              <TableRow key={s.id}>
                <TableCell className="font-medium">{s.nome}</TableCell>
                <TableCell>{s.leadTime} gg</TableCell>
                <TableCell><div className="flex gap-1">{s.giorniConsegna.map(g => <Badge key={g} variant="secondary" className="text-[10px]">{g}</Badge>)}</div></TableCell>
                <TableCell>{s.cutoff}</TableCell>
                <TableCell>€ {s.minimoOrdine}</TableCell>
                <TableCell className="text-xs text-muted-foreground">{s.ultimoUpdate}</TableCell>
                <TableCell><Badge variant="outline">{s.metodo}</Badge></TableCell>
                <TableCell>
                  <span className={`px-2 py-0.5 rounded-md text-xs font-medium ${
                    s.affidabilita >= 95 ? 'bg-primary/15 text-primary' : s.affidabilita >= 90 ? 'bg-yellow-500/15 text-yellow-700' : 'bg-destructive/15 text-destructive'
                  }`}>{s.affidabilita}%</span>
                </TableCell>
                <TableCell><Button variant="outline" size="sm" className="h-7 text-xs" onClick={() => setDetail(s)}>Dettagli</Button></TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Card>

      <Dialog open={!!detail} onOpenChange={() => setDetail(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{detail?.nome}</DialogTitle>
            <DialogDescription>Condizioni e contatti fornitore</DialogDescription>
          </DialogHeader>
          {detail && (
            <div className="space-y-4 text-sm">
              <div className="grid grid-cols-2 gap-3">
                <div><p className="text-muted-foreground text-xs">Lead time</p><p className="font-medium">{detail.leadTime} giorni</p></div>
                <div><p className="text-muted-foreground text-xs">Cutoff ordini</p><p className="font-medium">{detail.cutoff}</p></div>
                <div><p className="text-muted-foreground text-xs">Minimo ordine</p><p className="font-medium">€ {detail.minimoOrdine}</p></div>
                <div><p className="text-muted-foreground text-xs">Affidabilità</p><p className="font-medium">{detail.affidabilita}%</p></div>
              </div>
              {detail.note && <div><p className="text-muted-foreground text-xs">Note</p><p>{detail.note}</p></div>}
              <div className="flex flex-col gap-2">
                {detail.portale && <a href={detail.portale} target="_blank" rel="noreferrer" className="flex items-center gap-2 text-primary hover:underline"><ExternalLink className="w-4 h-4" />{detail.portale}</a>}
                <p className="flex items-center gap-2"><Mail className="w-4 h-4 text-muted-foreground" />{detail.email}</p>
                <p className="flex items-center gap-2"><Phone className="w-4 h-4 text-muted-foreground" />{detail.telefono}</p>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </>
  );
}

/* ═══════════════════ PAGE ═══════════════════ */
export default function Suppliers() {
  return (
    <div className="space-y-6">
      {/* HEADER */}
      <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">Acquisti</h1>
          <p className="text-muted-foreground">Disponibilità fornitori, condizioni e supporto al riordino</p>
        </div>
        <div className="flex gap-2 flex-wrap">
          <Button><Upload className="w-4 h-4 mr-1" />Carica disponibilità</Button>
          <Button variant="outline"><RefreshCw className="w-4 h-4 mr-1" />Sincronizza</Button>
          <Button variant="secondary"><FileText className="w-4 h-4 mr-1" />Crea bozza ordine</Button>
        </div>
      </div>

      {/* CONTROLS */}
      <div className="flex flex-wrap gap-3">
        <Select defaultValue="sede1"><SelectTrigger className="w-[180px]"><SelectValue /></SelectTrigger>
          <SelectContent><SelectItem value="sede1">Sede 1 – Bergamo</SelectItem><SelectItem value="sede2">Sede 2 – Brescia</SelectItem></SelectContent>
        </Select>
        <Select defaultValue="oggi"><SelectTrigger className="w-[140px]"><SelectValue /></SelectTrigger>
          <SelectContent><SelectItem value="oggi">Oggi</SelectItem><SelectItem value="7g">7 giorni</SelectItem><SelectItem value="30g">30 giorni</SelectItem></SelectContent>
        </Select>
      </div>

      {/* KPI */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <AcquistiKpi title="Fornitori aggiornati oggi" value="7 / 12" icon={CheckCircle2} />
        <AcquistiKpi title="Righe importate oggi" value="12.340" icon={Package} />
        <AcquistiKpi title="Da verificare" value="43" icon={AlertTriangle} variant="warning" />
        <AcquistiKpi title="Fornitori senza update" value="3" icon={Clock} variant="destructive" />
      </div>

      {/* TABS */}
      <Tabs defaultValue="inbox" className="space-y-4">
        <TabsList>
          <TabsTrigger value="inbox">Inbox disponibilità</TabsTrigger>
          <TabsTrigger value="master">Disponibilità (Master)</TabsTrigger>
          <TabsTrigger value="catalogo">Catalogo</TabsTrigger>
          <TabsTrigger value="fornitori">Fornitori</TabsTrigger>
        </TabsList>

        <TabsContent value="inbox"><InboxTab /></TabsContent>
        <TabsContent value="master"><MasterTab /></TabsContent>
        <TabsContent value="catalogo"><CatalogoTab /></TabsContent>
        <TabsContent value="fornitori"><FornitoriTab /></TabsContent>
      </Tabs>
    </div>
  );
}

/* ═══════════════════ MOCK DATA ═══════════════════ */

const mockSuppliersExpanded = [
  { id: 1, nome: 'FloraItalia', leadTime: 3, giorniConsegna: ['Lun', 'Mer', 'Ven'], cutoff: '18:00', minimoOrdine: 150, ultimoUpdate: '10 Feb 2026 08:12', metodo: 'Excel', affidabilita: 95, note: 'Consegna sempre puntuale, verificare minimo per spedizioni isole.', portale: 'https://portal.floraitalia.it', email: 'ordini@floraitalia.it', telefono: '+39 035 123 456' },
  { id: 2, nome: 'HerbGarden', leadTime: 2, giorniConsegna: ['Mar', 'Gio'], cutoff: '14:00', minimoOrdine: 80, ultimoUpdate: '10 Feb 2026 07:45', metodo: 'PDF', affidabilita: 98, note: null, portale: null, email: 'info@herbgarden.it', telefono: '+39 030 654 321' },
  { id: 3, nome: 'RoseWorld', leadTime: 5, giorniConsegna: ['Mer'], cutoff: '12:00', minimoOrdine: 200, ultimoUpdate: '09 Feb 2026 16:30', metodo: 'Web', affidabilita: 92, note: 'Tempi più lunghi da ottobre a dicembre.', portale: 'https://b2b.roseworld.com', email: 'vendite@roseworld.com', telefono: '+39 02 987 654' },
  { id: 4, nome: 'Vivaio Bonetti', leadTime: 4, giorniConsegna: ['Lun', 'Gio'], cutoff: '16:00', minimoOrdine: 300, ultimoUpdate: '08 Feb 2026 09:00', metodo: 'Excel', affidabilita: 88, note: 'Specializzato in alberi da frutto e conifere grandi.', portale: null, email: 'ordini@vivaiobonetti.it', telefono: '+39 045 111 222' },
  { id: 5, nome: 'GreenSupply', leadTime: 2, giorniConsegna: ['Lun', 'Mar', 'Mer', 'Gio', 'Ven'], cutoff: '20:00', minimoOrdine: 50, ultimoUpdate: '10 Feb 2026 06:00', metodo: 'Web', affidabilita: 96, note: 'Fornitore materiali non-vivi. Consegna rapida.', portale: 'https://shop.greensupply.it', email: 'support@greensupply.it', telefono: '+39 02 333 444' },
  { id: 6, nome: 'Agrivivai Rossi', leadTime: 3, giorniConsegna: ['Mar', 'Ven'], cutoff: '15:00', minimoOrdine: 120, ultimoUpdate: '07 Feb 2026 11:20', metodo: 'PDF', affidabilita: 85, note: null, portale: null, email: 'commerciale@agrivivai.it', telefono: '+39 0376 555 666' },
];

const mockInboxFiles = [
  { id: 1, fornitore: 'FloraItalia', ricevuto: '10/02/2026 08:12', sorgente: 'Excel', stato: 'OK' as const, righeEstratte: 4520, righeNormalizzate: 4480, copertura: 94, errore: null },
  { id: 2, fornitore: 'HerbGarden', ricevuto: '10/02/2026 07:45', sorgente: 'PDF', stato: 'OK' as const, righeEstratte: 1280, righeNormalizzate: 1275, copertura: 88, errore: null },
  { id: 3, fornitore: 'RoseWorld', ricevuto: '09/02/2026 16:30', sorgente: 'Web', stato: 'Warning' as const, righeEstratte: 3100, righeNormalizzate: 2890, copertura: 72, errore: null },
  { id: 4, fornitore: 'Vivaio Bonetti', ricevuto: '08/02/2026 09:00', sorgente: 'Excel', stato: 'Error' as const, righeEstratte: 0, righeNormalizzate: 0, copertura: 0, errore: 'Formato file non riconosciuto — colonne mancanti: prezzo, disponibilità.' },
  { id: 5, fornitore: 'GreenSupply', ricevuto: '10/02/2026 06:00', sorgente: 'Web', stato: 'OK' as const, righeEstratte: 2340, righeNormalizzate: 2340, copertura: 97, errore: null },
  { id: 6, fornitore: 'Agrivivai Rossi', ricevuto: '07/02/2026 11:20', sorgente: 'PDF', stato: 'Warning' as const, righeEstratte: 1100, righeNormalizzate: 955, copertura: 65, errore: null },
];

const mockAvailabilityRows = [
  { id: 1, codart: 'FI-001', descrizione: 'Geranio zonale rosso P14', fascia: 'Fiorite', categoria: 'Stagionali', famiglia: 'Gerani', migliorFornitore: 'FloraItalia', leadTime: 3, qty: 240, prezzo: 2.10, ultimoUpdate: '10/02' },
  { id: 2, codart: 'FI-002', descrizione: 'Petunia surfinia lilla P12', fascia: 'Fiorite', categoria: 'Stagionali', famiglia: 'Petunie', migliorFornitore: 'FloraItalia', leadTime: 3, qty: 180, prezzo: 1.85, ultimoUpdate: '10/02' },
  { id: 3, codart: 'AR-010', descrizione: 'Basilico genovese P10', fascia: 'Aromatiche', categoria: 'Aromatiche', famiglia: 'Basilico', migliorFornitore: 'HerbGarden', leadTime: 2, qty: 500, prezzo: 1.20, ultimoUpdate: '10/02' },
  { id: 4, codart: null, descrizione: 'Rosa rampicante "New Dawn"', fascia: 'Fiorite', categoria: 'Rose', famiglia: 'Rampicanti', migliorFornitore: 'RoseWorld', leadTime: 5, qty: 45, prezzo: 8.50, ultimoUpdate: '09/02' },
  { id: 5, codart: 'VE-020', descrizione: 'Abete nordmanniana h.150', fascia: 'Verdi', categoria: 'Conifere', famiglia: 'Abeti', migliorFornitore: 'Vivaio Bonetti', leadTime: 4, qty: 12, prezzo: 32.00, ultimoUpdate: '08/02' },
  { id: 6, codart: 'MA-050', descrizione: 'Terriccio universale 50L', fascia: 'Materiali', categoria: 'Terricci', famiglia: 'Universali', migliorFornitore: 'GreenSupply', leadTime: 2, qty: 800, prezzo: 4.50, ultimoUpdate: '10/02' },
  { id: 7, codart: null, descrizione: 'Lavanda angustifolia P14', fascia: 'Aromatiche', categoria: 'Aromatiche', famiglia: 'Lavande', migliorFornitore: 'HerbGarden', leadTime: 2, qty: 320, prezzo: 2.30, ultimoUpdate: '10/02' },
  { id: 8, codart: 'FI-008', descrizione: 'Ciclamino persicum P12', fascia: 'Fiorite', categoria: 'Stagionali', famiglia: 'Ciclamini', migliorFornitore: 'FloraItalia', leadTime: 3, qty: 0, prezzo: 2.80, ultimoUpdate: '10/02' },
];

const mockCatalogFamilies = [
  {
    id: 1, nome: 'Gerani', fascia: 'Fiorite', categoria: 'Stagionali',
    articoli: [
      { codart: 'FI-001', descrizione: 'Geranio zonale rosso P14', migliorFornitore: 'FloraItalia', qty: 240, prezzo: 2.10, alternative: [{ fornitore: 'FloraItalia', qty: 240, prezzo: 2.10, leadTime: 3 }, { fornitore: 'Agrivivai Rossi', qty: 80, prezzo: 2.30, leadTime: 3 }] },
      { codart: 'FI-003', descrizione: 'Geranio parigino rosa P14', migliorFornitore: 'FloraItalia', qty: 150, prezzo: 2.20, alternative: [{ fornitore: 'FloraItalia', qty: 150, prezzo: 2.20, leadTime: 3 }] },
      { codart: 'FI-004', descrizione: 'Geranio imperiale mix P16', migliorFornitore: 'Agrivivai Rossi', qty: 60, prezzo: 3.50, alternative: [{ fornitore: 'Agrivivai Rossi', qty: 60, prezzo: 3.50, leadTime: 3 }, { fornitore: 'FloraItalia', qty: 30, prezzo: 3.80, leadTime: 3 }] },
    ],
  },
  {
    id: 2, nome: 'Petunie', fascia: 'Fiorite', categoria: 'Stagionali',
    articoli: [
      { codart: 'FI-002', descrizione: 'Petunia surfinia lilla P12', migliorFornitore: 'FloraItalia', qty: 180, prezzo: 1.85, alternative: [{ fornitore: 'FloraItalia', qty: 180, prezzo: 1.85, leadTime: 3 }] },
      { codart: 'FI-005', descrizione: 'Petunia grandiflora bianca P12', migliorFornitore: 'FloraItalia', qty: 90, prezzo: 1.75, alternative: [{ fornitore: 'FloraItalia', qty: 90, prezzo: 1.75, leadTime: 3 }, { fornitore: 'Agrivivai Rossi', qty: 40, prezzo: 1.90, leadTime: 3 }] },
    ],
  },
  {
    id: 3, nome: 'Basilico', fascia: 'Aromatiche', categoria: 'Aromatiche',
    articoli: [
      { codart: 'AR-010', descrizione: 'Basilico genovese P10', migliorFornitore: 'HerbGarden', qty: 500, prezzo: 1.20, alternative: [{ fornitore: 'HerbGarden', qty: 500, prezzo: 1.20, leadTime: 2 }, { fornitore: 'GreenSupply', qty: 200, prezzo: 1.35, leadTime: 2 }] },
      { codart: 'AR-011', descrizione: 'Basilico greco P10', migliorFornitore: 'HerbGarden', qty: 300, prezzo: 1.30, alternative: [{ fornitore: 'HerbGarden', qty: 300, prezzo: 1.30, leadTime: 2 }] },
    ],
  },
  {
    id: 4, nome: 'Lavande', fascia: 'Aromatiche', categoria: 'Aromatiche',
    articoli: [
      { codart: 'AR-020', descrizione: 'Lavanda angustifolia P14', migliorFornitore: 'HerbGarden', qty: 320, prezzo: 2.30, alternative: [{ fornitore: 'HerbGarden', qty: 320, prezzo: 2.30, leadTime: 2 }, { fornitore: 'FloraItalia', qty: 100, prezzo: 2.50, leadTime: 3 }] },
    ],
  },
  {
    id: 5, nome: 'Abeti', fascia: 'Verdi', categoria: 'Conifere',
    articoli: [
      { codart: 'VE-020', descrizione: 'Abete nordmanniana h.150', migliorFornitore: 'Vivaio Bonetti', qty: 12, prezzo: 32.00, alternative: [{ fornitore: 'Vivaio Bonetti', qty: 12, prezzo: 32.00, leadTime: 4 }] },
      { codart: 'VE-021', descrizione: 'Abete rosso h.120', migliorFornitore: 'Vivaio Bonetti', qty: 8, prezzo: 28.00, alternative: [{ fornitore: 'Vivaio Bonetti', qty: 8, prezzo: 28.00, leadTime: 4 }] },
    ],
  },
];

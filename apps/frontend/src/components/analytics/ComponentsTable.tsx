import { useState, useMemo } from 'react';
import { Search } from 'lucide-react';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import { ComponentArticle } from '@/hooks/useAnalyticsComponents';

interface ComponentsTableProps {
  data: ComponentArticle[];
  loading: boolean;
}

export function ComponentsTable({ data, loading }: ComponentsTableProps) {
  const [searchTerm, setSearchTerm] = useState('');

  const filteredData = useMemo(() => {
    if (!searchTerm) return data;
    const term = searchTerm.toLowerCase();
    return data.filter(
      (row) =>
        row.codart?.toLowerCase().includes(term) ||
        row.articolo_nome?.toLowerCase().includes(term)
    );
  }, [data, searchTerm]);

  if (loading) {
    return (
      <Card className="p-6">
        <h3 className="text-sm font-medium text-muted-foreground mb-4">Articoli Componenti</h3>
        <div className="h-48 flex items-center justify-center text-muted-foreground">
          Caricamento...
        </div>
      </Card>
    );
  }

  if (data.length === 0) {
    return (
      <Card className="p-6">
        <h3 className="text-sm font-medium text-muted-foreground mb-4">Articoli Componenti</h3>
        <div className="h-48 flex items-center justify-center text-muted-foreground">
          Seleziona un'entità per visualizzare gli articoli
        </div>
      </Card>
    );
  }

  return (
    <Card className="p-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-medium text-muted-foreground">
          Articoli Componenti ({data.length})
        </h3>
        <div className="relative w-64">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
          <Input
            placeholder="Cerca codart o nome..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="pl-10 h-8 text-sm"
          />
        </div>
      </div>

      <div className="max-h-96 overflow-auto border rounded-lg">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="text-xs">Codart</TableHead>
              <TableHead className="text-xs">Nome Articolo</TableHead>
              <TableHead className="text-xs">Pot Size</TableHead>
              <TableHead className="text-xs">Fascia Prezzo</TableHead>
              <TableHead className="text-xs text-right">Prezzo IVA incl.</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {filteredData.slice(0, 100).map((row, idx) => (
              <TableRow key={`${row.codart}-${idx}`}>
                <TableCell className="text-xs font-mono">{row.codart}</TableCell>
                <TableCell className="text-xs">{row.articolo_nome}</TableCell>
                <TableCell className="text-xs">{row.pot_size || '-'}</TableCell>
                <TableCell className="text-xs">{row.fascia_prezzo_iva_inc || '-'}</TableCell>
                <TableCell className="text-xs text-right">
                  {row.prezzo_iva_inclusa != null
                    ? `€${row.prezzo_iva_inclusa.toLocaleString('it-IT', { minimumFractionDigits: 2 })}`
                    : '-'}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
        {filteredData.length > 100 && (
          <p className="text-xs text-muted-foreground p-2 text-center">
            Mostrati 100 di {filteredData.length} articoli
          </p>
        )}
      </div>
    </Card>
  );
}

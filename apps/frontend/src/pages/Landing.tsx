import { Link } from 'react-router-dom';
import { Leaf, TrendingUp, BarChart3, Calendar, ShoppingCart, FileSpreadsheet, Users, Clock, ArrowRight } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { useAuth } from '@/hooks/useAuth';

export default function Landing() {
  const { user, loading } = useAuth();

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <header className="border-b border-border/50 bg-card/80 backdrop-blur-sm sticky top-0 z-50">
        <div className="container mx-auto px-4 py-4 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 bg-primary rounded-xl flex items-center justify-center">
              <Leaf className="w-6 h-6 text-primary-foreground" />
            </div>
            <span className="text-xl font-bold">GreenBrain</span>
          </div>
          <div className="flex items-center gap-3">
            {!loading && user ? (
              <Button asChild>
                <Link to="/dashboard">Vai alla Dashboard</Link>
              </Button>
            ) : (
              <Button asChild>
                <Link to="/login">Accedi</Link>
              </Button>
            )}
          </div>
        </div>
      </header>

      {/* Hero Section */}
      <section className="py-24 lg:py-32">
        <div className="container mx-auto px-4">
          <div className="max-w-4xl mx-auto text-center">
            <h1 className="text-4xl lg:text-5xl xl:text-6xl font-bold leading-tight text-foreground tracking-tight">
              Decisioni di riordino basate sui dati.
              <span className="block text-primary mt-2">Non sull'intuito.</span>
            </h1>
            <p className="text-lg lg:text-xl text-muted-foreground mt-6 max-w-2xl mx-auto leading-relaxed">
              Una piattaforma avanzata per Garden Center che vogliono controllare stock, prevedere la domanda e ottimizzare gli ordini.
            </p>
            <div className="flex flex-wrap justify-center gap-4 mt-10">
              {!loading && user ? (
                <Button size="lg" asChild>
                  <Link to="/dashboard">Vai alla Dashboard</Link>
                </Button>
              ) : (
                <>
                  <Button size="lg" asChild>
                    <Link to="/login">Accedi alla piattaforma</Link>
                  </Button>
                  <Button size="lg" variant="outline" asChild>
                    <Link to="/login">Richiedi accesso</Link>
                  </Button>
                </>
              )}
            </div>
            {/* Trust text */}
            <div className="mt-16 flex flex-wrap justify-center gap-x-8 gap-y-2 text-sm text-muted-foreground font-medium tracking-wide">
              <span>Forecast</span>
              <span className="hidden sm:inline">•</span>
              <span>Analytics</span>
              <span className="hidden sm:inline">•</span>
              <span>Pianificazione</span>
              <span className="hidden sm:inline">•</span>
              <span>Controllo operativo</span>
            </div>
          </div>
        </div>
      </section>

      {/* Executive Summary - Metrics */}
      <section className="py-20 bg-muted/30">
        <div className="container mx-auto px-4">
          <div className="grid md:grid-cols-3 gap-8 max-w-4xl mx-auto">
            <Card className="p-8 text-center bg-card border-border/50">
              <p className="text-4xl font-bold text-primary">–25%</p>
              <p className="text-foreground font-medium mt-2">Riduzione stock-out</p>
            </Card>
            <Card className="p-8 text-center bg-card border-border/50">
              <p className="text-4xl font-bold text-primary">–18%</p>
              <p className="text-foreground font-medium mt-2">Riduzione overstock stagionale</p>
            </Card>
            <Card className="p-8 text-center bg-card border-border/50">
              <p className="text-4xl font-bold text-primary">+12%</p>
              <p className="text-foreground font-medium mt-2">Migliore rotazione assortimento</p>
            </Card>
          </div>
          <p className="text-center text-sm text-muted-foreground mt-8">
            Indicatori stimati su analisi storiche e simulazioni operative.
          </p>
        </div>
      </section>

      {/* Processo Decisionale */}
      <section className="py-24">
        <div className="container mx-auto px-4">
          <h2 className="text-3xl font-bold text-center mb-16">Un processo di riordino strutturato</h2>
          <div className="grid md:grid-cols-3 gap-12 max-w-5xl mx-auto">
            {/* Analizza */}
            <div className="text-center">
              <div className="w-14 h-14 bg-primary/10 rounded-2xl flex items-center justify-center mx-auto mb-6">
                <BarChart3 className="w-7 h-7 text-primary" />
              </div>
              <h3 className="text-xl font-semibold mb-4">Analizza</h3>
              <ul className="space-y-2 text-muted-foreground">
                <li>Vendite storiche</li>
                <li>Stagionalità</li>
                <li>Performance per categoria</li>
              </ul>
            </div>
            {/* Prevede */}
            <div className="text-center">
              <div className="w-14 h-14 bg-primary/10 rounded-2xl flex items-center justify-center mx-auto mb-6">
                <TrendingUp className="w-7 h-7 text-primary" />
              </div>
              <h3 className="text-xl font-semibold mb-4">Prevede</h3>
              <ul className="space-y-2 text-muted-foreground">
                <li>Forecast settimanale</li>
                <li>Eventi e festività</li>
                <li>Meteo locale</li>
              </ul>
            </div>
            {/* Ottimizza */}
            <div className="text-center">
              <div className="w-14 h-14 bg-primary/10 rounded-2xl flex items-center justify-center mx-auto mb-6">
                <ShoppingCart className="w-7 h-7 text-primary" />
              </div>
              <h3 className="text-xl font-semibold mb-4">Ottimizza</h3>
              <ul className="space-y-2 text-muted-foreground">
                <li>Quantità suggerite</li>
                <li>Copertura stock</li>
                <li>Ordini per fornitore</li>
              </ul>
            </div>
          </div>
        </div>
      </section>

      {/* Controllo Operativo */}
      <section className="py-24 bg-muted/30">
        <div className="container mx-auto px-4">
          <div className="max-w-3xl mx-auto">
            <h2 className="text-3xl font-bold text-center mb-12">Controllo operativo completo</h2>
            <div className="grid sm:grid-cols-2 gap-x-12 gap-y-4">
              <div className="flex items-center gap-3">
                <ArrowRight className="w-4 h-4 text-primary flex-shrink-0" />
                <span className="text-foreground">Pianificazione settimanale e mensile</span>
              </div>
              <div className="flex items-center gap-3">
                <ArrowRight className="w-4 h-4 text-primary flex-shrink-0" />
                <span className="text-foreground">Anticipo dei picchi di domanda</span>
              </div>
              <div className="flex items-center gap-3">
                <ArrowRight className="w-4 h-4 text-primary flex-shrink-0" />
                <span className="text-foreground">Confronto anno su anno</span>
              </div>
              <div className="flex items-center gap-3">
                <ArrowRight className="w-4 h-4 text-primary flex-shrink-0" />
                <span className="text-foreground">Gestione fornitori e lead time</span>
              </div>
              <div className="flex items-center gap-3">
                <ArrowRight className="w-4 h-4 text-primary flex-shrink-0" />
                <span className="text-foreground">Report pronti (Excel, PDF, Email)</span>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Target Section */}
      <section className="py-24">
        <div className="container mx-auto px-4">
          <div className="max-w-2xl mx-auto text-center">
            <div className="w-14 h-14 bg-primary/10 rounded-2xl flex items-center justify-center mx-auto mb-6">
              <Users className="w-7 h-7 text-primary" />
            </div>
            <h2 className="text-3xl font-bold mb-6">Progettata per strutture professionali</h2>
            <p className="text-lg text-muted-foreground leading-relaxed">
              GreenBrain è pensata per Garden Center strutturati, catene retail green e responsabili acquisti che lavorano su volumi, margini e stagionalità reali.
            </p>
          </div>
        </div>
      </section>

      {/* Final CTA */}
      <section className="py-24 bg-primary/5">
        <div className="container mx-auto px-4 text-center">
          <h2 className="text-3xl lg:text-4xl font-bold mb-6">
            Porta metodo e dati nel processo di riordino.
          </h2>
          <div className="flex flex-wrap justify-center gap-4 mt-8">
            {!loading && user ? (
              <Button size="lg" asChild>
                <Link to="/dashboard">Vai alla Dashboard</Link>
              </Button>
            ) : (
              <>
                <Button size="lg" asChild>
                  <Link to="/login">Accedi</Link>
                </Button>
                <Button size="lg" variant="outline" asChild>
                  <Link to="/login">Richiedi una demo</Link>
                </Button>
              </>
            )}
          </div>
          <p className="text-sm text-muted-foreground mt-6">
            Implementazione rapida. Nessun software da installare.
          </p>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-border py-8">
        <div className="container mx-auto px-4">
          <div className="flex flex-col sm:flex-row items-center justify-between gap-4">
            <div className="flex items-center gap-2">
              <div className="w-8 h-8 bg-primary rounded-lg flex items-center justify-center">
                <Leaf className="w-4 h-4 text-primary-foreground" />
              </div>
              <span className="font-semibold">GreenBrain</span>
            </div>
            <p className="text-sm text-muted-foreground">
              © {new Date().getFullYear()} GreenBrain. Tutti i diritti riservati.
            </p>
          </div>
        </div>
      </footer>
    </div>
  );
}

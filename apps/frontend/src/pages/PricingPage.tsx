import { Link } from "react-router-dom";
import { ArrowRight, Check, Leaf, ShieldCheck, Download, CreditCard, HelpCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { useAuth } from "@/hooks/useAuth";

export default function PricingPage() {
  const { user, loading } = useAuth();

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <header className="border-b border-border/50 bg-card/80 backdrop-blur-sm sticky top-0 z-50">
        <div className="container mx-auto px-4 py-4 flex items-center justify-between">
          <Link to="/" className="flex items-center gap-3">
            <div className="w-10 h-10 bg-primary rounded-xl flex items-center justify-center">
              <Leaf className="w-6 h-6 text-primary-foreground" />
            </div>
            <span className="text-xl font-bold">GreenBrain</span>
          </Link>
          <div className="flex items-center gap-3">
            {!loading && user ? (
              <Button asChild>
                <Link to="/account">Vai all&apos;account</Link>
              </Button>
            ) : (
              <>
                <Button variant="ghost" asChild>
                  <Link to="/login">Accedi</Link>
                </Button>
                <Button asChild>
                  <Link to="/signup?plan=starter">Inizia ora</Link>
                </Button>
              </>
            )}
          </div>
        </div>
      </header>

      {/* Hero */}
      <section className="py-20 lg:py-24">
        <div className="container mx-auto px-4">
          <div className="max-w-3xl mx-auto text-center">
            <Badge variant="secondary" className="mb-4">Piani disponibili</Badge>
            <h1 className="text-4xl lg:text-5xl font-bold tracking-tight">
              Prezzi chiari per partire con GreenBrain
            </h1>
            <p className="text-lg text-muted-foreground mt-6 leading-relaxed">
              Scegli il piano adatto alla tua struttura. Starter o Enterprise, il processo
              è sempre guidato e il supporto onboarding è incluso.
            </p>
          </div>
        </div>
      </section>

      {/* Plans */}
      <section className="pb-20">
        <div className="container mx-auto px-4">
          <div className="max-w-5xl mx-auto grid lg:grid-cols-2 gap-8 items-start">

            {/* Starter */}
            <Card className="p-8 border-primary/30 shadow-md relative">
              <Badge className="absolute -top-3 left-8">Più scelto</Badge>
              <div className="mb-6">
                <p className="text-sm uppercase tracking-wide text-muted-foreground font-medium">GreenBrain Starter</p>
                <h2 className="text-4xl font-bold mt-2">€99<span className="text-xl font-normal text-muted-foreground"> / mese</span></h2>
                <p className="text-muted-foreground mt-3 text-sm leading-relaxed">
                  Ideale per Garden Center che vogliono partire con controllo operativo,
                  forecast e processo di riordino strutturato.
                </p>
              </div>
              <Separator className="mb-6" />
              <div className="grid gap-3 text-sm mb-8">
                {[
                  "Area cliente riservata",
                  "Accesso GreenBrain con credenziali dedicate",
                  "Stato onboarding e provisioning in tempo reale",
                  "Download bundle cliente autenticato",
                  "Analisi dati e processo di riordino",
                  "Onboarding guidato incluso",
                  "Aggiornamenti e supporto tecnico",
                  "Attivazione abbonamento dal portale",
                ].map((item) => (
                  <div key={item} className="flex items-start gap-3">
                    <Check className="w-4 h-4 text-primary mt-0.5 flex-shrink-0" />
                    <span>{item}</span>
                  </div>
                ))}
              </div>
              {!loading && user ? (
                <Button size="lg" className="w-full" asChild>
                  <Link to="/account">
                    Vai all&apos;account <ArrowRight className="w-4 h-4 ml-2" />
                  </Link>
                </Button>
              ) : (
                <div className="flex flex-col gap-3">
                  <Button size="lg" className="w-full" asChild>
                    <Link to="/signup?plan=starter">
                      Crea account <ArrowRight className="w-4 h-4 ml-2" />
                    </Link>
                  </Button>
                  <Button size="lg" variant="outline" className="w-full" asChild>
                    <Link to="/login">Ho già un account</Link>
                  </Button>
                </div>
              )}
            </Card>

            {/* Enterprise */}
            <Card className="p-8 border-border shadow-sm">
              <div className="mb-6">
                <p className="text-sm uppercase tracking-wide text-muted-foreground font-medium">GreenBrain Enterprise</p>
                <h2 className="text-4xl font-bold mt-2">Su misura</h2>
                <p className="text-muted-foreground mt-3 text-sm leading-relaxed">
                  Per strutture articolate, catene retail o multi-sede che richiedono
                  configurazioni personalizzate e SLA dedicati.
                </p>
              </div>
              <Separator className="mb-6" />
              <div className="grid gap-3 text-sm mb-8">
                {[
                  "Tutto il piano Starter",
                  "Configurazione personalizzata",
                  "Onboarding dedicato e prioritario",
                  "SLA e supporto avanzato",
                  "Multi-tenant o multi-sede",
                  "Integrazione gestionale su misura",
                ].map((item) => (
                  <div key={item} className="flex items-start gap-3">
                    <Check className="w-4 h-4 text-muted-foreground mt-0.5 flex-shrink-0" />
                    <span>{item}</span>
                  </div>
                ))}
              </div>
              <div className="flex flex-col gap-3">
                <Button size="lg" variant="outline" className="w-full" asChild>
                  <Link to="/signup?plan=enterprise">
                    Richiedi attivazione assistita <ArrowRight className="w-4 h-4 ml-2" />
                  </Link>
                </Button>
                <p className="text-xs text-center text-muted-foreground">
                  Il team GreenBrain ti contatterà entro 24h dalla registrazione.
                </p>
              </div>
            </Card>
          </div>
        </div>
      </section>

      {/* Cosa succede dopo */}
      <section className="py-16 bg-muted/30">
        <div className="container mx-auto px-4">
          <div className="max-w-3xl mx-auto">
            <h2 className="text-2xl font-bold text-center mb-2">Cosa succede dopo l&apos;attivazione</h2>
            <p className="text-center text-muted-foreground text-sm mb-12">
              Dal primo accesso all&apos;operatività completa, ogni step è guidato.
            </p>
            <div className="grid sm:grid-cols-3 gap-8">
              {([
                { Icon: CreditCard, title: "Pagamento sicuro", desc: "Attivi l'abbonamento dalla tua area cliente. Il pagamento è gestito da Stripe con carta o SEPA." },
                { Icon: Download, title: "Bundle pronto", desc: "Il tuo ambiente GreenBrain viene predisposto e il pacchetto reso disponibile per il download." },
                { Icon: ShieldCheck, title: "Onboarding guidato", desc: "Il team ti supporta nell'installazione e nell'integrazione con il tuo gestionale esistente." },
              ] as const).map(({ Icon, title, desc }) => (
                <div key={title} className="text-center">
                  <div className="w-12 h-12 bg-primary/10 rounded-2xl flex items-center justify-center mx-auto mb-4">
                    <Icon className="w-6 h-6 text-primary" />
                  </div>
                  <h3 className="font-semibold mb-2">{title}</h3>
                  <p className="text-sm text-muted-foreground">{desc}</p>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section className="py-16">
        <div className="container mx-auto px-4">
          <div className="max-w-2xl mx-auto">
            <h2 className="text-2xl font-bold text-center mb-10">Domande frequenti</h2>
            <div className="space-y-7">
              {([
                { q: "Cosa serve per iniziare?", a: "È sufficiente compilare il form di registrazione. Il tuo ambiente viene predisposto entro pochi giorni lavorativi." },
                { q: "Come funziona il download del bundle?", a: "Appena il provisioning è completato, trovi il bundle pronto per il download nella tua area cliente. Include tutto il necessario per l'installazione." },
                { q: "Posso integrare GreenBrain con il mio gestionale?", a: "Sì. La guida inclusa nel bundle copre le integrazioni più comuni. Il team è disponibile per connettori specifici su piano Enterprise." },
                { q: "Come viene gestito il pagamento?", a: "L'abbonamento si attiva dalla tua area cliente. Il pagamento è gestito tramite Stripe, con carta di credito o SEPA." },
                { q: "Posso disdire in qualsiasi momento?", a: "Sì. Non ci sono vincoli a lungo termine sul piano Starter. Puoi gestire la disdetta direttamente dal portale." },
              ] as const).map(({ q, a }) => (
                <div key={q}>
                  <h3 className="font-semibold mb-2 flex items-center gap-2">
                    <HelpCircle className="w-4 h-4 text-primary flex-shrink-0" />
                    {q}
                  </h3>
                  <p className="text-sm text-muted-foreground pl-6">{a}</p>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-border py-8">
        <div className="container mx-auto px-4 text-center">
          <div className="flex items-center justify-center gap-2 mb-3">
            <div className="w-8 h-8 bg-primary rounded-lg flex items-center justify-center">
              <Leaf className="w-4 h-4 text-primary-foreground" />
            </div>
            <span className="font-semibold">GreenBrain</span>
          </div>
          <p className="text-sm text-muted-foreground">
            <Link to="/" className="hover:underline">Home</Link>
            {" · "}
            © {new Date().getFullYear()} GreenBrain. Tutti i diritti riservati.
          </p>
        </div>
      </footer>
    </div>
  );
}

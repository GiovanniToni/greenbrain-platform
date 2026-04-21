import { Link } from "react-router-dom";
import { ArrowRight, Check, Leaf, ShieldCheck, Download, CreditCard, HelpCircle, Mail } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { useAuth } from "@/hooks/useAuth";
import { PLAN_META, PLAN_CODES } from "@/lib/planConfig";

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
                  <Link to="/signup?plan=pro">Inizia ora</Link>
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
            <Badge variant="secondary" className="mb-4">3 piani in abbonamento mensile</Badge>
            <h1 className="text-4xl lg:text-5xl font-bold tracking-tight">
              Prezzi chiari per partire con GreenBrain
            </h1>
            <p className="text-lg text-muted-foreground mt-6 leading-relaxed">
              Tre piani in abbonamento mensile, senza vincoli pluriennali. Parti da Starter
              e passa a Pro o Advanced quando vuoi.
            </p>
            <p className="text-sm text-muted-foreground/70 mt-2">
              Abbonamento mensile — onboarding guidato incluso in tutti i piani
            </p>
          </div>
        </div>
      </section>

      {/* 3 plan cards */}
      <section className="pb-16">
        <div className="container mx-auto px-4">
          <div className="max-w-5xl mx-auto grid lg:grid-cols-3 gap-6 items-start">
            {PLAN_CODES.map((code) => {
              const plan = PLAN_META[code];
              const isHighlighted = plan.highlighted;
              return (
                <Card
                  key={code}
                  className={`p-7 relative ${isHighlighted ? "border-primary/40 shadow-lg ring-1 ring-primary/20" : "border-border shadow-sm"}`}
                >
                  {isHighlighted && (
                    <Badge className="absolute -top-3 left-7">Più scelto</Badge>
                  )}
                  <div className="mb-5">
                    <p className="text-xs uppercase tracking-wide text-muted-foreground font-semibold mb-1">
                      GreenBrain {plan.label}
                    </p>
                    <div className="flex items-end gap-1">
                      <span className="text-4xl font-bold">€{plan.price}</span>
                      <span className="text-base text-muted-foreground mb-1"> / mese</span>
                    </div>
                    <p className="text-xs text-muted-foreground mt-1">abbonamento mensile</p>
                    <p className="text-muted-foreground mt-3 text-sm leading-relaxed">
                      {plan.tagline}
                    </p>
                  </div>
                  <Separator className="mb-5" />
                  <div className="grid gap-2.5 text-sm mb-7">
                    {plan.features.map((feat) => (
                      <div key={feat} className="flex items-start gap-2.5">
                        <Check className={`w-4 h-4 mt-0.5 flex-shrink-0 ${isHighlighted ? "text-primary" : "text-muted-foreground"}`} />
                        <span>{feat}</span>
                      </div>
                    ))}
                  </div>
                  {!loading && user ? (
                    <Button size="lg" className="w-full" variant={isHighlighted ? "default" : "outline"} asChild>
                      <Link to="/account">
                        Vai all&apos;account <ArrowRight className="w-4 h-4 ml-2" />
                      </Link>
                    </Button>
                  ) : (
                    <Button size="lg" className="w-full" variant={isHighlighted ? "default" : "outline"} asChild>
                      <Link to={`/signup?plan=${code}`}>
                        Crea account {plan.label} <ArrowRight className="w-4 h-4 ml-2" />
                      </Link>
                    </Button>
                  )}
                </Card>
              );
            })}
          </div>
        </div>
      </section>

      {/* Enterprise */}
      <section className="pb-20">
        <div className="container mx-auto px-4">
          <Card className="max-w-5xl mx-auto p-8 border-border shadow-sm">
            <div className="flex flex-col sm:flex-row sm:items-center gap-6">
              <div className="flex-1">
                <p className="text-xs uppercase tracking-wide text-muted-foreground font-semibold mb-1">GreenBrain Enterprise</p>
                <h2 className="text-2xl font-bold">Su misura</h2>
                <p className="text-muted-foreground mt-2 text-sm leading-relaxed max-w-xl">
                  Per strutture articolate, catene retail o multi-sede che richiedono
                  configurazioni personalizzate, SLA dedicati e integrazioni su misura.
                  Include tutto di Advanced più onboarding prioritario e supporto dedicato.
                </p>
              </div>
              <div className="flex flex-col gap-3 min-w-52">
                <Button size="lg" variant="outline" className="w-full" asChild>
                  <Link to="/signup?plan=enterprise">
                    <Mail className="w-4 h-4 mr-2" />
                    Richiedi attivazione
                  </Link>
                </Button>
                <p className="text-xs text-center text-muted-foreground">
                  Il team GreenBrain ti contatterà entro 24h.
                </p>
              </div>
            </div>
          </Card>
        </div>
      </section>

      {/* Cosa succede dopo */}
      <section className="py-16 bg-muted/30">
        <div className="container mx-auto px-4">
          <div className="max-w-3xl mx-auto">
            <h2 className="text-2xl font-bold text-center mb-2">Cosa succede dopo la registrazione</h2>
            <p className="text-center text-muted-foreground text-sm mb-12">
              Dal primo accesso all&apos;operatività completa, ogni step è guidato.
            </p>
            <div className="grid sm:grid-cols-3 gap-8">
              {([
                { Icon: CreditCard, title: "Pagamento sicuro", desc: "Salvi il metodo di pagamento dalla tua area cliente. L'abbonamento si attiva solo dopo la sessione di setup e la verifica dei dati." },
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
                {
                  q: "Cosa serve per iniziare?",
                  a: "È sufficiente compilare il form di registrazione. Il tuo ambiente viene predisposto entro pochi giorni lavorativi dal team GreenBrain.",
                },
                {
                  q: "Qual è la differenza tra i piani?",
                  a: "Starter include dati storici, analytics e assortment planner. Pro aggiunge forecast e riordino automatizzato. Advanced aggiunge l'area fornitori. Tutti i piani includono onboarding guidato.",
                },
                {
                  q: "Come funziona il download del bundle?",
                  a: "Appena il provisioning è completato, trovi il bundle pronto per il download nella tua area cliente. Include tutto il necessario per l'installazione.",
                },
                {
                  q: "Posso integrare GreenBrain con il mio gestionale?",
                  a: "Sì. La guida inclusa nel bundle copre le integrazioni più comuni. Il team è disponibile per connettori specifici su piano Enterprise.",
                },
                {
                  q: "Come viene gestito il pagamento?",
                  a: "Il metodo di pagamento si salva dalla tua area cliente tramite Stripe, con carta di credito. L'abbonamento mensile si attiva solo dopo la sessione di setup e la verifica dei dati.",
                },
                {
                  q: "Posso cambiare piano in futuro?",
                  a: "Sì. È possibile passare a un piano superiore in qualsiasi momento contattando il team GreenBrain.",
                },
                {
                  q: "Come funziona la disdetta?",
                  a: "I piani sono in abbonamento mensile senza vincoli pluriennali. Per disdire è sufficiente contattare il team GreenBrain con almeno 30 giorni di anticipo rispetto alla scadenza mensile. La gestione della disdetta automatica dal portale è in sviluppo.",
                },
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

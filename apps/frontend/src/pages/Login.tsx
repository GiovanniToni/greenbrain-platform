import { useEffect, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { Leaf, Mail, Lock } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card } from "@/components/ui/card";
import { useToast } from "@/hooks/use-toast";
import { useAuth, type AuthUser } from "@/hooks/useAuth";
import { ApiError, apiPost, setStoredToken } from "@/lib/apiClient";

function redirectAfterLogin(user: AuthUser, navigate: ReturnType<typeof useNavigate>) {
  const currentHost = window.location.host;
  const targetHost = user.home_host?.trim();
  const targetPath = user.home_path?.trim() || "/dashboard";

  if (targetHost && targetHost !== currentHost) {
    window.location.href = `https://${targetHost}${targetPath}`;
    return;
  }

  navigate(targetPath || "/dashboard", { replace: true });
}

export default function Login() {
  const [searchParams] = useSearchParams();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const navigate = useNavigate();
  const { toast } = useToast();
  const { user, loading, login } = useAuth();

  const currentHost = window.location.host;
  const isCentralHost = currentHost === "www.greenbrain.it" || currentHost === "greenbrain.it";

  useEffect(() => {
    if (!loading && user) {
      redirectAfterLogin(user, navigate);
    }
  }, [user, loading, navigate]);

  useEffect(() => {
    const sso = searchParams.get("sso");
    if (!sso || isCentralHost) return;

    let cancelled = false;

    async function run() {
      try {
        const data = await apiPost("/api/v1/auth/sso/exchange", { ticket: sso });
        setStoredToken(data.access_token);
        window.location.href = `${window.location.origin}/dashboard`;
      } catch (err) {
        if (!cancelled) {
          setErrorMessage(err instanceof Error ? err.message : "Errore SSO");
        }
      }
    }

    run();
    return () => {
      cancelled = true;
    };
  }, [searchParams, isCentralHost]);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsLoading(true);
    setErrorMessage(null);

    try {
      if (isCentralHost) {
        const data = await apiPost("/api/v1/auth/sso/start", { email, password });
        window.location.href = data.redirect_url;
        return;
      }

      const me = await login(email, password);

      toast({
        title: "Benvenuto!",
        description: "Accesso effettuato con successo.",
      });

      redirectAfterLogin(me, navigate);
    } catch (err) {
      const msg =
        err instanceof ApiError && err.status === 401
          ? "Credenziali non valide. Riprova."
          : err instanceof Error
            ? err.message
            : "Errore di accesso.";

      setErrorMessage(msg);

      toast({
        title: "Errore di accesso",
        description: msg,
        variant: "destructive",
      });
    } finally {
      setIsLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background">
        <div className="animate-pulse text-muted-foreground">Caricamento...</div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background flex items-center justify-center p-4">
      <Card className="w-full max-w-md p-8 animate-fade-in">
        <div className="flex items-center justify-center gap-3 mb-8">
          <div className="w-12 h-12 bg-primary rounded-xl flex items-center justify-center">
            <Leaf className="w-7 h-7 text-primary-foreground" />
          </div>
          <span className="text-2xl font-bold">GreenBrain</span>
        </div>

        <h1 className="text-xl font-semibold text-center mb-2">Bentornato!</h1>
        <p className="text-sm text-muted-foreground text-center mb-8">Accedi al tuo Garden Center</p>

        <form onSubmit={handleLogin} className="space-y-4" autoComplete="off">
          <div className="space-y-2">
            <label className="text-sm font-medium">Email</label>
            <div className="relative">
              <Mail className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
              <Input
                type="email"
                name="gb_email"
                autoComplete="off"
                data-lpignore="true"
                data-1p-ignore="true"
                placeholder="nome@gardencenter.it"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="pl-10"
                required
              />
            </div>
          </div>

          <div className="space-y-2">
            <label className="text-sm font-medium">Password</label>
            <div className="relative">
              <Lock className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
              <Input
                type="password"
                name="gb_password"
                autoComplete="new-password"
                data-lpignore="true"
                data-1p-ignore="true"
                placeholder="••••••••"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="pl-10"
                required
              />
            </div>
          </div>

          {errorMessage && <p className="text-sm text-destructive text-center">{errorMessage}</p>}

          <Button type="submit" className="w-full" disabled={isLoading}>
            {isLoading ? "Accesso in corso..." : "Accedi"}
          </Button>
        </form>

        <p className="text-xs text-muted-foreground text-center mt-6">
          Hai dimenticato la password? Contatta l&apos;amministratore.
        </p>
      </Card>
    </div>
  );
}

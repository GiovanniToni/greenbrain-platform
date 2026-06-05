import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";

import { AuthProvider } from "@/hooks/useAuth";
import { AppLayout } from "@/components/layout/AppLayout";
import { ProtectedRoute, CustomerRoute, InternalAdminRoute } from "@/components/auth/ProtectedRoute";

import Landing from "@/pages/Landing";
import Login from "@/pages/Login";
import ForgotPassword from "@/pages/ForgotPassword";
import ResetPassword from "@/pages/ResetPassword";
import PricingPage from "@/pages/PricingPage";
import CustomerPortalDashboard from "@/pages/CustomerPortalDashboard";
import LocalPasswordSync from "@/pages/LocalPasswordSync";
import CustomerOpsConsolePage from "@/pages/CustomerOpsConsolePage";
import Signup from "@/pages/Signup";
import Customers from "@/pages/Customers";
import CustomerDetail from "@/pages/CustomerDetail";

import Dashboard from "@/pages/Dashboard";
import Reorders from "@/pages/Reorders";
import Analytics from "@/pages/Analytics";
import Suppliers from "@/pages/Suppliers";
import AssortmentPlanner from "@/pages/AssortmentPlanner";
import NotFound from "@/pages/NotFound";

const queryClient = new QueryClient();

const App = () => (
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <Toaster />
      <Sonner />
      <BrowserRouter>
        <AuthProvider>
          <Routes>
            <Route path="/" element={<Landing />} />
            <Route path="/login" element={<Login />} />
            <Route path="/forgot-password" element={<ForgotPassword />} />
            <Route path="/reset-password" element={<ResetPassword />} />
            <Route path="/pricing" element={<PricingPage />} />
            <Route path="/customer-portal" element={<Navigate to="/account" replace />} />
            <Route path="/signup" element={<Signup />} />
            <Route path="/local-sync/password" element={<LocalPasswordSync />} />

            <Route element={<ProtectedRoute />}>
              <Route element={<AppLayout />}>
                <Route path="/account" element={<CustomerPortalDashboard />} />
                <Route path="/portal" element={<Navigate to="/account" replace />} />

                <Route element={<CustomerRoute />}>
                  <Route path="/dashboard" element={<Dashboard />} />
                  <Route path="/dashboard/reorders" element={<Reorders />} />
                  <Route path="/analytics" element={<Analytics />} />
                  <Route path="/assortment-planner" element={<AssortmentPlanner />} />
                  <Route path="/suppliers" element={<Suppliers />} />
                </Route>

                <Route element={<InternalAdminRoute />}>
                  <Route path="/ops" element={<CustomerOpsConsolePage />} />
                  <Route path="/ops/customers" element={<Navigate to="/customers" replace />} />
                  <Route path="/customers" element={<Customers />} />
                  <Route path="/customers/:customerId" element={<CustomerDetail />} />
                </Route>
              </Route>
            </Route>

            <Route path="*" element={<NotFound />} />
          </Routes>
        </AuthProvider>
      </BrowserRouter>
    </TooltipProvider>
  </QueryClientProvider>
);

export default App;

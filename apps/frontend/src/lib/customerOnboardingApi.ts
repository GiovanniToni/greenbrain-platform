import { apiPost } from "@/lib/apiClient";

export type CustomerSignupPayload = {
  company_name: string;
  contact_name?: string;
  contact_email: string;
  contact_phone?: string;
  vat_number?: string;
  address_line?: string;
  city?: string;
  country?: string;
  assigned_release_version?: string;
};

export async function signupCustomer(payload: CustomerSignupPayload) {
  return apiPost("/api/v1/customer-onboarding/signup", payload);
}

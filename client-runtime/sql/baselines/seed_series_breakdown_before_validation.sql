--
-- PostgreSQL database dump
--

\restrict rKhjPZmHyzhNSjIDVhtels3sFenEdjL7A8Nb2g5HXC53kbg1hmvmrzhJDtololR

-- Dumped from database version 16.13
-- Dumped by pg_dump version 16.13

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: t_core_analytics__breakdown_daily_categoria_fp_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain
--

COPY public.t_core_analytics__breakdown_daily_categoria_fp_v2 (data, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, is_holiday, holiday_name, dow, qty_forecast) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__breakdown_daily_famiglia_fp_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain
--

COPY public.t_core_analytics__breakdown_daily_famiglia_fp_v2 (data, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, is_holiday, holiday_name, dow, qty_forecast) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__breakdown_daily_fascia_fp_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain
--

COPY public.t_core_analytics__breakdown_daily_fascia_fp_v2 (data, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, is_holiday, holiday_name, dow, qty_forecast) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__breakdown_monthly_categoria_fp_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain
--

COPY public.t_core_analytics__breakdown_monthly_categoria_fp_v2 (period_start, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, qty_forecast) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__breakdown_monthly_famiglia_fp_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain
--

COPY public.t_core_analytics__breakdown_monthly_famiglia_fp_v2 (period_start, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, qty_forecast) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__breakdown_monthly_fascia_fp_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain
--

COPY public.t_core_analytics__breakdown_monthly_fascia_fp_v2 (period_start, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, qty_forecast) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__breakdown_weekly_categoria_fp_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain
--

COPY public.t_core_analytics__breakdown_weekly_categoria_fp_v2 (period_start, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, qty_forecast) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__breakdown_weekly_famiglia_fp_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain
--

COPY public.t_core_analytics__breakdown_weekly_famiglia_fp_v2 (period_start, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, qty_forecast) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__breakdown_weekly_fascia_fp_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain
--

COPY public.t_core_analytics__breakdown_weekly_fascia_fp_v2 (period_start, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, qty_forecast) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__breakdown_yearly_categoria_fp_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain
--

COPY public.t_core_analytics__breakdown_yearly_categoria_fp_v2 (period_start, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, qty_forecast) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__breakdown_yearly_famiglia_fp_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain
--

COPY public.t_core_analytics__breakdown_yearly_famiglia_fp_v2 (period_start, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, qty_forecast) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__breakdown_yearly_fascia_fp_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain
--

COPY public.t_core_analytics__breakdown_yearly_fascia_fp_v2 (period_start, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, qty_forecast) FROM stdin;
\.


--
-- PostgreSQL database dump complete
--

\unrestrict rKhjPZmHyzhNSjIDVhtels3sFenEdjL7A8Nb2g5HXC53kbg1hmvmrzhJDtololR


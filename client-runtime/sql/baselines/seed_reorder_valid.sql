--
-- PostgreSQL database dump
--

\restrict zGwVvVdQFdQbSe7PVTQK0gr89QoI1hvjAJ1xzLFkfVJvlquRswc0EMeLzI9xCSv

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
-- Data for Name: greenhouse_forecast_results_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain
--

COPY public.greenhouse_forecast_results_v2 (data, famiglia, fascia_prezzo_iva_inc, qty_forecast, created_at) FROM stdin;
2026-04-01	test_family_a	A	5.000	2026-03-31 12:26:19.890277
2026-04-02	test_family_a	A	5.000	2026-03-31 12:26:19.890277
2026-04-03	test_family_a	A	5.000	2026-03-31 12:26:19.890277
2026-04-04	test_family_a	A	6.000	2026-03-31 12:26:19.890277
2026-04-05	test_family_a	A	6.000	2026-03-31 12:26:19.890277
2026-04-06	test_family_a	A	6.000	2026-03-31 12:26:19.890277
2026-04-07	test_family_a	A	6.000	2026-03-31 12:26:19.890277
\.


--
-- Data for Name: greenhouse_products_normalized; Type: TABLE DATA; Schema: public; Owner: greenbrain
--

COPY public.greenhouse_products_normalized (codart, tipo, fascia, categoria, descrizione, fascia_corretta, categoria_corretta, famiglia, prezzo_iva_esclusa, prezzo_iva_inclusa, fascia_prezzo_iva_inc, pot_size, load_timestamp) FROM stdin;
TEST001	\N	\N	\N	Pianta test	fascia_test	categoria_test	test_family_a	\N	10.00	A	P10	2026-03-31 12:26:19.888472
\.


--
-- Data for Name: greenhouse_sales_family_daily_fact; Type: TABLE DATA; Schema: public; Owner: greenbrain
--

COPY public.greenhouse_sales_family_daily_fact (data, famiglia, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, fascia_corretta, categoria_corretta, pot_sizes_text, pot_sizes_json, articoli_inclusi, articoli_json) FROM stdin;
2026-03-28	test_family_a	A	5.000	50.00	5	fascia_test	categoria_test	\N	[]	\N	[]
2026-03-29	test_family_a	A	6.000	60.00	6	fascia_test	categoria_test	\N	[]	\N	[]
2026-03-30	test_family_a	A	7.000	70.00	7	fascia_test	categoria_test	\N	[]	\N	[]
\.


--
-- Data for Name: greenhouse_stock_raw_upload; Type: TABLE DATA; Schema: public; Owner: greenbrain
--

COPY public.greenhouse_stock_raw_upload (data_rilevazione, codart, descrizione, qty_giacenza, created_at) FROM stdin;
2026-03-31	TEST001	Pianta test	2.000	2026-03-31 12:26:19.889079
\.


--
-- PostgreSQL database dump complete
--

\unrestrict zGwVvVdQFdQbSe7PVTQK0gr89QoI1hvjAJ1xzLFkfVJvlquRswc0EMeLzI9xCSv


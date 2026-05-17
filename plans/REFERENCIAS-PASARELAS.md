# Referencias técnicas — PIX y SPEI

Documentación oficial y de terceros para construir los mock adapters de MiPIT.
Estas referencias se usan en las semanas 9 (adaptadores), 11 (E2E) y 16 (documentación de tesis).

---

## PIX — Banco Central do Brasil (BCB)

### Especificación oficial de la API

| Recurso | Link |
|---|---|
| OpenAPI Spec (YAML raw) | https://raw.githubusercontent.com/bacen/pix-api/master/openapi.yaml |
| Spec renderizada (HTML) | https://bacen.github.io/pix-api/index.html |
| Repositorio GitHub BCB | https://github.com/bacen/pix-api (v2.9.0) |
| API DICT (directorio de llaves) | https://www.bcb.gov.br/content/estabilidadefinanceira/pix/API-DICT-MED-2.0.html |
| GitHub DICT API | https://github.com/bacen/pix-dict-api |
| Manual de Padrones para Iniciación | https://www.bcb.gov.br/content/estabilidadefinanceira/pix/Regulamento_Pix/II_ManualdePadroesparaIniciacaodoPix.pdf |
| Guia Pix Automático | https://www.bcb.gov.br/content/estabilidadefinanceira/pix/guia_pix_automatico.pdf |
| Todos los repos del BCB | https://github.com/bacen |

### Sandbox oficial BCB

| Recurso | Link |
|---|---|
| PIX Tester (sandbox BCB) | https://qr-h.sandbox.pix.bcb.gov.br/ |

> **Acceso restringido**: requiere ser Participante Direto (institución financiera autorizada por el BCB). No disponible para PoC académico.

### Endpoints clave a mockear

| Endpoint | Método | Descripción |
|---|---|---|
| `/v2/cob` | `POST` | Crear cobrança imediata (sin txid) |
| `/v2/cob/{txid}` | `PUT` | Crear cobrança con txid |
| `/v2/cob/{txid}` | `GET` | Consultar cobrança |
| `/v2/cob/{txid}` | `PATCH` | Revisar/modificar cobrança |
| `/v2/cob` | `GET` | Listar cobranças (filtros: inicio, fim, cpf, cnpj, status) |
| `/v2/pix/{e2eid}` | `GET` | Consultar Pix por endToEndId |

### Payload de referencia — Crear cobrança

**Request (`POST /v2/cob` o `PUT /v2/cob/{txid}`):**

```json
{
  "calendario": { "expiracao": 3600 },
  "devedor": {
    "cpf": "12345678909",
    "nome": "Francisco da Silva"
  },
  "valor": { "original": "123.45" },
  "chave": "71cdf9ba-c695-4e3c-b010-abb521a3f1be",
  "solicitacaoPagador": "Cobrança dos serviços prestados."
}
```

**Response (201 Created):**

```json
{
  "calendario": {
    "criacao": "2020-09-09T20:15:00.358Z",
    "expiracao": 3600
  },
  "txid": "7978c0c97ea847e78e8849634473c1f1",
  "revisao": 0,
  "status": "ATIVA",
  "devedor": {
    "cpf": "12345678909",
    "nome": "Francisco da Silva"
  },
  "valor": { "original": "123.45" },
  "chave": "71cdf9ba-c695-4e3c-b010-abb521a3f1be",
  "pixCopiaECola": "00020101021226830014BR.GOV.BCB.PIX..."
}
```

### Payload de referencia — Pix concluído (con endToEndId)

```json
{
  "endToEndId": "E12345678202009091221kkkkkkkkkkk",
  "txid": "655dfdb1a4514b8fbb58254b958913fb",
  "valor": "110.00",
  "horario": "2020-09-09T20:15:00.358Z",
  "pagador": {
    "cnpj": "12345678000195",
    "nome": "Empresa de Serviços SA"
  },
  "infoPagador": "0123456789",
  "devolucoes": [
    {
      "id": "123ABC",
      "rtrId": "Dxxxxxxxx202009091221kkkkkkkkkkk",
      "valor": "10.00",
      "horario": { "solicitacao": "2020-09-09T20:15:00.358Z" },
      "status": "EM_PROCESSAMENTO"
    }
  ]
}
```

### Tipos de chave PIX

| Tipo | Formato | Ejemplo |
|---|---|---|
| CPF | 11 dígitos | `12345678909` |
| CNPJ | 14 dígitos | `12345678000195` |
| Email | email válido | `fulano@example.com` |
| Telefone | +55DDDNUMERO | `+5511987654321` |
| EVP (aleatória) | UUID v4 | `71cdf9ba-c695-4e3c-b010-abb521a3f1be` |

### Statuses de cobrança PIX

| Status | Descripción |
|---|---|
| `ATIVA` | Cobrança creada, pendiente de pago |
| `CONCLUIDA` | Pago recibido |
| `REMOVIDA_PELO_USUARIO_RECEBEDOR` | Cancelada por el receptor |
| `REMOVIDA_PELO_PSP` | Removida por el PSP |
| `EXPIRADA` | Expiró el calendario.expiracao |

### PSPs con documentación de sandbox accesible (referencia adicional)

| PSP | Link | Notas |
|---|---|---|
| Efí Pay (ex-Gerencianet) | https://dev.efipay.com.br/en/docs/api-pix/cobrancas-imediatas/ | Sandbox completo, payloads reales |
| PicPay | https://developers-business.picpay.com/pix/docs/sandbox/ | Sandbox para desarrolladores |
| Stone Open Bank | https://docs.openbank.stone.com.br/docs/referencia-da-api/pix/apis-padrao/cob/criar-cobranca-imediata | Referencia API PIX |
| iugu | https://developer.iugu.com/pix/api/v2/pix/%7Be2eid%7D-get | Referencia endpoints PIX |

---

## SPEI — Banco de México (Banxico)

### Documentación oficial Banxico

| Recurso | Link |
|---|---|
| Página oficial SPEI | https://www.banxico.org.mx/servicios/spei_-transferencias-banco-me.html |
| Participantes SPEI | https://www.banxico.org.mx/servicios/participantes-spei-banco-me.html |
| Circular 14/2017 (normativa) | https://www.banxico.org.mx/marco-normativo/normativa-emitida-por-el-banco-de-mexico/circular-14-2017/%7BA06FBFEE-06BB-F249-32FC-25B334B2A744%7D.pdf |
| Manual de Operación SPEI v5.4 | https://www.banxico.org.mx/sistemas-de-pago/d/%7BA21AA19F-C855-9E64-98A4-832D9A51B2B0%7D.pdf |
| CEP (Comprobante Electrónico de Pago) | https://www.banxico.org.mx/cep/ |

> **Acceso restringido**: requiere autorización escrita de Banxico, HSM, data center Tier III, enlaces privados dedicados. Participación directa toma 12-18 meses. No viable para PoC académico.

### STP — Principal referencia para API SPEI

| Recurso | Link |
|---|---|
| STP APIs (página oficial) | https://stp.mx/en/apis/ |
| STP WADL (spec técnica) | https://demo.stpmex.com:7024/speiws/rest/application.wadl?metadata=true&detail=true |
| stpmex-python (Cuenca) | https://github.com/cuenca-mx/stpmex-python |
| PyPI stpmex | https://pypi.org/project/stpmex/ |
| STP Zendesk (soporte/docs) | https://stpmex.zendesk.com/hc/es |

### Campos de una orden SPEI (RegistraOrden vía STP)

| Campo | Tipo | Obligatorio | Descripción |
|---|---|---|---|
| `empresa` | string | Sí | Identificador de la empresa en STP |
| `claveRastreo` | string(30) | Sí | Clave alfanumérica de rastreo única |
| `conceptoPago` | string | Sí | Concepto/descripción del pago |
| `cuentaOrdenante` | string(18) | Sí | CLABE de la cuenta origen |
| `cuentaBeneficiario` | string(18) | Sí | CLABE de la cuenta destino |
| `institucionContraparte` | string(5) | Sí | Código de la institución destino (ej: 40072 = Banorte) |
| `monto` | decimal | Sí | Monto de la transferencia en MXN |
| `nombreBeneficiario` | string | Sí | Nombre del beneficiario |
| `nombreOrdenante` | string | No | Nombre del ordenante |
| `rfcCurpBeneficiario` | string | No | RFC o CURP del beneficiario |
| `rfcCurpOrdenante` | string | No | RFC o CURP del ordenante |
| `tipoCuentaBeneficiario` | string | No | Tipo de cuenta (40 = CLABE, 3 = tarjeta débito, 10 = celular) |
| `tipoPago` | string | No | Tipo de pago |
| `referenciaNumerica` | string(7) | No | Referencia numérica definida por el usuario |

### Payload de referencia — RegistraOrden SPEI

**Request (basado en stpmex-python):**

```json
{
  "empresa": "MIPIT_POC",
  "claveRastreo": "CR20260301ABC123",
  "conceptoPago": "Pago de servicios",
  "cuentaOrdenante": "646180110400000007",
  "cuentaBeneficiario": "072691004495711499",
  "institucionContraparte": "40072",
  "monto": 1500.00,
  "nombreBeneficiario": "Ricardo Sanchez",
  "nombreOrdenante": "Maria Lopez",
  "rfcCurpBeneficiario": "SACR850101HDFLPS01",
  "tipoCuentaBeneficiario": "40",
  "referenciaNumerica": "1234567"
}
```

**Response (éxito):**

```json
{
  "resultado": {
    "id": 12345678,
    "descripcionError": "",
    "claveRastreo": "CR20260301ABC123"
  }
}
```

### Validación de CLABE (18 dígitos)

| Posición | Significado | Ejemplo |
|---|---|---|
| 1-3 | Código de banco | `072` (Banorte) |
| 4-6 | Código de plaza | `691` |
| 7-17 | Número de cuenta | `00449571149` |
| 18 | Dígito verificador | `9` |

### Consulta por clave de rastreo

```python
orden = client.ordenes.consulta_clave_rastreo(
    claveRastreo='CR1234567890',
    institucionOperante=90646,
    fechaOperacion=dt.date(2026, 3, 1)
)
```

### Proveedores con documentación SPEI útil

| Proveedor | Link | Notas |
|---|---|---|
| EBANX | https://ebanx.github.io/dev-academy/docs/payments/guides/accept-payments/api/mexico/spei/ | Sandbox: `https://sandbox.ebanx.com/ws/direct` |
| Mercado Pago | https://www.mercadopago.com.mx/developers/es/docs/checkout-api-orders/payment-integration/spei-transfers | Integración SPEI con sandbox |
| Apitude (validación CEP) | https://apitude.co/es/docs/services/banxico-spei-mx/ | Valida transferencias contra DB Banxico |
| Mith (guía conexión 2026) | https://mith.mx/blog/conexion-spei-banxico-requisitos-proceso-costos-2026 | Requisitos actualizados 2026 |
| Mith (sin ser banco) | https://mith.mx/blog/formas-conectarse-spei-sin-ser-banco-2026 | Alternativas para fintechs |
| Conecta (guía SPEI 2025) | https://conecta.mx/blog/guia-completa-del-spei-en-2025-como-funciona-requisitos-y-retos/ | Guía completa con campos |

---

## Justificación de mock servers para la tesis

### Por qué usamos mocks en lugar de sandboxes reales

1. **PIX**: El sandbox oficial del BCB (`qr-h.sandbox.pix.bcb.gov.br`) solo es accesible para Participantes Diretos — instituciones financieras autorizadas. El proceso de adesión tiene 3 etapas (cadastral, homologatória, operação restrita) y requiere solidez financiera y conformidade regulatória (Resolução BCB nº 429/2024).

2. **SPEI**: Requiere autorización escrita de Banxico, infraestructura dedicada (HSM con certificación CISA/CISSP/ISO 27001, data center Tier III con 99.98% uptime, enlaces privados). Participación directa toma 12-18 meses. Incluso la vía más rápida (modelo híbrido con agregador) requiere 1-2 meses y relación contractual con un banco.

3. **Ninguno** ofrece un sandbox público tipo "regístrate y prueba" como Stripe, PayPal o Mercado Pago. Son sistemas interbancarios cerrados de bancos centrales.

### Cómo nuestros mocks replican el comportamiento real

- **PIX mock**: Implementa los endpoints `/v2/cob` y `/v2/pix/{e2eid}` con los schemas exactos del OpenAPI del BCB. Valida tipos de chave (CPF, CNPJ, email, telefone, EVP). Simula transiciones de status (ATIVA → CONCLUIDA / EXPIRADA). Genera endToEndId con formato estándar.

- **SPEI mock**: Implementa RegistraOrden con los campos de STP. Valida CLABE de 18 dígitos (banco + plaza + cuenta + dígito verificador). Genera claveRastreo. Simula respuestas de éxito y error con los códigos documentados.

- **Tasas de error simuladas**: Ambos mocks incluyen configuración para simular fallos (timeout, rechazo, error de validación) con tasas configurables para pruebas de resiliencia.

### Extensibilidad a producción

Para conectar con rieles reales, solo cambiar variables de entorno:
- `PIX_SANDBOX_URL` → URL del PSP real (ej: Efí Pay, Stone, PicPay)
- `SPEI_SANDBOX_URL` → URL de STP o banco corresponsal

La interfaz del adaptador (`client.ts`) no cambia; solo la URL base y las credenciales de autenticación.

### Referencias para citar en la tesis

- BCB. "API Pix." GitHub, v2.9.0, 2025. https://github.com/bacen/pix-api
- BCB. "API DICT." v2.X.0-RC4. https://www.bcb.gov.br/content/estabilidadefinanceira/pix/API-DICT-MED-2.0.html
- BCB. "Manual de Padrões para Iniciação do Pix." v2.9.0. https://www.bcb.gov.br/content/estabilidadefinanceira/pix/Regulamento_Pix/II_ManualdePadroesparaIniciacaodoPix.pdf
- Banxico. "Circular 14/2017 — Normas internas del SPEI." https://www.banxico.org.mx/marco-normativo/
- Banxico. "Manual de Operación del SPEI." v5.4. https://www.banxico.org.mx/sistemas-de-pago/
- STP. "APIs — Sistema de Transferencias y Pagos." https://stp.mx/en/apis/
- Cuenca. "stpmex-python." GitHub. https://github.com/cuenca-mx/stpmex-python

---

*Documento de referencia para Semanas 9 (adaptadores), 11 (E2E testing) y 16 (documentación).*

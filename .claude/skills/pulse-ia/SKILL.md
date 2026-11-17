---
name: pulse-ia
description: Gera o painel HTML "Pulse IA" com as notícias e pesquisas recentes de inteligência artificial (arXiv cs.AI + VentureBeat AI), traduzidas para português. Use quando o usuário pedir "resumo rápido de IA", "atualizações recentes", "o que mudou em IA", "pulse ia", novidades/notícias de IA do dia, ou o mesmo para uma data específica (ex.: "o que mudou em IA em 15-03-2025").
---

# Pulse IA — painel de monitoramento de IA

Gera `pulse-ia.html` (um único arquivo, atualizado a cada execução) na **pasta conectada** (diretório de trabalho atual da sessão) e abre no navegador.

Os scripts ficam em `scripts/` dentro do diretório desta skill (`<SKILL_DIR>` abaixo). O ambiente é Windows PowerShell 5.1, então rode sempre com:
`powershell -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>\scripts\<script>.ps1" ...`

## Fluxo

### 1. Entender o pedido
- Sem data → modo **recentes** (hoje).
- Com data (qualquer formato: "15/03/2025", "ontem", "15 de março") → converta para `DD-MM-AAAA`, modo **data**.
- Anuncie no terminal em uma linha o que vai fazer (ex.: "Pulse IA: coletando arXiv e VentureBeat para 17-11-2026").

### 2. Coletar (script com logs)
```
powershell -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>\scripts\fetch.ps1" [-Date DD-MM-AAAA]
```
O script imprime logs `[pulse-ia] [INFO|OK|WARN|ERRO]`, nunca para se uma fonte falhar e termina com `RAW_JSON=<caminho>`. Leia esse JSON (`arxiv[]`, `venturebeat[]`, `sources[]`).

### 3. Fallbacks (continuar mesmo com falha)
- **VentureBeat com status `falhou`** (o site costuma bloquear scripts com 429/308): use `WebFetch` em `https://venturebeat.com/category/ai/` pedindo título, URL completa, data e resumo de cada artigo. Se funcionar, marque a fonte como `fallback` com nota "via WebFetch". Se também falhar, deixe `falhou` e siga só com arXiv.
- **arXiv com status `falhou`**: tente `WebFetch` em `https://arxiv.org/list/cs.AI/recent`. Se falhar, siga sem ele.
- **Modo data** e a data tem pouca ou nenhuma cobertura nas duas fontes (comum para datas antigas, já que o feed/listagem só mostra itens recentes): complemente com `WebSearch` (ex.: `"AI news" <mês dia ano>`, `site:venturebeat.com AI <mês ano>`). Nesse modo **outras fontes confiáveis são permitidas** (ex.: The Verge, TechCrunch, Reuters, blogs oficiais de OpenAI/Google/Anthropic/Meta), dando preferência a 2025 em diante quando a data pedida for de até ~1 ano atrás. Adicione cada fonte extra em `sources` com status `ok` e nota "complementar".
- Sempre informe no terminal qual fallback foi usado e por quê.
- Fora do modo data, use **apenas** arXiv e VentureBeat.

### 4. Curar e traduzir
Escolha o que importa para quem **cria produtos de IA**. Foco:
- novas tecnologias/modelos e capacidades;
- movimentações de empresas (lançamentos, preços, aquisições, rodadas, mudanças de liderança);
- tendências relevantes;
- atualizações importantes para construção de produtos (APIs, custos, agentes, segurança, avaliação).

Regras de curadoria:
- **Ignore conteúdo patrocinado** ("sponsored", "presented by", "in partnership with") e itens fora da data pedida (no modo recentes, priorize os últimos ~7 dias; descarte o que for mais antigo que 14 dias).
- `top`: 4 a 7 itens, os mais relevantes primeiro (o 1º vira o card de destaque). Misture VentureBeat e os melhores papers do arXiv (no máximo 2 papers no top, escolhendo os de aplicação prática).
- `secondary`: 8 a 15 itens em lista compacta (notícias restantes + papers notáveis).
- Tudo em **português do Brasil**: `title` traduzido, `title_original` em inglês; `summary` com 1–2 frases curtas em PT; `why` em uma frase sobre o impacto para quem cria produtos. Não invente fatos além do que a fonte diz; nomes de produtos/modelos ficam no original.
- `tag`: uma palavra ou duas — ex.: Modelo, Agentes, Empresa, Pesquisa, Infra, Segurança, Produto, Preço, Mercado.
- `date` no formato `DD/MM`.
- `headline`: uma frase-manchete do dia; `summary`: 2–3 frases resumindo o panorama; `trends`: 3–5 tendências curtas.

Escreva o JSON curado (UTF-8) em `%TEMP%\pulse-ia\content-DD-MM-AAAA.json` com este formato:
```json
{
  "date": "17-11-2026",
  "mode": "recent",
  "headline": "Frase-manchete do dia",
  "summary": "Resumo de 2-3 frases do panorama.",
  "trends": ["Agentes em produção", "Guerra de preços de modelos"],
  "top": [
    {"title": "Título em PT", "title_original": "Original title", "summary": "Resumo curto em PT.",
     "why": "Impacto para quem cria produtos.", "tag": "Modelo", "source": "VentureBeat",
     "date": "17/11", "url": "https://..."}
  ],
  "secondary": [
    {"title": "Título em PT", "title_original": "Original title", "tag": "Pesquisa",
     "source": "arXiv", "date": "16/11", "url": "https://...", "note": "opcional: 1 linha de contexto"}
  ],
  "sources": [
    {"name": "arXiv cs.AI", "url": "https://arxiv.org/list/cs.AI/recent", "status": "ok", "note": ""},
    {"name": "VentureBeat AI", "url": "https://venturebeat.com/category/ai/", "status": "fallback", "note": "via WebFetch"}
  ]
}
```
`status` aceita `ok`, `fallback` ou `falhou`. Use o `sources` do JSON bruto como base, atualizado com os fallbacks.

### 5. Renderizar, salvar e abrir
```
powershell -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>\scripts\render.ps1" -Content "<content.json>" -OutDir "<diretório de trabalho atual>"
```
O script salva na pasta indicada (a pasta conectada), abre no navegador padrão e imprime `HTML=<caminho>`:
- **Modo recentes:** sempre o mesmo arquivo, `pulse-ia.html`, sobrescrito a cada execução (não se acumulam arquivos por dia).
- **Modo data:** `pulse-ia-DD-MM-AAAA.html` (pedido avulso, não substitui o painel diário).
O histórico datado fica só no GitHub (`historico/`). Em execução agendada (sem ninguém olhando), acrescente `-NoOpen`.

### 5b. Atualizar o link compartilhável (GitHub Pages)
O link público é hospedado no GitHub Pages (não use o claude.ai para compartilhar). Envie o HTML gerado:
```
powershell -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>\scripts\publish-github.ps1" -Html "<caminho HTML=>"
```
- **Modo recentes:** atualiza `index.html` (o link fixo) e guarda uma cópia em `historico/`.
- **Modo data:** acrescente `-NoIndex` para salvar só em `historico/` sem trocar o painel do dia.
- O script lê `config.json` (dono/repositório) e o token da variável de ambiente `PULSE_GH_TOKEN`. Nunca peça, mostre nem grave o token.
- Ele imprime `SITE_URL=` (link fixo) e `HISTORY_URL=`. Se falhar (sem token, sem config, erro de rede), registre no terminal e siga: o arquivo local continua valendo.

### 6. Responder
Em poucas linhas: caminho do arquivo (link markdown relativo), link do GitHub Pages (se atualizado), manchete do dia, quantos destaques/itens no radar e quais fontes falharam ou usaram fallback.

## Design (já implementado em render.ps1 — não alterar sem pedido)
- Fundo `#fffdf7`, texto `#2b2d42`, roxo suave `#6d597a`, amarelo suave `#f2cc8f`.
- Fontes Google: Fraunces (títulos), Instrument Sans (texto), Space Grotesk (metadados).
- Topo: título com data + resumo do dia + tendências. Bloco 1: cards grandes (Principais notícias). Bloco 2: lista compacta (Radar). Rodapé: data de geração + fontes com status.
- Cada card/linha abre o link original em nova aba; botão "Ver original (EN)" alterna os títulos/resumos para o inglês; layout responsivo (3 → 2 → 1 coluna).

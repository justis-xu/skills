---
name: baoyu-translate
description: >-
  This skill should be used when the user asks to "translate", "翻译", "精翻", "translate article",
  "translate to Chinese", "translate to English", "改成中文", "改成英文", "convert to Chinese",
  "localize", "本地化", "refined translation", "精细翻译", "proofread translation", "快速翻译", "快翻",
  "这篇文章翻译一下", or provides a URL/file with translation intent. Supports three modes
  (quick/normal/refined) with custom glossary support.
version: 1.59.0
metadata:
  openclaw:
    homepage: https://github.com/JimLiu/baoyu-skills#baoyu-translate
    requires:
      anyBins:
        - bun
        - npx
---

> **安装**：`npx skills@latest add jimliu/baoyu-skills --skill baoyu-translate`
>
> **词汇表优先级**：EXTEND.md（用户配置）> `references/translate/glossary.md`（本项目）> baoyu-translate 内置词汇表。

# Translator

Three-mode translation skill: **quick** for direct translation, **normal** for analysis-informed translation, **refined** for full publication-quality workflow with review and polish.

## User Input Tools

When this skill prompts the user, follow this tool-selection rule (priority order):

1. **Prefer built-in user-input tools** exposed by the current agent runtime — e.g., `AskUserQuestion`, `request_user_input`, `clarify`, `ask_user`, or any equivalent.
2. **Fallback**: if no such tool exists, emit a numbered plain-text message and ask the user to reply with the chosen number/answer for each question.
3. **Batching**: if the tool supports multiple questions per call, combine all applicable questions into a single call; if only single-question, ask them one at a time in priority order.

Concrete `AskUserQuestion` references below are examples — substitute the local equivalent in other runtimes.

## Script Directory

Scripts in `scripts/` subdirectory. `{baseDir}` = this SKILL.md's directory path. Resolve `${BUN_X}` runtime: if `bun` installed → `bun`; if `npx` available → `npx -y bun`; else suggest installing bun. Replace `{baseDir}` and `${BUN_X}` with actual values.

| Script | Purpose |
|--------|---------|
| `scripts/main.ts` | CLI entry point. Default action splits markdown into chunks; also supports explicit `chunk` subcommand |
| `scripts/chunk.ts` | Markdown chunking implementation used by `main.ts` and kept compatible for direct invocation |

## Preferences (EXTEND.md)

Check EXTEND.md in priority order — the first one found wins:

| Priority | Path | Scope |
|----------|------|-------|
| 1 | `.baoyu-skills/baoyu-translate/EXTEND.md` | Project |
| 2 | `${XDG_CONFIG_HOME:-$HOME/.config}/baoyu-skills/baoyu-translate/EXTEND.md` | XDG |
| 3 | `$HOME/.baoyu-skills/baoyu-translate/EXTEND.md` | User home |

| Result | Action |
|--------|--------|
| Found | Read, parse, apply. On first use in session, briefly remind: "Using preferences from [path]. You can edit EXTEND.md to customize glossary, audience, etc." |
| Not found | **MUST** run first-time setup (see below) — do NOT silently use defaults |

**EXTEND.md supports**: default target language, default mode, target audience, custom glossaries (inline or file path), translation style, chunk settings.

### First-Time Setup (BLOCKING)

**CRITICAL**: When EXTEND.md is not found, you **MUST** run the first-time setup before ANY translation. This is a **BLOCKING** operation.

Use `AskUserQuestion` with all questions (target language, mode, audience, style, save location) in ONE call. After user answers, create EXTEND.md at the chosen location, confirm "Preferences saved to [path]", then continue.

## Defaults

All configurable values in one place. EXTEND.md overrides these; CLI flags override EXTEND.md.

| Setting | Default | EXTEND.md key | CLI flag | Description |
|---------|---------|---------------|----------|-------------|
| Target language | `zh-CN` | `target_language` | `--to` | Translation target language |
| Mode | `normal` | `default_mode` | `--mode` | Translation mode |
| Audience | `general` | `audience` | `--audience` | Target reader profile |
| Style | `storytelling` | `style` | `--style` | Translation style preference |
| Chunk threshold | `4000` | `chunk_threshold` | — | Word count to trigger chunked translation |
| Chunk max words | `5000` | `chunk_max_words` | — | Max words per chunk |

## Modes

| Mode | Flag | Steps | When to Use |
|------|------|-------|-------------|
| Quick | `--mode quick` | Translate | Short texts, informal content, quick tasks |
| Normal | `--mode normal` (default) | Analyze → Translate | Articles, blog posts, general content |
| Refined | `--mode refined` | Analyze → Translate → Review → Polish | Publication-quality, important documents |

**Default mode**: Normal (can be overridden in EXTEND.md `default_mode` setting).

**Style presets** — control the voice and tone of the translation (independent of audience):

| Value | Description | Effect |
|-------|-------------|--------|
| `storytelling` | Engaging narrative flow (default) | Draws readers in, smooth transitions, vivid phrasing |
| `formal` | Professional, structured | Neutral tone, clear organization, no colloquialisms |
| `technical` | Precise, documentation-style | Concise, terminology-heavy, minimal embellishment |
| `literal` | Close to original structure | Minimal restructuring, preserves source sentence patterns |
| `academic` | Scholarly, rigorous | Formal register, complex clauses OK, citation-aware |
| `business` | Concise, results-focused | Action-oriented, executive-friendly, bullet-point mindset |
| `humorous` | Preserves and adapts humor | Witty, playful, recreates comedic effect in target language |
| `conversational` | Casual, spoken-like | Friendly, approachable, as if explaining to a friend |
| `elegant` | Literary, polished prose | Aesthetically refined, rhythmic, carefully crafted word choices |

Custom style descriptions are also accepted, e.g., `--style "poetic and lyrical"`.

**Auto-detection**:
- "快翻", "quick", "直接翻译" → quick mode
- "精翻", "refined", "publication quality", "proofread" → refined mode
- Otherwise → default mode (normal)

**Upgrade prompt**: After normal mode completes, display:
> Translation saved. To further review and polish, reply "继续润色" or "refine".

If user responds, continue with review → polish steps (same as refined mode Steps 4-6 in refined-workflow.md) on the existing output.

**Audience presets**:

| Value | Description | Effect |
|-------|-------------|--------|
| `general` | General readers (default) | Plain language, more translator's notes for jargon |
| `technical` | Developers / engineers | Less annotation on common tech terms |
| `academic` | Researchers / scholars | Formal register, precise terminology |
| `business` | Business professionals | Business-friendly tone, explain tech concepts |

Custom audience descriptions are also accepted, e.g., `--audience "AI感兴趣的普通读者"`.

## Workflow

### Step 1: Load Preferences

1.1 Check EXTEND.md (see Preferences section above)

1.2 Load built-in glossary for the language pair if available:
- EN→ZH: built-in glossary-en-zh

1.3 Merge glossaries (priority order):
1. EXTEND.md `glossary` / `glossary_files`（用户配置，最高优先级）
2. `references/translate/glossary.md`（本项目词汇表）
3. 内置词汇表

### Step 2: Materialize Source & Create Output Directory

Materialize source (file as-is, inline text/URL → save to `translate/{slug}.md`), then create output directory: `{source-dir}/{source-basename}-{target-lang}/`. Detect source language if `--from` not specified.

**Output directory contents** (all intermediate and final files go here):

| File | Mode | Description |
|------|------|-------------|
| `translation.md` | All | Final translation (always this name) |
| `01-analysis.md` | Normal, Refined | Content analysis (domain, tone, terminology) |
| `02-prompt.md` | Normal, Refined | Assembled translation prompt |
| `03-draft.md` | Refined | Initial draft before review |
| `04-critique.md` | Refined | Critical review findings (diagnosis only) |
| `05-revision.md` | Refined | Revised translation based on critique |
| `chunks/` | Chunked | Source chunks + translated chunks |

### Step 3: Assess Content Length

Quick mode does not chunk — translate directly regardless of length. Before translating, estimate word count. If content exceeds chunk threshold (default 4000 words), proactively warn: "This article is ~{N} words. Quick mode translates in one pass without chunking — for long content, `--mode normal` produces better results with terminology consistency." Then proceed if user doesn't switch.

For normal and refined modes:

| Content | Action |
|---------|--------|
| < chunk threshold | Translate as single unit |
| >= chunk threshold | Chunk translation (see Step 3.1) |

**3.1 Long Content Preparation** (normal/refined modes, >= chunk threshold only)

Before translating chunks:

1. **Extract terminology**: Scan entire document for proper nouns, technical terms, recurring phrases
2. **Build session glossary**: Merge extracted terms with loaded glossaries, establish consistent translations
3. **Split into chunks**: Use `${BUN_X} {baseDir}/scripts/main.ts <file> [--max-words <chunk_max_words>] [--output-dir <output-dir>]`
4. **Assemble translation prompt**: Save as `02-prompt.md` (shared context only, no task instructions)
5. **Draft translation via subagents** (if Agent tool available): Spawn one subagent per chunk in parallel
6. **Merge**: Combine translated chunks in order → `03-draft.md` (refined) or `translation.md` (normal)
7. All intermediate files preserved in `chunks/`

### Step 4: Translate & Refine

**Translation principles** (apply to all modes):

- **Rewrite, not translate**: Rewrite content into natural, engaging target language as if a skilled native writer composed it from scratch. Quality test: "Does this read like it was originally written in the target language?"
- **Accuracy first**: Facts, data, and logic must match the original exactly
- **Natural flow**: Use idiomatic target language word order. Break long source sentences into shorter, natural ones. Interpret metaphors and idioms by intended meaning, not word-for-word
- **Terminology**: Use standard translations consistently. First occurrence of specialized terms: annotate with original in parentheses
- **Preserve format**: Keep all markdown formatting (headings, bold, italic, images, links, code blocks)
- **Proactive interpretation**: For jargon or concepts the target audience may lack context for, add concise explanations in **bold parentheses** `（**解释**）`. Keep annotations few — only where genuinely needed for comprehension

#### Quick Mode

Translate directly → save to `translation.md`. Apply all translation principles above.

#### Normal Mode

1. **Analyze** → `01-analysis.md` (domain, tone, terminology, translation challenges)
2. **Assemble prompt** → `02-prompt.md` (translation instructions with context, glossary, challenges)
3. **Translate** (following `02-prompt.md`) → `translation.md`

After completion, prompt user: "Translation saved. To further review and polish, reply **继续润色** or **refine**."

#### Refined Mode

Steps and saved files (all in output directory):
1. **Analyze** → `01-analysis.md`
2. **Assemble prompt** → `02-prompt.md`
3. **Draft** → `03-draft.md`
4. **Critical review** → `04-critique.md` (diagnosis only: accuracy, Europeanized language, strategy execution, expression issues)
5. **Revision** → `05-revision.md`
6. **Polish** → `translation.md`

Each step reads the previous step's file and builds on it.

### Step 5: Output

Final translation is always at `translation.md` in the output directory.

Display summary:
```
**Translation complete** ({mode} mode)

Source: {source-path}
Languages: {from} → {to}
Output dir: {output-dir}/
Final: {output-dir}/translation.md
Glossary terms applied: {count}
```

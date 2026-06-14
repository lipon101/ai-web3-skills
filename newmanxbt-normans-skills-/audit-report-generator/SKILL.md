---
name: audit-report-generator
description: Generate professional PDF audit reports from markdown findings. Use when converting security audit findings to formal PDF reports, creating audit deliverables, or formatting vulnerability assessments. Triggers on requests to "generate audit report", "create PDF report", "format findings as PDF", or any audit report generation task.
---

# Audit Report Generator

## Overview

This skill transforms security audit findings written in markdown into professional PDF audit reports using pandoc and the eisvogel LaTeX template. It produces polished, publication-ready deliverables suitable for client delivery.

## Pre-Ask Questions (Required)

**IMPORTANT**: Before generating any report, you MUST ask the user these questions using AskUserQuestion tool:

1. **Company/Firm Name**: What is your company or firm name?
   - First time: Ask and save the answer as default for all future reports
   - Subsequent reports: Use saved default, but allow user to override
   - If no preference: "Independent Security Researcher"

2. **Client/Protocol Name**: What is the name of the protocol being audited?
   - Example: "Uniswap"

3. **Report Title**: What should the report title be?
   - Default: "[Protocol Name] Security Audit Report"

Store the company name preference so it becomes the default option for future audit reports in this project.

## Prerequisites

Before generating reports, ensure these dependencies are installed:

```bash
# Install pandoc (markdown to PDF converter)
brew install pandoc

# Install LaTeX (required for PDF compilation)
brew install --cask mactex-no-gui
# OR for a lighter installation:
brew install basictex

# After installing basictex, you may need:
sudo tlmgr update --self
sudo tlmgr install footnotebackref titling
```

Verify installation:
```bash
pandoc --version
pdflatex --version
```

## Quick Start Workflow

### 1. Prepare Your Markdown Report

Create a markdown file following the report structure (see `references/report-structure.md`). The file must include:

- YAML frontmatter with title, author, and date
- LaTeX title page block
- Standard audit report sections

### 2. Generate the PDF

```bash
# Basic usage (output goes to same directory as input)
bash ~/.claude/skills/audit-report-generator/scripts/make-pdf.sh report.md

# Specify output location
bash ~/.claude/skills/audit-report-generator/scripts/make-pdf.sh report.md --out output/final-report.pdf

# Use custom logo
bash ~/.claude/skills/audit-report-generator/scripts/make-pdf.sh report.md --logo /path/to/client-logo.pdf
```

## Input Format Specification

### YAML Frontmatter

Every report must begin with:

```yaml
---
title: Protocol Audit Report
author: Your Firm Name
date: October 17, 2024
header-includes:
  - \usepackage{titling}
  - \usepackage{graphicx}
---
```

### Title Page

Include the LaTeX title page after the frontmatter:

```latex
\begin{titlepage}
    \centering
    \begin{figure}[h]
        \centering
        \includegraphics[width=0.5\textwidth]{logo.pdf}
    \end{figure}
    \vspace*{2cm}
    {\Huge\bfseries Protocol Audit Report\par}
    \vspace{1cm}
    {\Large Version 1.0\par}
    \vspace{2cm}
    {\Large\itshape Your Firm Name\par}
    \vfill
    {\large \today\par}
\end{titlepage}

\maketitle
```

### Finding Format

Each vulnerability finding should follow the layout in `references/finding-layout.md`:

```markdown
### [M-1] Unchecked return value allows silent transfer failures

**Description**

[Technical description of the vulnerability]

**Impact**

[Consequences if exploited]

**Proof of Concepts**

[Code or steps to reproduce]

**Recommended mitigation**

[How to fix it]
```

Severity prefixes: `C-#` (Critical), `H-#` (High), `M-#` (Medium), `L-#` (Low), `I-#` (Informational), `G-#` (Gas)

## Script Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `<input.md>` | Source markdown file (required) | - |
| `--out <path>` | Output PDF path | `<input>.pdf` |
| `--logo <path>` | Logo PDF for title page | Required if report uses logo |
| `--template <path>` | Custom LaTeX template | Bundled `assets/eisvogel.latex` |

## Useful LaTeX in Markdown

| Command | Purpose |
|---------|---------|
| `\newpage` | Force page break |
| `\vspace{1cm}` | Add vertical space |
| `\textbf{text}` | Bold text |

## Troubleshooting

### "pdflatex not found"
Install LaTeX: `brew install --cask mactex-no-gui`

### "footnotebackref.sty not found"
Install the package: `sudo tlmgr install footnotebackref`

### Logo not appearing
- Ensure logo is PDF format (not PNG/JPG)
- Check the `logo.pdf` path is accessible from the markdown file's directory

## Resources

### scripts/
- `make-pdf.sh` - Main PDF generation script

### assets/
- `eisvogel.latex` - LaTeX template (professional formatting)

### references/
- `finding-layout.md` - Template for individual findings
- `report-structure.md` - Complete report structure guide

# Audit Report Structure Template

This template defines the complete structure for a professional security audit report.

## YAML Frontmatter

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

## Title Page (LaTeX)

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

## Required Sections

### 1. Table of Contents

```markdown
# Table of Contents
- [Table of Contents](#table-of-contents)
- [About Your Firm](#about-your-firm)
- [Disclaimer](#disclaimer)
- [Risk Classification](#risk-classification)
- [Protocol Overview](#protocol-overview)
- [Audit Scope](#audit-scope)
- [Executive Summary](#executive-summary)
    - [Summary](#summary)
    - [Issues Found](#issues-found)
    - [Summary of Findings](#summary-of-findings)
- [Findings](#findings)
  - [Critical](#critical)
  - [High](#high)
  - [Medium](#medium)
  - [Low](#low)
  - [Informational](#informational)
  - [Gas](#gas)
```

### 2. About Section

Describe your firm's expertise and track record.

### 3. Disclaimer

Standard legal disclaimer about audit scope and limitations.

### 4. Risk Classification Matrix

```markdown
|                | Impact: High | Impact: Medium | Impact: Low |
|----------------|--------------|----------------|-------------|
| Likelihood: High   | Critical     | High           | Medium      |
| Likelihood: Medium | High         | Medium         | Low         |
| Likelihood: Low    | Medium       | Low            | Low         |
```

### 5. Protocol Overview

Describe the protocol's purpose, key features, and architecture.

### 6. Audit Scope

List the files and commit hash included in the audit.

### 7. Executive Summary

#### Summary Table

```markdown
| Project Name  | [Protocol Name]                 |
|---------------|---------------------------------|
| Repository    | [Link to repo](#)               |
| Commit        | [Commit hash](#)                |
| Audit Timeline| [Date range]                    |
| Methods       | Manual Review, Stateful Fuzzing |
```

#### Issues Found Table

```markdown
|               | Count |
|---------------|-------|
| Critical Risk | 0     |
| High Risk     | 0     |
| Medium Risk   | 0     |
| Low Risk      | 0     |
| Informational | 0     |
| Gas Optimizations | 0 |
| **Total Issues** | **0** |
```

#### Summary of Findings Table

```markdown
| ID   | Description                      | Status     |
|------|----------------------------------|------------|
| [M-1](#m-1) | Brief description      | Resolved   |
| [I-1](#i-1) | Brief description      | Acknowledged |
```

### 8. Findings Sections

Each severity level gets its own section:

```markdown
\newpage

# Findings
## Critical
## High
## Medium
## Low
## Informational
## Gas
```

Use `\newpage` for page breaks between major sections.

## Useful LaTeX Commands

| Command | Purpose |
|---------|---------|
| `\newpage` | Force page break |
| `\vspace{1cm}` | Add vertical space |
| `\textbf{text}` | Bold text |
| `\textit{text}` | Italic text |
| `\begin{itemize}...\end{itemize}` | Bullet list |

## Complete Example

See the skill's test files for a complete working example.

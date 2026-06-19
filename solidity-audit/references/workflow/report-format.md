# Report Format

## Final Report Sections

The final report should contain these sections in order:

1. `Security Review — <Project>`
2. `Scope`
3. `Module Map`
4. `Findings`
5. `Findings List`
6. `Module Conclusions`
7. `Residual Risks`
8. `Disclaimer`

## Scope

Include:

- mode
- reviewed files
- reviewed contracts
- discovered modules
- labels used

## Module Map

For each module include:

- `module_id`
- core contracts
- all included contracts
- labels present

## Finding Fields

Every finding should render:

- confidence marker
- numbered title
- module id
- labels
- location
- confidence
- severity
- broken invariant
- description
- fix, if confidence is above threshold

## Confidence Threshold

Default threshold: `75`

Below threshold:

- keep the finding in the report
- omit the fix section

## Module Conclusions

For each module include:

- labels present
- core contracts
- primary risks
- coverage note
- conclusion

## Residual Risks

Call out:

- important assumptions
- incomplete protocol documentation
- external dependencies not fully reviewed
- cross-module edges with limited visibility

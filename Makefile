# Codebase Review Pipeline (Make + ask)
# Run with parallelism: `make -j`

ASK := ./ask
SRC := codebase.txt

# --- Role prompts ---
QUALITY_ROLE := You are an engineer who will inherit this module after the original author leaves. You care about whether you can read, debug, and change this code six months from now. Be specific. Avoid generic advice.
PERF_ROLE    := You are a performance engineer who profiles this service in production. You care about wasted CPU, memory, and I/O per request. Ignore style and security concerns -- those are handled elsewhere.
SEC_ROLE     := You are a security reviewer auditing this code before a third-party penetration test. You think in terms of concrete attack vectors and exploitability.
SUM_ROLE    := You are a review editor who cuts review findings down to the items most worth a developer reading. You delete noise without remorse.
REFINE_ROLE := You are an engineering lead consolidating three independent reviews into a single report for sprint planning. You remove overlap and surface root causes, not symptoms.
PLAN_ROLE   := You are a delivery lead turning a consolidated review into a sprint-ready action list that engineers can pick up and start working on immediately.

# --- Task prompts ---
QUALITY_TASK := Read the code that follows and find every place where naming is misleading, control flow is hard to follow, error handling is missing, or logic is duplicated. Write 5 to 7 bullets. Each bullet must (a) name the exact function or line in the code, and (b) state the concrete fix. Format every bullet as: - <location>: <problem> -> <fix>. Output bullets only -- no preamble, no headings, no closing remarks.
PERF_TASK := Read the code that follows and find every place that wastes CPU, memory, or I/O. Pay attention to: connections opened per request instead of pooled, missing pagination or limits, blocking I/O on hot paths, repeated work that could be cached, and unindexed queries. Write 5 to 7 bullets. Each bullet must (a) name the exact bottleneck and where it lives, and (b) give the concrete optimization. Format every bullet as: - <location>: <issue> -> <optimization>. Output bullets only -- no preamble, no headings, no closing remarks.
SEC_TASK := Read the code that follows and identify every exploitable weakness. Consider injection, authentication and authorization gaps, unsafe defaults, secret or internal exposure, unvalidated input, and insecure transport. Write 5 to 7 bullets. Each bullet must name the vulnerability class, the exact location in the code, and the concrete mitigation. Format every bullet as: - <location>: <risk> -> <mitigation>. Output bullets only -- no preamble, no headings, no closing remarks.
SUM_TASK := Compress the bullet list that follows into EXACTLY 5 bullets. Keep only the highest-impact, directly actionable items. Drop anything vague, low-severity, or stylistic. Preserve the arrow format "<location>: X -> Y" from the input. Output 5 bullets only -- no preamble, no headings.
REFINE_TASK := The input that follows contains three sections under the level-2 markdown headings \#\# Code Quality, \#\# Performance, and \#\# Security. Rewrite the report with these rules: (1) preserve those three headings exactly; (2) if a finding appears in more than one section, keep it in the single section where it has the most leverage and drop it from the others; (3) collapse symptoms into the underlying root cause; (4) keep only high-signal, actionable items. Output the rewritten markdown only.
PLAN_TASK := The input that follows contains two parts: first the raw per-section summary report, then the cross-section refined report. Use both to produce a final markdown document whose top-level title is the level-1 heading \# Engineering Action Plan. Under it, list every action item. For each item give: a one-sentence task description, a Priority tag (High / Medium / Low), an Effort estimate (Small / Medium / Large), and a one-line rationale. Sort items so Priority High comes first. End the document with a level-2 heading \#\# Execution Order that lists the items in the order an engineer should tackle them, resolving dependencies first. Output markdown only, no preamble.

.PHONY: all clean
.DELETE_ON_ERROR:

all: action.plan.md

# --- Phase 1: FAN-OUT ---

quality.md: $(SRC) $(ASK)
	$(ASK) -s '$(QUALITY_ROLE)' '$(QUALITY_TASK)' < $(SRC) > $@

perf.md: $(SRC) $(ASK)
	$(ASK) -s '$(PERF_ROLE)' '$(PERF_TASK)' < $(SRC) > $@

security.md: $(SRC) $(ASK)
	$(ASK) -s '$(SEC_ROLE)' '$(SEC_TASK)' < $(SRC) > $@

# --- Phase 2: LOCAL SUMMARIZATION ---

quality.sum.md: quality.md $(ASK)
	$(ASK) -s '$(SUM_ROLE)' '$(SUM_TASK)' < $< > $@

perf.sum.md: perf.md $(ASK)
	$(ASK) -s '$(SUM_ROLE)' '$(SUM_TASK)' < $< > $@

security.sum.md: security.md $(ASK)
	$(ASK) -s '$(SUM_ROLE)' '$(SUM_TASK)' < $< > $@

# --- Phase 3: CONCAT REPORT (shell only, no LLM) ---

concatenated.md: quality.sum.md perf.sum.md security.sum.md
	{ \
	  echo '## Code Quality'; echo; cat quality.sum.md; echo; \
	  echo '## Performance';  echo; cat perf.sum.md;    echo; \
	  echo '## Security';     echo; cat security.sum.md; echo; \
	} > $@

# --- Phase 4: FAN-IN #1 (cross-section refinement) ---

refined.md: concatenated.md $(ASK)
	$(ASK) -s '$(REFINE_ROLE)' '$(REFINE_TASK)' < $< > $@

# --- Phase 5: FAN-IN #2 (final Engineering Action Plan) ---

action.plan.md: concatenated.md refined.md $(ASK)
	cat concatenated.md refined.md | $(ASK) -s '$(PLAN_ROLE)' '$(PLAN_TASK)' > $@

clean:
	rm -f quality.md perf.md security.md \
	      quality.sum.md perf.sum.md security.sum.md \
	      concatenated.md refined.md action.plan.md

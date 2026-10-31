TPC-DS on MariaDB -- editable report

This ZIP is a document package, separate from the course implementation ZIP.

To collaborate in Overleaf:
  1. Upload the generated TPCDS-Part-I-latex.zip as a new project.
  2. Select XeLaTeX as the compiler and main.tex as the main document.
  3. Fill in metadata.tex with the group members, student IDs and group number.
  4. Edit the report text in main.tex. Numeric tables are in generated/.

To compile the extracted package locally with installed TeX tools:
  xelatex -no-shell-escape main.tex
  bibtex main
  xelatex -no-shell-escape main.tex
  xelatex -no-shell-escape main.tex

To refresh measurements from the full implementation checkout:
  python3 -B scripts/build_latex_report.py --out submission/latex-review-02

The output directory must be new. This build requires installed XeLaTeX,
BibTeX and gnuplot and never runs Docker or SQL. It discovers complete
original/adopted SF1/SF2/SF3/SF4 runs at:
  results/check-original-sf<N>/tuned/
  results/sf<N>-all-tuned-v1/tuned/

Preserved experiments/evidence/docker_sf<N>_99/ bundles are used if the live
result directory is unavailable. All four scales have been exported this way.
The earlier SF4 original directory results/check-original/tuned/ is also supported.

Only complete, successful 99-query runs with verified answer artifacts are
included. The report tables contain completed measurements. A complete execution is separate from
whether its answers match. Configurations and missing metadata remain disclosed.
The old unsupported four-scale table is not used as experimental evidence.

generated/evidence.json identifies each input summary and configuration.
generated/campaign-statistics.json stores the derived totals, ratios and contributions.
generated/run-selection.tex records the selected AC-powered SF2/SF3 reruns.
Their previous adopted passes are retained under evidence/history/ in this ZIP
and history/pre-ac-rerun/ in the corresponding repository evidence folders.
generated/sf<N>-comparison.csv contains all 99 per-query times and answer statuses.
The raw comparison status is preserved. Q71 permutations within tied ordering
keys are recorded as a separate review only after checking the executed SQL,
full row values and both complete sort-key sequences.
evidence/ contains the complete input bundles, including executed SQL snapshots.
SOURCE-MANIFEST.json records hashes of the files originally packaged by the build.
Editing the extracted sources intentionally changes those original hashes.

TPC-EULA.txt accompanies the TPC-derived SQL in the evidence bundles.
The supplied Oracle/PostgreSQL example reports informed the structure and are
credited in the bibliography; their PDFs and results are not redistributed here.

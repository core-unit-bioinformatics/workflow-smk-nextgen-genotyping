#!/usr/bin/env python3
"""List rare SVs (by reference-panel allele frequency) that are homozygous in the cohort.

Inputs:
  * the merged multi-sample PanGenie VCF (after convert-to-biallelic; GT[:GQ] per sample),
    as a file or '-' for stdin;
  * the allele frequency of the reference panel, either
      - --panel-vcf: the panel VCF that was given to PanGenie (the reference callset); the AF
        is re-computed from its genotypes (the INFO/AF of the panel is not reliable) and the
        panel variants are matched to the cohort VCF via the panel's INFO/ID, or
      - --panel-table: the table of the workflow rule 'tabulate_pangenie_panel_variants'
        (proc/50-plotting/10_pangenie/pl_tab/<ref_callset>.panel-variants.tsv.gz), which
        contains the same information but only exists for runs with the plotting module.

Optional filters: --max-cohort-af, --min-gq. With --annotate (and --vep) the rows that
survive the filters are annotated with genes via the Ensembl REST API (needs internet
access).

With --annotate the columns genes (SYMBOL(biotype);...), overlaps_cds (yes/no) and, with --vep,
vep_most_severe / vep_canonical (Ensembl VEP with symbolic DEL/INS alleles, so only a rough
estimate for insertions) are inserted before full_variant_id.

A variant is reported if |len(ALT) - len(REF)| >= --sv-min-length, its panel AF is below
--max-panel-af and at least one cohort sample has the genotype 1/1. Low genotype
qualities are NOT filtered; the GQ is reported for every homozygous genotype so that
the list can be filtered afterwards.

Output (TSV, one row per homozygous sample genotype; variant_id is a short ID such as
chr1-597799-INS-376, the complete graph ID of the VCF is the last column):
  variant_id, chrom, start, end, sv_type, sv_length, panel_af, cohort_af, cohort_n_called,
  cohort_n_het, cohort_n_hom_alt, sample, gq, full_variant_id

To speed things up, the VCF can be pre-filtered to SVs (the script checks the length again):
  bcftools view -i 'ILEN<=-50 || ILEN>=50' merged.vcf.gz | rare_homozygous_svs.py - ...
"""

import argparse
import csv
import gzip
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

MAX_RETRIES = 5

HEADER = (
    "variant_id",
    "chrom",
    "start",
    "end",
    "sv_type",
    "sv_length",
    "panel_af",
    "cohort_af",
    "cohort_n_called",
    "cohort_n_het",
    "cohort_n_hom_alt",
    "sample",
    "gq",
    "full_variant_id",
)


def load_rare_panel_svs(path, sv_min_length, max_panel_af):
    """Return {variant ID: panel AF} of panel variants that are SVs and rarer than the cutoff."""
    rare = {}
    n_svs = 0
    with gzip.open(path, "rt", encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            if abs(int(row["ilen"])) < sv_min_length:
                continue
            n_svs += 1
            if row["af"] != "NA" and float(row["af"]) < max_panel_af:
                rare[row["id"]] = float(row["af"])
    print(
        f"panel: {n_svs} SVs, {len(rare)} with AF < {max_panel_af}",
        file=sys.stderr,
    )
    return rare


def log(message):
    """Print a message with a time stamp to stderr."""
    print(f"[{time.strftime('%H:%M:%S')}] {message}", file=sys.stderr, flush=True)


def info_value(info, key):
    """Return the value of an INFO key (None if the key is absent)."""
    prefix = key + "="
    for item in info.split(";"):
        if item.startswith(prefix):
            return item[len(prefix) :]
    return None


def load_rare_panel_svs_from_vcf(path, sv_min_length, max_panel_af):
    """Return {INFO/ID: panel AF} of panel SVs rarer than the cutoff, AF from the genotypes."""
    rare = {}
    n_svs = 0
    with open_vcf(path) as vcf:
        for line in vcf:
            if line.startswith("#"):
                continue
            fields = line.rstrip("\n").split("\t", 9)
            ref, alt = fields[3], fields[4]
            if "," in alt or abs(len(alt) - len(ref)) < sv_min_length:
                continue
            n_svs += 1
            var_id = info_value(fields[7], "ID")
            if var_id is None or len(fields) < 10:
                continue
            gt_index = fields[8].split(":").index("GT")
            n_called = n_alt = 0
            for sample_field in fields[9].split("\t"):
                alleles = genotype_alleles(sample_field.split(":")[gt_index])
                called = [allele for allele in alleles if allele != "."]
                n_called += len(called)
                n_alt += called.count("1")
            if n_called and n_alt / n_called < max_panel_af:
                rare[var_id] = n_alt / n_called
    print(
        f"panel VCF: {n_svs} SVs, {len(rare)} with AF < {max_panel_af}",
        file=sys.stderr,
    )
    return rare


def open_vcf(path):
    """Open a (gzipped) VCF for reading as text; '-' means stdin."""
    if path == "-":
        return sys.stdin
    opener = gzip.open if path.endswith(".gz") else open
    return opener(path, "rt", encoding="utf-8")


def genotype_alleles(genotype):
    """Return the list of allele strings of a GT field ('0/1' or '0|1' -> ['0', '1'])."""
    return genotype.replace("|", "/").split("/")


def fetch_json(url):
    """Return the parsed JSON of a GET request; retry rate limiting (429) and server errors."""
    request = urllib.request.Request(url, headers={"Content-Type": "application/json"})
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            retryable = error.code == 429 or error.code >= 500
            if not retryable or attempt == MAX_RETRIES:
                raise
            time.sleep(float(error.headers.get("Retry-After", 2 * attempt)))
        except (urllib.error.URLError, TimeoutError):
            if attempt == MAX_RETRIES:
                raise
            time.sleep(2 * attempt)
    raise RuntimeError("unreachable")


def safe_query(function, n_missing, *args):
    """Run a query; on a persistent error warn (with the URL) and return 'ERROR' values."""
    try:
        return function(*args)
    except (urllib.error.URLError, TimeoutError) as error:
        url = getattr(error, "url", "")
        print(f"WARNING: query failed for {args[1:]} ({error}) {url}", file=sys.stderr)
        return ("ERROR",) * n_missing


def query_region(server, chrom, start, end):
    """Return (genes string, overlaps_cds) for one region."""
    region = f"{chrom.removeprefix('chr')}:{start}-{end}"
    query = urllib.parse.urlencode(
        [("feature", "gene"), ("feature", "cds"), ("content-type", "application/json")]
    )
    features = fetch_json(f"{server}/overlap/region/human/{region}?{query}")
    genes = sorted(
        {
            f"{item.get('external_name') or item['id']}({item.get('biotype', 'NA')})"
            for item in features
            if item.get("feature_type") == "gene"
        }
    )
    has_cds = any(item.get("feature_type") == "cds" for item in features)
    return (";".join(genes) if genes else "."), ("yes" if has_cds else "no")


def vep_region(chrom, start, end, sv_type):
    """Return the VEP region string with a symbolic allele (the anchor base is excluded)."""
    name = chrom.removeprefix("chr")
    if sv_type == "deletion":
        return f"{name}:{int(start) + 1}-{end}:1/DEL"
    if sv_type == "insertion":
        return f"{name}:{int(start) + 1}-{start}:1/INS"
    raise ValueError(f"unknown sv_type {sv_type!r} (expected deletion or insertion)")


def query_vep(server, chrom, start, end, sv_type):
    """Return (most severe consequence, canonical transcript consequences) from VEP."""
    query = urllib.parse.urlencode(
        [("canonical", "1"), ("content-type", "application/json")]
    )
    region = vep_region(chrom, start, end, sv_type)
    results = fetch_json(f"{server}/vep/human/region/{region}?{query}")
    if not results:
        return ".", "."
    result = results[0]
    canonical = sorted(
        {
            f"{item.get('gene_symbol') or item['gene_id']}:{','.join(item['consequence_terms'])}"
            for item in result.get("transcript_consequences", [])
            if item.get("canonical")
        }
    )
    return result.get("most_severe_consequence", "."), (";".join(canonical) or ".")


def annotate_rows(rows, server, pause, use_vep):
    """Return (extra column names, per-row extra values) for rows with chrom/start/end."""
    cache = {}
    vep_cache = {}
    for row in rows:
        key = (row["chrom"], row["start"], row["end"])
        if key not in cache:
            cache[key] = safe_query(query_region, 2, server, *key)
            time.sleep(pause)
            if len(cache) % 50 == 0:
                print(f"  {len(cache)} regions done", file=sys.stderr)
        vep_key = (*key, row.get("sv_type", ""))
        if use_vep and vep_key not in vep_cache:
            vep_cache[vep_key] = safe_query(query_vep, 2, server, *vep_key)
            time.sleep(pause)
    n_failed = sum(1 for value in cache.values() if value[0] == "ERROR")
    print(
        f"{len(rows)} rows, {len(cache)} regions annotated, {n_failed} regions failed",
        file=sys.stderr,
    )
    names = ["genes", "overlaps_cds"] + (
        ["vep_most_severe", "vep_canonical"] if use_vep else []
    )
    values = []
    for row in rows:
        key = (row["chrom"], row["start"], row["end"])
        extra = list(cache[key])
        if use_vep:
            extra += list(vep_cache[(*key, row["sv_type"])])
        values.append(extra)
    return names, values


def main():
    """Stream the VCF and write one row per homozygous genotype of a rare SV."""
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "vcf", help="merged PanGenie VCF (.vcf or .vcf.gz), or '-' for stdin"
    )
    panel = parser.add_mutually_exclusive_group(required=True)
    panel.add_argument(
        "--panel-vcf", help="panel VCF (.vcf or .vcf.gz) given to PanGenie"
    )
    panel.add_argument(
        "--panel-table", help="panel variant table (.tsv.gz) of the plotting module"
    )
    parser.add_argument("-o", "--output", required=True, help="output TSV")
    parser.add_argument(
        "--max-panel-af",
        type=float,
        default=0.01,
        help="report SVs with a panel AF below this value (default: 0.01)",
    )
    parser.add_argument(
        "--sv-min-length",
        type=int,
        default=50,
        help="minimum |len(ALT) - len(REF)| of an SV (default: 50)",
    )
    parser.add_argument(
        "--max-cohort-af",
        type=float,
        help="only report SVs with a cohort AF of at most this value (default: no filter)",
    )
    parser.add_argument(
        "--min-gq",
        type=float,
        help="only report homozygous genotypes with GQ >= this value (default: no filter)",
    )
    parser.add_argument(
        "--annotate",
        action="store_true",
        help="add overlapping genes (Ensembl REST, internet needed) to the result",
    )
    parser.add_argument(
        "--vep",
        action="store_true",
        help=(
            "with --annotate: also add the Ensembl VEP consequence. VEP gets only the "
            "symbolic alleles DEL/INS: reliable for deletions (overlap-based), only a "
            "rough estimate for insertions (no frame/stop information, as the inserted "
            "sequence is unknown) and for COMPLEX events (treated as plain DEL/INS)"
        ),
    )
    parser.add_argument(
        "--annotate-limit",
        type=int,
        default=500,
        help="refuse to annotate more than this many rows (default: 500)",
    )
    parser.add_argument(
        "--server", default="https://rest.ensembl.org", help="Ensembl REST server"
    )
    args = parser.parse_args()
    if args.vep and not args.annotate:
        parser.error("--vep requires --annotate")

    log(f"Step 1/4: reading the panel AF from {args.panel_vcf or args.panel_table}")
    if args.panel_vcf:
        log("(a panel VCF is large; this can take several minutes)")
        rare_panel = load_rare_panel_svs_from_vcf(
            args.panel_vcf, args.sv_min_length, args.max_panel_af
        )
    else:
        rare_panel = load_rare_panel_svs(
            args.panel_table, args.sv_min_length, args.max_panel_af
        )

    log(f"Step 2/4: scanning the cohort VCF {args.vcf}")
    samples = []
    n_records = n_svs = n_rare = n_reported = 0
    table = []
    with open_vcf(args.vcf) as vcf:
        for line in vcf:
            if line.startswith("##"):
                continue
            fields = line.rstrip("\n").split("\t")
            if line.startswith("#CHROM"):
                samples = fields[9:]
                log(f"{len(samples)} samples in the cohort VCF")
                continue
            n_records += 1
            if n_records % 500_000 == 0:
                log(f"  {n_records} VCF records scanned, {len(table)} rows so far")
            chrom, pos, var_id, ref, alt = fields[:5]
            ilen = len(alt) - len(ref)
            if "," in alt or abs(ilen) < args.sv_min_length:
                continue
            n_svs += 1
            panel_af = rare_panel.get(var_id)
            if panel_af is None:
                continue
            n_rare += 1
            format_keys = fields[8].split(":")
            gt_index = format_keys.index("GT")
            gq_index = format_keys.index("GQ") if "GQ" in format_keys else None

            n_called = n_alt_alleles = n_het = 0
            hom_samples = []
            for sample, sample_field in zip(samples, fields[9:], strict=True):
                values = sample_field.split(":")
                alleles = genotype_alleles(values[gt_index])
                called = [allele for allele in alleles if allele != "."]
                n_called += len(called)
                n_alt_alleles += called.count("1")
                if len(alleles) == 2 and set(alleles) == {"0", "1"}:
                    n_het += 1
                elif alleles == ["1", "1"]:
                    gq = "NA"
                    if gq_index is not None and gq_index < len(values):
                        gq = "NA" if values[gq_index] == "." else values[gq_index]
                    hom_samples.append((sample, gq))
            if not hom_samples:
                continue
            n_reported += 1
            cohort_af = f"{n_alt_alleles / n_called:.4f}" if n_called else "NA"
            if args.max_cohort_af is not None and (
                cohort_af == "NA" or float(cohort_af) > args.max_cohort_af
            ):
                continue
            sv_type = "deletion" if ilen < 0 else "insertion"
            end = int(pos) + len(ref) - 1
            short_id = f"{chrom}-{pos}-{sv_type[:3].upper()}-{abs(ilen)}"
            for sample, gq in hom_samples:
                if args.min_gq is not None and (gq == "NA" or float(gq) < args.min_gq):
                    continue
                table.append(
                    dict(
                        zip(
                            HEADER,
                            [
                                short_id,
                                chrom,
                                pos,
                                end,
                                sv_type,
                                abs(ilen),
                                f"{panel_af:.5f}",
                                cohort_af,
                                n_called // 2,
                                n_het,
                                len(hom_samples),
                                sample,
                                gq,
                                var_id,
                            ],
                            strict=True,
                        )
                    )
                )

    log(f"Scan finished: {len(table)} rows left after the filters")
    extra_names, extras = [], [[] for _ in table]
    if not args.annotate:
        log("Step 3/4: gene annotation skipped (--annotate not given)")
    elif len(table) <= args.annotate_limit:
        log(
            f"Step 3/4: annotating {len(table)} rows via {args.server} (needs internet)"
        )
    if args.annotate and len(table) > args.annotate_limit:
        print(
            f"WARNING: {len(table)} rows exceed --annotate-limit {args.annotate_limit}; "
            "NOT annotated. Filter further (--max-cohort-af, --min-gq) or raise the limit.",
            file=sys.stderr,
        )
    elif args.annotate:
        extra_names, extras = annotate_rows(table, args.server, 0.1, args.vep)

    log(f"Step 4/4: writing {args.output}")
    with open(args.output, "w", encoding="utf-8", newline="") as out:
        writer = csv.writer(out, delimiter="\t", lineterminator="\n")
        writer.writerow([*HEADER[:-1], *extra_names, HEADER[-1]])
        for row, extra in zip(table, extras, strict=True):
            writer.writerow(
                [*(row[name] for name in HEADER[:-1]), *extra, row[HEADER[-1]]]
            )
    print(
        f"cohort: {n_svs} SVs in the VCF, {n_rare} with panel AF < {args.max_panel_af}, "
        f"{n_reported} of them homozygous in at least one sample; "
        f"{len(table)} rows written after filters",
        file=sys.stderr,
    )
    print(
        "(SVs not found in the panel table or without panel AF are not reported)",
        file=sys.stderr,
    )
    log("Done")


if __name__ == "__main__":
    main()

# Enhanced Spatial Transcriptomics Analysis Pipeline

---

## Overview

This pipeline processes Stereo-seq spatial transcriptomics data through the following steps:

```
FASTQ Files → SAW Processing → GEF File → Analysis → Results
```

**Spatial Transcriptomics Analysis Framework Components:**
1. **Baseline** - Baseline results
2. **Ensemble Clustering** - Ensemble clustering result
3. **Biological Annotation** - Cell type identification with 248 markers
4. **Knowledge-Based Clustering** - Biology-guided analysis
5. **AI Agent** - Self-directed hypothesis testing

---

## Installation

### 1. Clone This Repository

```bash
git clone <this-repo-url>
cd "Spatial Transcriptomics Analysis"
```

All five analysis scripts (`baseline.py`, `ensemble_clustering.py`, `annotator.py`, `ai_agent.py`, `ovarian_knowledge_base.py`) live at the repository root — no additional setup needed to place them.

### 2. Install Conda (skip if you already have it)

Check first:

```bash
conda --version
```

If that command isn't found, install Miniconda:

- **macOS (Homebrew):** `brew install --cask miniconda`
- **macOS / Linux (official installer, no Homebrew):** https://docs.conda.io/en/latest/miniconda.html
- **Windows:** download the installer from the same page and run it.

After installing, restart your terminal (or run `conda init <your-shell-name>`, e.g. `conda init zsh`, then reopen your terminal) so the `conda` command is available.

### 3. Set Up the Environment (conda, recommended)

The pipeline's dependencies include compiled/native libraries (e.g. `h5py` links against HDF5), so **conda is the recommended way to install**, since it resolves those system-level dependencies automatically:

```bash
conda env create -f environment.yml
conda activate spatial-transcriptomics
```

This creates an isolated environment named `spatial-transcriptomics` with Python 3.11 and every dependency pinned to the exact tested version.

Then install the package itself (registers the scripts as importable modules, so they can also be run as `python -m baseline ...`, etc.):

```bash
pip install .
```

<details>
<summary>Alternative: pip + venv</summary>

```bash
python -m venv .venv
source .venv/bin/activate  # Linux/Mac
# OR
.venv\Scripts\activate     # Windows

pip install -r requirements.txt
```

Note: this does not manage non-Python system dependencies, so you may need HDF5 installed separately depending on your OS.
</details>

### 4. Verify Installation

```bash
# Check Python version (3.9+ required; environment.yml installs 3.11)
python --version

# Check package installations
python -c "import numpy, pandas, scipy, sklearn, h5py, umap; print('All packages installed!')"
```

### 5. (Optional) Stereo-seq SAW Pipeline

Only needed if you're starting from raw FASTQ files rather than an existing GEF file (see Step 1 below).

```bash
# Visit: https://github.com/STOmics/SAW
# Follow installation instructions for your system

# For Linux/macOS:
git clone https://github.com/STOmics/SAW.git
cd SAW
# Follow the installation guide in their README

saw --version # Should be 7.1+
```

---

## Pipeline Steps

### Step 1: Process FASTQ Files with SAW

**Input:** Raw FASTQ files from Stereo-seq sequencing

**SAW Documentation:** https://github.com/STOmics/SAW

#### 1.1 Prepare Input Files

Your FASTQ files should follow Stereo-seq format ():
```
sample_R1.fastq.gz  # Read 1: Contains barcode + UMI
sample_R2.fastq.gz  # Read 2: Contains cDNA sequence
```

#### 1.2 Create SAW Configuration File

Create `config.json`:
```json
{
  "input": {
    "read1": "path/to/sample_R1.fastq.gz",
    "read2": "path/to/sample_R2.fastq.gz",
    "reference": "path/to/reference_genome"
  },
  "output": {
    "outdir": "saw_output"
  },
  "chemistry": "Stereo-seq",
  "threads": 8
}
```

#### 1.3 Run SAW Pipeline

```bash
# Basic SAW command
saw run \
  --config config.json \
  --outdir saw_output \
  --threads 8

# This will produce several files including:
# - cellbin.gef 
# - QC reports
# - Expression matrices
```

**Processing Time:** 5+ hours depending on data size and computer

---

### Step 2: Generate GEF File

#### 2.1 Locate GEF File

After SAW completes, find your GEF file:
```bash
# Default location
ls saw_output/*.gef

# Example output:
# saw_output/B04372C211.adjusted.cellbin.gef
```

#### 2.2 Copy GEF File to Working Directory

```bash
# Copy to your analysis directory
cp saw_output/*.gef ./input_data.gef
```

**Note:** If you already have a GEF file, you can skip Step 1 entirely and start here! 

GEF file link for mouse ovarian tissue (for SJSU account): https://drive.google.com/file/d/1KTiaVZ6b734-6N9xbdI6t9Vx9xXRuOuu/view?usp=sharing

---

### Step 3: Run Spatial Transcriptomics Analysis

Every script accepts `--input` and `--output` flags, so no source-code editing is required to point them at your own GEF file. If you omit `--input`, each script falls back to (in order) the `$ST_INPUT_GEF` environment variable, then a built-in default. Run `python <script>.py --help` for the full list of options on any script.

**Output goes to `output/<stage>/<run timestamp>/` by default** (e.g. `output/ensemble/20260727_140512/`) if you don't pass `--output` — so re-running the pipeline never silently overwrites a previous run's results. All stages run together via `run_pipeline.sh` or `watch_runner.py` share one timestamp, so a full run's results all land under the same `<run timestamp>` across `output/baseline/`, `output/ensemble/`, `output/annotator/`, and `output/agent/`. Override with `--output some/path` (or `$ST_OUTPUT_DIR`) if you want a fixed location instead.

All commands below assume your GEF file is at `./input_data.gef` and that you've activated the conda environment from Step 2.

**Shortcut:** rather than running each script individually, `./run_pipeline.sh` chains 3.2-3.4 (ensemble → annotation → agent) automatically in the required order. For fully automatic, ongoing analysis — drop a new `.gef` file into the project folder and it runs and notifies you when done, no manual invocation needed — run `python watch_runner.py` (cross-platform: macOS, Linux, Windows) and leave it running; see [AI_AGENT_DEPLOY.md](AI_AGENT_DEPLOY.md) for full setup, including running it as a persistent background service. The individual commands below are for running or debugging a single stage on its own.

#### 3.1 Run Baseline Clustering (optional, for comparison)

`baseline.py` is a standalone reference clustering method, not part of the required pipeline chain — its results are used only to benchmark how much the ensemble method (3.2) improves on a simpler baseline (see the Expected Results table below). It's not required to produce annotation or agent results.

```bash
python baseline.py --input input_data.gef

# Output: output/baseline/<run timestamp>/
# - recursive clustering results (JSON) and summary report
```

**Time:** ~10-15 minutes

#### 3.2 Run Ensemble Clustering

```bash
python ensemble_clustering.py --input input_data.gef

# Output: output/ensemble/<run timestamp>/
# - ensemble_results.json
# - clustering_analysis.png
# - comprehensive_report.txt
```

**Time:** 30-60 minutes (depending on cell count and computer). Use `--max-cells` to cap the number of cells analyzed for a faster run.

#### 3.3 Run Knowledge-Based Biological Annotation

```bash
python annotator.py --input input_data.gef

# Output: output/annotator/<run timestamp>/
# - cell_type_assignments.csv
# - marker_detection_report.txt
# - spatial_coherence_analysis.json
```

**Time:** ~20 minutes

#### 3.4 Run the Autonomous AI Agent (agentic analysis)

The AI agent generates and tests its own biological hypotheses using an LLM. This step is **optional** and separate from Steps 3.1-3.3, which run and produce full results with no LLM involved.

**Requirements:** an OpenAI API key (the agent auto-disables LLM assistance and falls back to non-LLM analysis if no key is provided). Set it either as an environment variable or a flag:

```bash
# Option A: environment variable
export OPENAI_API_KEY="sk-..."
python ai_agent.py --input input_data.gef

# Option B: command-line flag
python ai_agent.py --input input_data.gef --api-key "sk-..."

# Output: output/agent/<run timestamp>/
# - autonomous_discoveries.json
# - autonomous_discovery_report.txt
# - hypothesis_validation_results.json
```

**Time:** 10-20 minutes. Use `--max-iterations` to control how many hypothesis generate/test cycles the agent runs (default: 5).

For fully automated, ongoing deployment of the AI agent (e.g. auto-run on new datasets), see [AI_AGENT_DEPLOY.md](AI_AGENT_DEPLOY.md).

---

## Project Structure

```
Spatial Transcriptomics Analysis/
├── README.md                          # This file
├── environment.yml                    # Conda environment spec (recommended)
├── requirements.txt                   # Pinned pip dependencies (fallback)
├── LICENSE
│
├── baseline.py                        # Step 3.1
├── ensemble_clustering.py             # Step 3.2
├── annotator.py                       # Step 3.3
├── ovarian_knowledge_base.py          # Marker/pathway knowledge base (imported by annotator.py)
├── ai_agent.py                        # Step 3.4 (agentic analysis)
│
├── run_pipeline.sh                    # Shortcut: runs 3.2-3.4 in order (macOS/Linux)
├── watch_runner.py                    # Cross-platform automatic watcher (see AI_AGENT_DEPLOY.md)
├── notify.py                          # Desktop/email notifications (used by the watchers)
├── deploy/                            # Background-service templates (launchd, systemd)
│
├── input_data.gef                     # Your GEF file (not included; see Step 2 above)
├── output/                            # All results, grouped by stage then run
│   ├── baseline/<run timestamp>/
│   ├── ensemble/<run timestamp>/
│   ├── annotator/<run timestamp>/
│   └── agent/<run timestamp>/
```

---

## Dependencies

See `environment.yml` (conda, recommended) or `requirements.txt` (pip) for the exact pinned versions used and tested:

```
h5py==3.14.0
llvmlite==0.43.0
matplotlib==3.9.4
numba==0.60.0
numpy==2.0.2
openai==2.43.0
pandas==2.3.3
pynndescent==0.6.0
scikit-learn==1.6.1
scipy==1.13.1
seaborn==0.13.2
umap-learn==0.5.12
```

Requires Python 3.9+ (numpy 2.x requirement); `environment.yml` installs 3.11.

---

## Expected Results Summary (number might change slightly for each run)

### Spatial Transcriptomics Analysis Framework Performance:

| Component | Metric | Value | vs. Baseline |
|-----------|--------|-------|--------------|
| **Ensemble** | Silhouette | 0.540 | +56.8% |
| **Ensemble** | Methods | 3 combined | N/A |
| **Ensemble** | Time | 3,094s | - |
| **Annotation** | Success Rate | 88.6% | ∞ (0%→88.6%) |
| **Annotation** | Cell Types | 10 | N/A |
| **Agent** | Hypotheses | 3 | 100% validated |
| **Agent** | Confidence | High | 3/3 discoveries |

---

## Visualizations

### Ensemble Clustering

![Comprehensive Ensemble Clustering Analysis](docs/images/comprehensive_clustering_analysis.png)
*Silhouette scores, cluster counts, execution time, and ensemble improvement across kmeans, DBSCAN, hierarchical, and Gaussian mixture methods.*

![Method Diversity and Quality](docs/images/method_diversity_quality.png)
*Method similarity (ARI) and quality metrics (Silhouette, Calinski-Harabasz, Davies-Bouldin) across clustering methods.*

### Biological Annotation

![Annotation Overview](docs/images/annotation_overview.png)
*Cell type spatial distribution, proportions, assignment quality, confidence scores, and marker gene detection across 24,930 analyzed cells.*

![Cell Type Assignments](docs/images/cell_type_assignments.png)
*Spatial map of assigned cell types across the tissue section, including granulosa cells, oocytes, theca cells, stromal fibroblasts, and immune populations.*

![Confidence Analysis](docs/images/confidence_analysis.png)
*Spatial and distribution view of assignment confidence scores.*

### Anatomical & Spatial Structure

![Anatomical Structures](docs/images/anatomical_structures.png)
*Identified anatomical structures including primordial, primary, secondary, and antral follicles, and corpus luteum structures.*

![Spatial Organization](docs/images/spatial_organization.png)
*Local cell density map and cell type centroids across the tissue.*

---

## AI Agent: How It Thinks (Example Hypotheses)

The AI agent doesn't just cluster cells — it proposes an idea about the biology, tests it statistically, and then explains what the result might mean, in plain language. Two examples of what this looks like in practice:

**Example 1: Cell subpopulations**

- *Hypothesis generated:* "Cells cluster into transcriptionally distinct groups that may represent different cell types or states."
- *What the agent did:* Ran PCA + K-means clustering and checked how well-separated the resulting groups were (silhouette score ≈ 0.40, high confidence).
- *Biological explanation:* This pattern is consistent with the tissue containing several different, specialized cell types — for example granulosa cells, theca cells, and oocytes in an ovarian follicle — each with its own distinct gene activity "fingerprint" rather than one uniform cell population.

**Example 2: Localized anomaly / signaling dysregulation**

- *Hypothesis generated:* "The detected anomaly in the dataset corresponds to a localized dysregulation of a specific signalling pathway that drives aberrant cellular behaviour in a subset of cells."
- *What the agent did:* Flagged a small group of cells whose expression didn't match the surrounding tissue, then ran anomaly detection and characterization on that subset.
- *Biological explanation:* A handful of cells are behaving differently from their neighbors, which could point to a signaling pathway (the chemical messages cells use to coordinate) switching on or off abnormally in that spot — for instance, in a follicle undergoing degeneration or a region responding to local stress.

In short: the **Hypothesis Generator** proposes the "what if," the **Analysis Planner/Executor** tests it with the right statistics, and the **Result Interpreter** translates the numbers back into a biological story a reader can follow.

---

## License

Spatial Transcriptomics Analysis Enhanced Framework - released under the [MIT License](LICENSE). Freely usable, modifiable, and redistributable, including for commercial purposes, provided the copyright notice is retained.

Note: this license covers the analysis scripts in this repository only. SAW (used for FASTQ processing, Step 1) is a separate third-party tool — check the [STOmics/SAW repository](https://github.com/STOmics/SAW) for its license terms.

---

For instructions on how to install an AI agent for automatic running of the pipeline and generating and testing hypotheses, please see [AI_AGENT_DEPLOY.md](AI_AGENT_DEPLOY.md).

## Based On

Maiqi Zhang, *Enhanced Autonomous Spatial Transcriptomics Analysis*, MS Thesis, San Jose State University, 2026. Advisor: Dr. William B. Andreopoulos.

---

This file was written and maintained by Minjun Roe.
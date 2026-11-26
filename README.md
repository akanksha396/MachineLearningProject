
from pathlib import Path
import shutil
import json
import sys
import platform
import hashlib
import subprocess
import zipfile
from datetime import datetime, timezone
from importlib.metadata import version, PackageNotFoundError

import pandas as pd

ROOT = Path(
    r"C:\Users\akshi\Desktop\phd-iit-jodhpur\Semester-1\Machine Learning"
)

PACKAGE = ROOT / "hcp-cognitive-task-decoding"
ZIP_PATH = ROOT / "hcp-cognitive-task-decoding.zip"

if not ROOT.is_dir():
    raise FileNotFoundError(ROOT)

# Never overwrite an existing packaged project.
if PACKAGE.exists() or ZIP_PATH.exists():
    raise FileExistsError(
        "Submission folder or ZIP already exists. "
        "Rename or move the previous package before rebuilding."
    )

required = {
    "notebooks/MachineLearningProject.ipynb":
        "MachineLearningProject(1).ipynb",
    "matlab/fMRI_timeseriesextraction_FINAL.m":
        "fMRI_timeseriesextraction_FINAL.m",
    "matlab/fMRI_EV_extraction_FINAL.m":
        "fMRI_EV_extraction_FINAL.m",
    "matlab/regressor_allTasks_FINAL_updated.m":
        "regressor_allTasks_FINAL_updated.m",
    "results/all_roi_fold_scores.csv":
        "all_roi_fold_scores.csv",
    "results/roi_ablation_fold_scores.csv":
        "roi_ablation_fold_scores.csv",
}

# Look in ROOT and its results directory.
def locate(name):
    candidates = [
        ROOT / name,
        ROOT / "results" / name
    ]
    return next((p for p in candidates if p.is_file()), None)

missing = [
    name for name in required.values()
    if locate(name) is None
]

if missing:
    raise FileNotFoundError(
        "Put these files in the project folder first:\n"
        + "\n".join(missing)
    )

PACKAGE.mkdir()

for destination, source in required.items():
    target = PACKAGE / destination
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(locate(source), target)

# Clear saved notebook outputs to avoid publishing
# hidden local paths or participant identifiers.
nb_path = PACKAGE / "notebooks/MachineLearningProject.ipynb"
with open(nb_path, encoding="utf-8") as f:
    notebook = json.load(f)

for cell in notebook["cells"]:
    if cell["cell_type"] == "code":
        cell["outputs"] = []
        cell["execution_count"] = None

with open(nb_path, "w", encoding="utf-8") as f:
    json.dump(notebook, f, indent=1, ensure_ascii=False)

# Reproducibility results: aggregate fold scores.
# Individual-level outputs are pseudonymized below.
extra_csv = [
    "all_roi_predictions.csv",
    "all_roi_subject_scores.csv",
    "roi_ablation_predictions.csv",
    "hcp_block_metadata.csv"
]

# Create a consistent, package-local subject code.
subject_ids = set()
for name in extra_csv:
    source = locate(name)
    if source:
        df = pd.read_csv(source, dtype={"subject": str})
        if "subject" in df.columns:
            subject_ids.update(df["subject"].dropna().tolist())

subject_map = {
    sid: f"subject_{i:03d}"
    for i, sid in enumerate(sorted(subject_ids), start=1)
}

for name in extra_csv:
    source = locate(name)
    if source is None:
        continue

    df = pd.read_csv(source, dtype={"subject": str})

    if "subject" in df.columns:
        df["subject"] = df["subject"].map(subject_map)

    df.to_csv(PACKAGE / "results" / name, index=False)

# Add the three visualizations if present.
figures = {
    "ProjOutput3.png": "model_comparison.png",
    "ProjOutput1.png": "logreg_roi_ablation.png",
    "ProjOutput2.png": "svm_roi_ablation.png"
}

(PACKAGE / "figures").mkdir(exist_ok=True)

for source_name, target_name in figures.items():
    source = locate(source_name)
    if source:
        shutil.copy2(source, PACKAGE / "figures" / target_name)

# Record available dependency versions.
dependencies = [
    "numpy", "scipy", "pandas", "scikit-learn",
    "matplotlib", "seaborn", "jupyter", "ipykernel"
]

requirements = []
for name in dependencies:
    try:
        requirements.append(f"{name}=={version(name)}")
    except PackageNotFoundError:
        requirements.append(name)

(PACKAGE / "requirements.txt").write_text(
    "\n".join(requirements) + "\n",
    encoding="utf-8"
)

(PACKAGE / "environment.yml").write_text(
    "name: hcp-task-decoding\n"
    "channels:\n"
    "  - conda-forge\n"
    "dependencies:\n"
    f"  - python={sys.version_info.major}.{sys.version_info.minor}\n"
    "  - pip\n"
    "  - pip:\n"
    + "".join(f"      - {p}\n" for p in requirements),
    encoding="utf-8"
)

(PACKAGE / "environment_snapshot.json").write_text(
    json.dumps({
        "python": sys.version,
        "platform": platform.platform(),
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "dependencies": requirements
    }, indent=2),
    encoding="utf-8"
)

(PACKAGE / ".gitignore").write_text(
    "__pycache__/\n"
    ".ipynb_checkpoints/\n"
    ".venv/\n"
    "*.pyc\n"
    "*.mat\n"
    "*.nii\n"
    "*.nii.gz\n"
    "*.zip\n"
    "*.npy\n"
    "*.npz\n"
    "*.joblib\n"
    "*.pkl\n"
    "data/*\n"
    "!data/README.md\n",
    encoding="utf-8"
)

(PACKAGE / "data").mkdir()

(PACKAGE / "data/README.md").write_text(
    "# Dataset\n\n"
    "The original HCP data and the derived "
    "Unrelated100_RestTask.mat file are NOT distributed.\n\n"
    "Obtain access through the authorized HCP data provider "
    "or from the dataset custodian with appropriate permissions.\n"
    "Place the required MAT file in this directory and update "
    "the notebook's input path accordingly.\n\n"
    "The MATLAB raw-data extraction scripts also require "
    "the original HCP archives, atlas NIfTI files, "
    "SPM12, and tfMRI_Concat_Runs.csv.\n",
    encoding="utf-8"
)

(PACKAGE / "README.md").write_text(
    """# HCP Cognitive Task Decoding

## Research question
Do subcortical and cerebellar ROIs provide additional
predictive information beyond cortical activity?

## Authors
Akanksha Tiwari (p26ai0002)
Garima Bargujar (p25ai0003)
Soni Kumari (p26cs0011)

Indian Institute of Technology Jodhpur

## Experiments
- 31 participants
- 180 ROIs: 54 subcortical, 100 cortical, 26 cerebellar
- Six tasks: WM, GAM, REL, LAN, MOT, EMO
- 2,810 extracted task blocks
- Logistic Regression and Linear SVM
- Nested subject-wise cross-validation:
  five outer folds and four inner folds
- Balanced accuracy and macro-F1

## Installation
Create a Python virtual environment and run:

    python -m pip install -r requirements.txt

Start Jupyter:

    jupyter notebook notebooks/MachineLearningProject.ipynb

Update the MAT-file path in the notebook to point to
your authorized local dataset copy.

Run notebook cells in order. The notebook is the
reference implementation of the reported experiments.

## MATLAB preprocessing
The original scripts are in matlab/.
They require MATLAB, SPM12, HCP source archives,
atlas NIfTI files, and tfMRI_Concat_Runs.csv.

They currently contain paths from their original
development environment; adapt them to local paths
before running. Do not execute them against the
only copy of an existing dataset.

Execution order:
1. fMRI_timeseriesextraction_FINAL.m
2. fMRI_EV_extraction_FINAL.m
3. regressor_allTasks_FINAL_updated.m

These scripts are retained as source provenance,
not as independently validated portable executables.

## Results
Aggregated results are under results/.
Three plots may be available in figures/.

## Important limitations
The notebook sets the task/run mapping using manually
confirmed flags. Verify the mapping against the original
tfMRI_Concat_Runs.csv before claiming full reproducibility.

The MATLAB scripts establish the expected ROI ordering:
subcortex 0-53, cortex 54-153, cerebellum 154-179
(Python zero-based indices).

Formal corrected statistical tests and size-matched
random-ROI controls have not been reported.

Shapley attribution and group dropout are proposed
extensions, not implemented experimental results.

See REPRODUCIBILITY.md and EXPERIMENT_STATUS.md.
""",
    encoding="utf-8"
)

(PACKAGE / "REPRODUCIBILITY.md").write_text(
    """# Reproducibility Declaration

We provide the source notebook, original MATLAB
preprocessing scripts, environment requirements,
aggregate fold-level results, and available figures.

The supplied notebook records experiments using
nested grouped cross-validation on 31 participants.

The dataset is excluded from the public repository.
Reproduction requires an independently authorized
copy of the HCP-derived data.

The original MATLAB pipeline additionally depends
on MATLAB, SPM12, atlas files and the run-info CSV.

The original notebook contains manual task/run
confirmation settings. This repository does not
claim fully automated independent verification
of those mappings.

No trained model checkpoints were supplied.
The experiments retrain models within each fold.

The included CSV files contain saved results, not
independent evidence of a successful rerun on
another machine.

Exact reproduction requires the same data,
correct extraction mapping, software environment,
and subject-wise validation procedure.

Declaration: The supplied sources and outputs
reflect the available project artifacts. The
package does not claim completion of unexecuted
Shapley attribution, group dropout, statistical
testing, or robustness experiments.
""",
    encoding="utf-8"
)

(PACKAGE / "EXPERIMENT_STATUS.md").write_text(
    """# Experiment Status

## Available
- Dataset inspection and quality checks
- Block-level activity features
- Six-task Logistic Regression and Linear SVM
- Nested subject-wise cross-validation
- Six ROI configurations
- Fold scores and held-out predictions

## Pending
- Independent task/run mapping audit
- External reproduction on a fresh environment
- Size-corrected Shapley attribution
- Subcortex + cerebellum coalition
- Missing-feature group dropout
- Random-ROI size controls
- Corrected statistical testing

No performance results are claimed for pending work.
""",
    encoding="utf-8"
)

(PACKAGE / "MODEL_CHECKPOINTS.md").write_text(
    """# Model Checkpoints

No trained model checkpoint files were supplied.

Logistic Regression and Linear SVM models are trained
inside the nested cross-validation process.

The saved experiment artifacts consist of held-out
predictions and fold-level evaluation results.

A future release may save per-fold fitted estimators
with their preprocessing pipeline, parameter settings,
software versions and data provenance.

There is currently no verified Hugging Face checkpoint
URL. None is invented.
""",
    encoding="utf-8"
)

(PACKAGE / "CITATION.cff").write_text(
    """cff-version: 1.2.0
message: "Please cite this repository if you use this work."
title: "Do Subcortical and Cerebellar Regions Improve Cognitive Task Decoding Beyond Cortex?"
type: software
authors:
  - family-names: Tiwari
    given-names: Akanksha
  - family-names: Bargujar
    given-names: Garima
  - family-names: Kumari
    given-names: Soni
""",
    encoding="utf-8"
)

# Generate SHA-256 checksums for all packaged files.
manifest = {}

for file in sorted(PACKAGE.rglob("*")):
    if file.is_file():
        relative = file.relative_to(PACKAGE).as_posix()
        manifest[relative] = hashlib.sha256(
            file.read_bytes()
        ).hexdigest()

(PACKAGE / "SHA256SUMS.json").write_text(
    json.dumps(manifest, indent=2),
    encoding="utf-8"
)

# Create the final ZIP.
with zipfile.ZipFile(
    ZIP_PATH, "w", zipfile.ZIP_DEFLATED
) as archive:
    for file in sorted(PACKAGE.rglob("*")):
        if file.is_file():
            archive.write(
                file,
                arcname=str(file.relative_to(ROOT))
            )

# Check ZIP integrity.
with zipfile.ZipFile(ZIP_PATH) as archive:
    damaged = archive.testzip()

assert damaged is None, f"Corrupt archive member: {damaged}"

print("Package created:", PACKAGE)
print("ZIP created:", ZIP_PATH)
print("ZIP size (MB):", round(
    ZIP_PATH.stat().st_size / 1024**2, 2
))
print("Files packaged:", len(manifest) + 1)
```

This creates `hcp-cognitive-task-decoding.zip` in your Machine Learning folder. The script does not generate Git commit history because genuine commit hashes exist only after Git commits have been created.

## Create the GitHub repository and commit history

After running the packaging code, open a terminal in the newly created `hcp-cognitive-task-decoding` folder.

Run:

```bash
git init
git add .
git commit -m "Initial reproducible HCP task-decoding project"
git log --format="%H | %aI | %an | %s"
```

The last command prints actual commit hashes, ISO-8601 timestamps, authors and commit messages.

To save a history snapshot:

```bash
git log --format="%H | %aI | %an | %s" > git_history.txt
git add git_history.txt
git commit -m "Add initial commit provenance"
```

The GitHub repository's own commit history remains the authoritative record, including the later commit that added `git_history.txt`.

Create an empty GitHub repository, then connect and push your local repository using its real URL:

```bash
git branch -M main
git remote add origin YOUR_GITHUB_REPOSITORY_URL
git push -u origin main
```

## Final submission assessment

Your available materials support a legitimate code-and-results repository. The package generator includes the required environment files, original MATLAB scripts, notebook, result artifacts, reproducibility declaration and checkpoint justification.

Two limitations must remain explicit: **a fully independent raw-data reproduction still needs the source data and run-information CSV**, and **the Shapley attribution and group-dropout extensions have not yet been executed**.

Do not present either as completed in the GitHub README.

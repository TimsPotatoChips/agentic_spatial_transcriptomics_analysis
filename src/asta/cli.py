"""Console-script entry points for ASTA.

Each function below runs the corresponding module exactly as
``python -m asta.<module>`` would, so the module's own
``if __name__ == "__main__":`` block (and its existing argparse CLI)
keeps working completely unchanged.
"""

import runpy


def baseline():
    runpy.run_module("asta.baseline", run_name="__main__", alter_sys=True)


def ensemble():
    runpy.run_module("asta.ensemble_clustering", run_name="__main__", alter_sys=True)


def annotate():
    runpy.run_module("asta.annotator", run_name="__main__", alter_sys=True)


def agent():
    runpy.run_module("asta.ai_agent", run_name="__main__", alter_sys=True)


def notify():
    runpy.run_module("asta.notify", run_name="__main__", alter_sys=True)

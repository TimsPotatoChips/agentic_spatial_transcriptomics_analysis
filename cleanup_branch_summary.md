# Cleanup Branch — Summary

## Environment & Installation
1. Added a one-command setup (a conda environment file) so installing all required dependencies takes one step instead of manually installing each package.
2. Made the package properly installable in one command instead of requiring files to be copied by hand.

## Usability
3. Added command-line options (`--input`, `--output`) to every script, so anyone can point the pipeline at their own data file without opening and editing the code.
4. Changed how results are saved — output is now grouped by run (each run gets its own timestamped folder), with that run's clustering, annotation, and AI agent results all kept together inside it. This means running the pipeline again never overwrites previous results, and everything produced by a single run is easy to find in one place instead of scattered across separate stage folders.

## License
5. Fixed a contradiction between the license file (MIT, fully open) and the README (which said "Academic Use Only") — both now agree it's MIT.

## Documentation
6. Rewrote the README with exact, step-by-step install and run instructions for every stage of the pipeline, including how to install the required tools if you don't already have them.
7. Explained clearly why there are two different automatic-run options and which one to use depending on your situation, including documenting a terminal-based chat option for the OpenClaw setup (in addition to the browser dashboard) for anyone who'd rather not keep a browser tab open.

## Testing
8. Added an automated test suite plus GitHub's continuous integration (CI) — a check that automatically runs every time the code changes, to catch anything broken.

## Cross-Platform Automation
9. Built a new automatic "watcher" that runs the full pipeline on its own whenever a new data file shows up, and made it work on any operating system (previously it only worked on macOS through a separate tool called OpenClaw).

## Audit & Cleanup
10. Audited the whole codebase for things that only worked because they were tied to one specific computer: a hardcoded file path, leftover references to an old class/course code, and log files that had accidentally been saved with a personal folder path inside them.
11. Fixed a bug where the background automation was silently falling back to an older, inconsistent setup instead of the new standardized one.
12. Deleted leftover test files created while verifying things worked.
